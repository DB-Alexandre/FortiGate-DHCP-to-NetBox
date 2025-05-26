#!/bin/bash

# === CONFIGURATION ===
FORTI_HOST="TON_URL_FORTI:PORT"
FORTI_API_KEY="TON_API_KEY_FORTI"
NETBOX_HOST="TON_URL_NETBOX:PORT"
NETBOX_API_KEY="TON_API_KEY_NETBOX"
SLUG="rserv"

# === DÉPENDANCES REQUISES ===
command -v jq >/dev/null || {
  echo "❌ jq manquant."
  exit 1
}
command -v ipcalc >/dev/null || {
  echo "❌ ipcalc manquant."
  exit 1
}

# === RÉCUPÉRATION DES BAUX DHCP ===
echo "[INFO] Récupération des baux DHCP depuis FortiGate..."

LEASES=$(curl -s -k -H "Authorization: Bearer $FORTI_API_KEY" "$FORTI_HOST/api/v2/monitor/system/dhcp")

if [[ -z "$LEASES" ]]; then
  echo "[ERREUR] Impossible de récupérer les baux DHCP."
  exit 1
fi

# === TRAITEMENT DES BAUX ===
echo "$LEASES" | jq -c '.results[]' | while read -r lease; do
  IP=$(echo "$lease" | jq -r '.ip')
  MAC=$(echo "$lease" | jq -r '.mac')
  HOSTNAME=$(echo "$lease" | jq -r '.hostname // "inconnu"')
  IFACE=$(echo "$lease" | jq -r '.interface // "inconnu"')
  NETWORK=$(ipcalc -n "$IP" 255.255.255.0 | grep Network | awk '{print $2}')
  RESERVED=$(echo "$lease" | jq -r '.reserved // false')

  EXPECTED_DESC="DHCP: $HOSTNAME ($MAC) sur $IFACE"
  TAG_IDS="[]"

  if [[ "$RESERVED" == "true" ]]; then
    TAG_LOOKUP=$(curl -s -H "Authorization: Token $NETBOX_API_KEY" "$NETBOX_HOST/api/extras/tags/?slug=$SLUG")
    TAG_ID=$(echo "$TAG_LOOKUP" | jq -r '.results[0].id')
    if [[ "$TAG_ID" != "null" && -n "$TAG_ID" ]]; then
      TAG_IDS="[$TAG_ID]"
    fi
  fi

  echo "[INFO] IP: $IP | MAC: $MAC | Hostname: $HOSTNAME | Interface: $IFACE | Réseau: $NETWORK"

  # === Vérifie si le préfixe réseau existe dans NetBox ===
  PREFIX_CHECK=$(curl -s -H "Authorization: Token $NETBOX_API_KEY" \
    "$NETBOX_HOST/api/ipam/prefixes/?prefix=$NETWORK")
  COUNT=$(echo "$PREFIX_CHECK" | jq -r '.count // 0')

  if [[ "$COUNT" -eq 0 ]]; then
    echo "[ACTION] Création du réseau $NETWORK dans NetBox..."
    curl -s -X POST "$NETBOX_HOST/api/ipam/prefixes/" \
      -H "Authorization: Token $NETBOX_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"prefix\": \"$NETWORK\", \"description\": \"Importé depuis FortiGate\"}" >/dev/null
  fi

  # === Recherche IP dans toutes les pages NetBox ===
  PAGE_URL="$NETBOX_HOST/api/ipam/ip-addresses/?limit=100"
  FOUND="false"
  MATCHED_ID=""
  CURRENT_DESC=""
  CURRENT_TAGS=""
  while [[ "$PAGE_URL" != "null" ]]; do
    RESPONSE=$(curl -s -H "Authorization: Token $NETBOX_API_KEY" "$PAGE_URL")
    MATCH=$(echo "$RESPONSE" | jq -c --arg ip "$IP" '.results[] | select(.address | startswith($ip))')
    if [[ -n "$MATCH" ]]; then
      FOUND="true"
      CURRENT_DESC=$(echo "$MATCH" | jq -r '.description // empty')
      CURRENT_TAGS=$(echo "$MATCH" | jq -r '[.tags[]?.id]')
      MATCHED_ID=$(echo "$MATCH" | jq -r '.id')
      break
    fi
    PAGE_URL=$(echo "$RESPONSE" | jq -r '.next')
  done

  if [[ "$FOUND" == "true" ]]; then
    if [[ "$CURRENT_DESC" != "$EXPECTED_DESC" || "$CURRENT_TAGS" != "$TAG_IDS" ]]; then
      echo "[UPDATE] Mise à jour de $IP : description ou tags incorrects. (ID: $MATCHED_ID)"

      PATCH_BODY=$(jq -n --arg desc "$EXPECTED_DESC" --argjson tags "$TAG_IDS" '{description: $desc, tags: $tags}')

      RESPONSE=$(curl -s -w "\n[HTTP_CODE:%{http_code}]\n" -X PATCH "$NETBOX_HOST/api/ipam/ip-addresses/$MATCHED_ID/" \
        -H "Authorization: Token $NETBOX_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$PATCH_BODY")

      HTTP_CODE=$(echo "$RESPONSE" | grep "\[HTTP_CODE:" | sed 's/\[HTTP_CODE://;s/\]//')
      if [[ "$HTTP_CODE" != "200" ]]; then
        echo "[ERREUR] Échec de la mise à jour de $IP (HTTP $HTTP_CODE)"
      fi
    else
      echo "[SKIP] L'IP $IP est déjà à jour."
    fi
  else
    echo "[ACTION] Ajout de l'IP $IP dans NetBox..."

    POST_BODY=$(jq -n \
      --arg addr "$IP/24" \
      --arg status "active" \
      --arg desc "$EXPECTED_DESC" \
      --argjson tags "$TAG_IDS" \
      '{address: $addr, status: $status, description: $desc, tags: $tags}')

    RESPONSE=$(curl -s -w "\n[HTTP_CODE:%{http_code}]\n" -X POST "$NETBOX_HOST/api/ipam/ip-addresses/" \
      -H "Authorization: Token $NETBOX_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$POST_BODY")

    HTTP_CODE=$(echo "$RESPONSE" | grep "\[HTTP_CODE:" | sed 's/\[HTTP_CODE://;s/\]//')
    if [[ "$HTTP_CODE" != "201" ]]; then
      echo "[ERREUR] Échec de l'ajout de $IP (HTTP $HTTP_CODE)"
    fi
  fi

  echo "[OK] IP $IP traitée avec succès."
done

echo "[OK] Synchronisation terminée."
echo "[INFO] Toutes les opérations sont terminées."
# === FIN DU SCRIPT ===

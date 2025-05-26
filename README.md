# Sync FortiGate DHCP Leases to NetBox

Ce script Bash permet de synchroniser automatiquement les baux DHCP actifs de votre FortiGate avec l'outil de gestion d'infrastructure NetBox via son API REST.

---

## Fonctionnalités

* ✨ Récupération automatique des baux DHCP depuis FortiGate (API v2)
* ♻ Déduction automatique du réseau via `ipcalc`
* 📁 Création du préfixe dans NetBox s'il est absent
* ✅ Ajout ou mise à jour de chaque adresse IP dans NetBox avec :

  * Description du type : `DHCP: <hostname> (<mac>) sur <interface>`
  * Tag `RESERVÉE` (slug `rserv`) ajouté si le bail est marqué comme réservé sur FortiGate
  * Retrait automatique du tag si la réservation est supprimée

---

## Prérequis

* Accès API activé sur le FortiGate
* Un token API NetBox avec droits en écriture sur IPAM
* Outils installés sur la machine d'exécution :

  * `jq`
  * `ipcalc`

---

## Installation

1. Clonez ce repo
2. Modifiez les variables `FORTI_HOST`, `FORTI_API_KEY`, `NETBOX_HOST` et `NETBOX_API_KEY` dans le script
3. Rendez le script exécutable :

```bash
chmod +x sync_fortigate_netbox.sh
```

---

## Automatisation (cron)

Pour exécuter toutes les 2h automatiquement :

```bash
crontab -e
```

Ajoutez :

```cron
0 */2 * * * /chemin/vers/sync_fortigate_netbox.sh >> /var/log/netbox_sync.log 2>&1
```

---

## Exemple de sortie

```
[INFO] IP: 192.168.1.100 | MAC: aa:bb:cc:dd:ee:ff | Hostname: poste1 | Interface: port3 | Réseau: 192.168.1.0/24
[ACTION] Ajout de l'IP 192.168.1.100 dans NetBox...
[OK] IP 192.168.1.100 traitée avec succès.
```

---

## Contributions

Les contributions sont les bienvenues !

---

## Licence

Ce projet est fourni sous licence MIT.

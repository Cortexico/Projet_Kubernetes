# Projet Kubernetes : Déploiement Applicatif Multi-composants

## Présentation

Ce projet met en œuvre un déploiement Kubernetes complet d'une application multi-composants (web, base de données répliquée, monitoring, stockage partagé) sur un cluster local (Minikube). Il répond au cahier des charges du sujet de projet (voir `projet_appli_kubernetes.md`).

- **Web-app** : application web (Nginx custom)
- **Sample-app** : application de test (Nginx)
- **Base de données** : MariaDB Galera (répliquée, via Helm)
- **Stockage partagé** : serveur NFS dans un pod (hostPath)
- **Monitoring** : Prometheus + Grafana (Helm)
- **TLS** : cert-manager, certificat autosigné
- **Scalabilité** : HPA, ressources, tests de tolérance

## Architecture

- Déploiement multi-composants (web, sample, DB)
- Base de données répliquée (Galera)
- Stockage partagé via NFS (hostPath sur Minikube)
- Monitoring Prometheus/Grafana
- Ingress + TLS
- RBAC

## Procédure de lancement locale (Minikube)

### 1. Prérequis
- Minikube installé et démarré
- Helm installé
- kubectl installé

### 2. Préparation du volume NFS
```bash
minikube ssh
sudo mkdir -p /nfs-vol
sudo chmod 777 /nfs-vol
exit
```
Ceci n'est évidemment pas "cloud-native" et devrait être porté sur une VM. Pour notre projet nous ferons tout de même comme ceci.

### 3. Build de l'image web-app
```bash
eval $(minikube docker-env)
docker build -t web-app-local:latest .
```

### 4. Lancement automatisé
```bash
chmod +x run_all.sh
./run_all.sh
```
Ce script va :
- Appliquer tous les manifests (NFS, DB, apps, services, ingress, monitoring, etc.)
- Attendre que tout soit prêt
- Lancer la vérification automatisée

### 5. Vérification manuelle
```bash
chmod +x verif_deploiement.sh
./verif_deploiement.sh
```

## Accès aux applications
Lancer la commande suivante dans un invite de commande dédié (opération nécessaire pour valider le script de vérification)

```bash
minikube tunnel
```
- Web-app : https://webapp.localdev.me
- Grafana : https://grafana.localdev.me

## Approche future : migration cloud-native

Pour une stack "production-ready" ou cloud, il faudra :
- Utiliser un vrai serveur NFS externe (VM dédiée, ou service cloud)
- Utiliser le StorageClass `nfs-csi` pour tous les PVC partagés
- Supprimer tout usage de hostPath
- Adapter les manifests pour pointer sur le StorageClass cloud-native

## Structure du projet
- `run_all.sh` : script global de build/déploiement/vérification
- `verif_deploiement.sh` : vérification automatisée
- `deploy_full.sh` : déploiement complet (infra + apps)
- `Dockerfile` : image custom web-app
- `k8s-manifests/` : tous les manifests Kubernetes
- `projet_appli_kubernetes.md` : sujet du projet

## Auteurs
- Hevan
- ...

## Remarques
- Ce projet est conçu pour fonctionner sur Minikube/local. Pour la prod/cloud, voir la section "Approche future". 
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

### Schéma d'architecture multi-composants

L'architecture ci-dessous illustre les différents composants déployés sur le cluster Kubernetes et leurs interactions :

```mermaid
flowchart TD
    subgraph Ingress
        A[webapp.localdev.me] --> B(Web-app Service)
        C[grafana.localdev.me] --> D(Grafana Service)
    end

    B --> E[web-app Pod]
    B --> F[sample-app Pod]
    E --> G[(MariaDB Galera Cluster)]
    F --> G
    G -.-> H[NFS (StorageClass)]
    D --> I[Grafana Pod]
    I --> J[Prometheus Pod]
    J --> K[web-app Pod]
    J --> F

    classDef ingress fill:#f9f,stroke:#333,stroke-width:2px;
    class A,C ingress;
```

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

### Aller plus loin : cluster multi-nœuds (1 control plane, 2-3 workers)

Le sujet demande explicitement un cluster avec 1 control plane et 2 à 3 workers. Minikube ne permet pas nativement ce mode (sauf expérimental), mais il existe plusieurs solutions pour déployer un cluster multi-nœuds sur une seule machine ou sur plusieurs VM :

- **Kind (Kubernetes in Docker)** : permet de simuler plusieurs nœuds (control-plane et workers) dans des conteneurs Docker. [Voir la doc Kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
- **k3d (K3s in Docker)** : permet aussi de simuler un cluster multi-nœuds très léger. [Voir la doc k3d](https://k3d.io/)
- **kubeadm** : pour un vrai cluster sur plusieurs VM (physiques ou virtuelles), en installant manuellement chaque nœud.
- **Cloud providers** : GKE, EKS, AKS, etc. permettent de créer des clusters multi-nœuds en quelques clics.

Pour un usage local ou pédagogique, Minikube reste le plus simple, mais pour répondre strictement au cahier des charges, il est recommandé d'utiliser Kind, k3d ou kubeadm pour simuler ou déployer un cluster multi-nœuds.

### À propos de MetalLB et des environnements on-premise

Le sujet de projet demande l'installation de MetalLB uniquement dans le cas d'un cluster "on-premise" (sur des VM ou serveurs physiques, hors cloud/minikube).
Dans notre projet, le test de la présence de MetalLB est intégré pour couvrir ce cas, mais il n'est pas utilisé ni nécessaire dans le contexte Minikube/local, car Minikube gère déjà l'exposition des services de type LoadBalancer.
Pour une future migration vers un cluster multi-nœuds sur des VM (cf. kubeadm, Kind, k3d), l'installation de MetalLB sera indispensable pour permettre l'accès aux services externes via des adresses IP.

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
#!/bin/bash
set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

function info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
function ok() { echo -e "${GREEN}[OK]${NC} $1"; }

info "Préparation du volume NFS sur Minikube (à faire une seule fois si déjà fait) :"
echo "  minikube ssh"
echo "  sudo mkdir -p /nfs-vol && sudo chmod 777 /nfs-vol"
echo "  exit"
read -p "Appuie sur Entrée pour continuer une fois le volume prêt..."

info "Build de l'image web-app dans le contexte Docker de Minikube..."
eval $(minikube docker-env)
docker build -t web-app-local:latest .
ok "Image web-app-local:latest buildée."

echo
info "Déploiement complet de la stack Kubernetes..."
chmod +x deploy_full.sh
./deploy_full.sh
ok "Manifests appliqués."

echo
info "Attente que tous les pods soient Running..."
kubectl wait --for=condition=Ready pods --all --timeout=300s
ok "Tous les pods sont prêts."

echo
info "Lancement de la vérification automatisée..."
chmod +x verif_deploiement.sh
./verif_deploiement.sh
ok "Vérification terminée."

echo -e "\n${GREEN}Tout est déployé et vérifié !${NC}" 
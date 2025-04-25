#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
function ok() { echo -e "${GREEN}[OK]${NC} $1"; }
function warn() { echo -e "${RED}[WARN]${NC} $1"; }

# 1. StorageClass local-path (Minikube)
if ! kubectl get storageclass | grep -q 'local-path'; then
  info "Enabling local-path-provisioner (Minikube)..."
  minikube addons enable storage-provisioner-rancher || warn "Addon local-path-provisioner déjà activé ou non supporté."
else
  ok "StorageClass local-path déjà présente."
fi

# 2. NFS CSI Driver + StorageClass
if ! kubectl get storageclass | grep -q 'nfs-csi'; then
  info "Installing NFS CSI driver..."
  curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.5.0/deploy/install-driver.sh | bash -s v4.5.0 --
  info "Deploying in-cluster NFS server (for dev/test)..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/example/nfs-provisioner/nfs-server.yaml
  info "Creating StorageClass nfs-csi..."
  cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs-server.default.svc.cluster.local
  share: /
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
else
  ok "StorageClass nfs-csi déjà présente."
fi

# 3. Ingress Controller
if ! helm status ingress-nginx -n ingress-nginx &>/dev/null; then
  info "Installing ingress-nginx..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
  helm repo update
  helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
else
  ok "Helm release ingress-nginx déjà installé."
fi

# 4. Cert-Manager
if ! helm status cert-manager -n cert-manager &>/dev/null; then
  info "Installing cert-manager..."
  helm repo add jetstack https://charts.jetstack.io || true
  helm repo update
  helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.14.5 --set installCRDs=true
else
  ok "Helm release cert-manager déjà installé."
fi

# 5. Monitoring (Prometheus + Grafana)
if ! helm status prom-stack -n monitoring &>/dev/null; then
  info "Installing kube-prometheus-stack..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
  helm repo update
  helm install prom-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace -f k8s-manifests/monitoring/kube-prometheus-stack-values.yaml
else
  ok "Helm release prom-stack déjà installé."
fi

# 6. MariaDB Galera (HA)
if ! helm status mariadb-galera -n database &>/dev/null; then
  info "Installing MariaDB Galera (HA)..."
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  helm install mariadb-galera bitnami/mariadb-galera --namespace database --create-namespace -f k8s-manifests/apps/mariadb-galera-values.yaml
else
  ok "Helm release mariadb-galera déjà installé."
fi

# 7. ClusterIssuer (TLS)
if kubectl get clusterissuer selfsigned-clusterissuer &>/dev/null; then
  ok "ClusterIssuer déjà présent."
else
  info "Applying ClusterIssuer..."
  kubectl apply -f k8s-manifests/security/selfsigned-clusterissuer.yaml
fi

# 8. RBAC
if kubectl get roles,rolebindings,clusterroles,clusterrolebindings -A | grep -q .; then
  ok "RBAC déjà appliqué."
else
  info "Applying RBAC..."
  kubectl apply -f k8s-manifests/security/rbac.yaml
fi

# 9. Secrets & ConfigMaps
info "Applying Secrets & ConfigMaps..."
kubectl apply -f k8s-manifests/apps/database-secret.yaml
kubectl apply -f k8s-manifests/apps/database-configmap.yaml
kubectl apply -f k8s-manifests/apps/webapp-configmap.yaml

# 10. PersistentVolumeClaims
info "Applying PersistentVolumeClaims..."
kubectl apply -f k8s-manifests/apps/database-pvc.yaml

# 11. Services
info "Applying Services..."
kubectl apply -f k8s-manifests/apps/database-service.yaml
kubectl apply -f k8s-manifests/apps/web-app-service.yaml
kubectl apply -f k8s-manifests/apps/sample-app-service.yaml

# 12. Deployments
info "Applying Deployments..."
kubectl apply -f k8s-manifests/apps/web-app-deployment.yaml
kubectl apply -f k8s-manifests/apps/sample-app-deployment.yaml

# 13. HorizontalPodAutoscalers
info "Applying HPAs..."
kubectl apply -f k8s-manifests/apps/web-app-hpa.yaml
kubectl apply -f k8s-manifests/apps/sample-app-hpa.yaml

# 14. Ingresses
info "Applying Ingresses..."
kubectl apply -f k8s-manifests/apps/web-app-ingress.yaml
kubectl apply -f k8s-manifests/monitoring/grafana-ingress.yaml

# 15. Wait for deployments to be ready
info "Waiting for deployments to be ready..."
kubectl wait --for=condition=available deployment/web-app-deployment --timeout=300s -n default || warn "web-app-deployment not ready."
kubectl wait --for=condition=available deployment/sample-app-deployment --timeout=300s -n default || warn "sample-app-deployment not ready."

info "All resources applied. Vérifie l'accès aux applications et lance ./verif_deploiement.sh pour valider." 
#!/bin/bash

# Script de vérification automatisée du déploiement Kubernetes
# Affiche PASS/FAIL pour chaque étape clé
# Arrêt en cas d'échec critique, résumé final

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=()

function pass() {
  echo -e "${GREEN}PASS${NC} - $1"
  PASS_COUNT=$((PASS_COUNT+1))
}
function fail() {
  echo -e "${RED}FAIL${NC} - $1"
  FAIL_COUNT=$((FAIL_COUNT+1))
  FAIL_LIST+=("$1")
}
function warn() {
  echo -e "${YELLOW}WARN${NC} - $1"
}

# 1. Vérification StorageClass
EXPECTED_SC=("local-path" "nfs-csi")
SC_OK=true
for sc in "${EXPECTED_SC[@]}"; do
  if kubectl get storageclass | grep -q "$sc"; then
    pass "StorageClass $sc présent"
  else
    fail "StorageClass $sc absent"
    SC_OK=false
  fi
done

# 2. Vérification pods/services/ingress/HPA
RESOURCES=("pod" "svc" "ingress" "hpa")
for res in "${RESOURCES[@]}"; do
  if kubectl get $res -A | grep -qv "No resources found"; then
    pass "$res présents"
  else
    fail "$res absents"
  fi
done

# 3. Vérification MariaDB Galera (HA)
if kubectl get pods -n database 2>/dev/null | grep -q mariadb-galera; then
  COUNT=$(kubectl get pods -n database -l app.kubernetes.io/name=mariadb-galera --no-headers 2>/dev/null | wc -l)
  if [ "$COUNT" -ge 3 ]; then
    pass "MariaDB Galera (HA) : $COUNT pods présents"
  else
    fail "MariaDB Galera : moins de 3 pods ($COUNT)"
  fi
else
  fail "MariaDB Galera non déployé (namespace database)"
fi

# 4. Vérification accès webapp
if curl -ks https://webapp.localdev.me | grep -qi "html"; then
  pass "Accès HTTPS à webapp.localdev.me OK"
else
  fail "Accès HTTPS à webapp.localdev.me KO"
fi

# 5. Vérification accès grafana
HTTP_CODE=$(curl -ks -o /dev/null -w "%{http_code}" https://grafana.localdev.me)
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
  pass "Accès HTTPS à grafana.localdev.me OK (code $HTTP_CODE)"
else
  # fallback : test sur le HTML générique ou le lien login
  if curl -ks https://grafana.localdev.me | grep -q '<a href="/login">Found</a>'; then
    pass "Accès HTTPS à grafana.localdev.me OK (login redirect)"
  else
    fail "Accès HTTPS à grafana.localdev.me KO (code $HTTP_CODE)"
  fi
fi

# 6. Vérification TLS (auto-signé accepté)
if echo | openssl s_client -connect webapp.localdev.me:443 -servername webapp.localdev.me 2>/dev/null | grep -q 'BEGIN CERTIFICATE'; then
  pass "Certificat TLS webapp.localdev.me présent"
else
  fail "Certificat TLS webapp.localdev.me absent"
fi

# 7. Vérification Grafana/Prometheus (métriques)
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$GRAFANA_POD" ]; then
  if kubectl logs -n monitoring "$GRAFANA_POD" | grep -qi "HTTP Server Listen"; then
    pass "Grafana pod running"
  else
    fail "Grafana pod KO"
  fi
else
  fail "Grafana pod absent"
fi

# 8. Vérification autoscaling (HPA)
HPA_NAME=$(kubectl get hpa -A | grep web-app | awk '{print $2}' | head -n1)
if [ -n "$HPA_NAME" ]; then
  pass "HPA web-app présent"
  # Simuler une charge CPU sur un pod web-app (si stress-ng installé dans l'image)
  WEBAPP_POD=$(kubectl get pods -n default -l app=web-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$WEBAPP_POD" ]; then
    if kubectl exec -n default "$WEBAPP_POD" -- sh -c "which stress-ng" >/dev/null 2>&1; then
      kubectl exec -n default "$WEBAPP_POD" -- sh -c "stress-ng --cpu 1 --timeout 10 &" 2>/dev/null || true
      sleep 15
      REPLICAS=$(kubectl get hpa -A | grep web-app | awk '{print $5}' | grep -Eo '^[0-9]+')
      if [ -n "$REPLICAS" ] && [ "$REPLICAS" -gt 1 ]; then
        pass "Autoscaling HPA web-app fonctionne ($REPLICAS pods)"
      else
        fail "Autoscaling HPA web-app ne scale pas ($REPLICAS pods)"
      fi
    else
      warn "stress-ng non présent dans l'image web-app, test autoscaling non applicable"
    fi
  else
    fail "Pod web-app non trouvé pour test autoscaling"
  fi
else
  fail "HPA web-app absent"
fi

# 9. Tolérance aux pannes (suppression pod)
if [ -n "$WEBAPP_POD" ]; then
  kubectl delete pod -n default "$WEBAPP_POD" --wait=true
  sleep 5
  NEW_POD=$(kubectl get pods -n default -l app=web-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$NEW_POD" ] && [ "$NEW_POD" != "$WEBAPP_POD" ]; then
    pass "Pod web-app recréé après suppression"
  else
    fail "Pod web-app non recréé après suppression"
  fi
else
  fail "Pas de pod web-app à supprimer pour test tolérance"
fi

# 10. Vérification stockage (PVC)
PVC_OK=true
for pvc in $(kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.name} {.spec.storageClassName}{"\n"}{end}'); do
  name=$(echo $pvc | awk '{print $1}')
  sc=$(echo $pvc | awk '{print $2}')
  if [[ "local-path nfs-csi" =~ "$sc" ]]; then
    pass "PVC $name lié à StorageClass $sc"
  else
    fail "PVC $name lié à StorageClass inattendue ($sc)"
    PVC_OK=false
  fi
done

# 11. Vérification RBAC (si manifest présent)
if [ -f k8s-manifests/security/rbac.yaml ]; then
  if kubectl get roles,rolebindings,clusterroles,clusterrolebindings -A | grep -q .; then
    pass "RBAC appliqué"
  else
    fail "RBAC non appliqué"
  fi
else
  echo -e "${YELLOW}Avertissement : pas de manifest RBAC trouvé${NC}"
fi

# Résumé final

echo -e "\n====================="
echo -e " Résumé des tests "
echo -e "====================="
echo -e "${GREEN}$PASS_COUNT PASS${NC} / ${RED}$FAIL_COUNT FAIL${NC}"
if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "\n${GREEN}TOUT EST OK !${NC}"
  exit 0
else
  echo -e "\n${RED}Des erreurs ont été détectées :${NC}"
  for f in "${FAIL_LIST[@]}"; do
    echo -e "- $f"
  done
  exit 1
fi 
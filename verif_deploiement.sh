#!/bin/bash

# Script de vérification automatisée du déploiement Kubernetes
# Chaque test est indépendant, logs explicites, summary final

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=()
WARN_COUNT=0
WARN_LIST=()

# Tableau pour stocker les résultats détaillés
TEST_RESULTS=()

function info() {
  echo -e "${YELLOW}INFO${NC} - $1"
}
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
  WARN_COUNT=$((WARN_COUNT+1))
  WARN_LIST+=("$1")
}

function record_result() {
  # $1 = nom du test, $2 = statut (PASS/FAIL/WARN)
  TEST_RESULTS+=("$1 : $2")
}

# === TESTS ===

function test_storageclass() {
  info "Vérification StorageClass"
  local test_name="StorageClass"
  for sc in local-path nfs-csi; do
    if kubectl get storageclass | grep -q "$sc"; then
      pass "StorageClass $sc présent"
      record_result "$test_name $sc" "PASS"
    else
      fail "StorageClass $sc absent"
      record_result "$test_name $sc" "FAIL"
    fi
  done
}

function test_metallb() {
  info "Vérification MetalLB"
  local test_name="MetalLB"
  if kubectl get pods -n metallb-system 2>/dev/null | grep -q speaker; then
    pass "MetalLB déployé (namespace metallb-system)"
    record_result "$test_name" "PASS"
  else
    warn "MetalLB non détecté (namespace metallb-system)"
    record_result "$test_name" "WARN"
  fi
}

function test_certmanager() {
  info "Vérification cert-manager"
  local test_name="cert-manager"
  if kubectl get pods -n cert-manager 2>/dev/null | grep -q cert-manager; then
    pass "cert-manager déployé (namespace cert-manager)"
    record_result "$test_name" "PASS"
  else
    fail "cert-manager non déployé (namespace cert-manager)"
    record_result "$test_name" "FAIL"
  fi
  if kubectl get certificate -A 2>/dev/null | grep -q webapp; then
    pass "Certificat généré par cert-manager pour webapp"
    record_result "cert-manager-certificate" "PASS"
  else
    fail "Aucun certificat généré par cert-manager pour webapp"
    record_result "cert-manager-certificate" "FAIL"
  fi
}

function test_prometheus() {
  info "Vérification Prometheus"
  local test_name="Prometheus"
  if kubectl get pods -n monitoring 2>/dev/null | grep -q prometheus; then
    pass "Prometheus déployé (namespace monitoring)"
    record_result "$test_name" "PASS"
  else
    fail "Prometheus non déployé (namespace monitoring)"
    record_result "$test_name" "FAIL"
  fi
}

function test_core_resources() {
  info "Vérification pods/services/ingress/HPA"
  for res in pod svc ingress hpa; do
    local test_name="CoreResource-$res"
    if kubectl get $res -A | grep -qv "No resources found"; then
      pass "$res présents"
      record_result "$test_name" "PASS"
    else
      fail "$res absents"
      record_result "$test_name" "FAIL"
    fi
  done
}

function test_mariadb_galera() {
  info "Vérification MariaDB Galera (HA)"
  local test_name="MariaDB-Galera"
  if kubectl get pods -n database 2>/dev/null | grep -q mariadb-galera; then
    COUNT=$(kubectl get pods -n database -l app.kubernetes.io/name=mariadb-galera --no-headers 2>/dev/null | wc -l)
    if [ "$COUNT" -ge 3 ]; then
      pass "MariaDB Galera (HA) : $COUNT pods présents"
      record_result "$test_name" "PASS"
    else
      fail "MariaDB Galera : moins de 3 pods ($COUNT)"
      record_result "$test_name" "FAIL"
    fi
  else
    fail "MariaDB Galera non déployé (namespace database)"
    record_result "$test_name" "FAIL"
  fi
}

function test_webapp_access() {
  info "Vérification accès webapp"
  local test_name="Webapp-Access"
  if curl -ks https://webapp.localdev.me | grep -qi "html"; then
    pass "Accès HTTPS à webapp.localdev.me OK"
    record_result "$test_name" "PASS"
  else
    fail "Accès HTTPS à webapp.localdev.me KO"
    record_result "$test_name" "FAIL"
  fi
}

function test_grafana_access() {
  info "Vérification accès grafana"
  local test_name="Grafana-Access"
  HTTP_CODE=$(curl -ks -o /dev/null -w "%{http_code}" https://grafana.localdev.me)
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    pass "Accès HTTPS à grafana.localdev.me OK (code $HTTP_CODE)"
    record_result "$test_name" "PASS"
  else
    if curl -ks https://grafana.localdev.me | grep -q '<a href="/login">Found</a>'; then
      pass "Accès HTTPS à grafana.localdev.me OK (login redirect)"
      record_result "$test_name" "PASS"
    else
      fail "Accès HTTPS à grafana.localdev.me KO (code $HTTP_CODE)"
      record_result "$test_name" "FAIL"
    fi
  fi
}

function test_tls() {
  info "Vérification TLS (auto-signé accepté)"
  local test_name="TLS"
  if echo | openssl s_client -connect webapp.localdev.me:443 -servername webapp.localdev.me 2>/dev/null | grep -q 'BEGIN CERTIFICATE'; then
    pass "Certificat TLS webapp.localdev.me présent"
    record_result "$test_name" "PASS"
  else
    fail "Certificat TLS webapp.localdev.me absent"
    record_result "$test_name" "FAIL"
  fi
}

function test_grafana_pod() {
  info "Vérification Grafana/Prometheus (métriques)"
  local test_name="Grafana-Pod"
  GRAFANA_POD=$(kubectl get pods -n monitoring | grep grafana | awk '{print $1}' | head -n1)
  if [ -n "$GRAFANA_POD" ]; then
    GRAFANA_STATUS=$(kubectl get pod -n monitoring "$GRAFANA_POD" -o jsonpath='{.status.phase}')
    if [ "$GRAFANA_STATUS" = "Running" ]; then
      if kubectl logs -n monitoring "$GRAFANA_POD" | grep -qi "HTTP Server Listen"; then
        pass "Grafana pod running"
        record_result "$test_name" "PASS"
      else
        warn "Grafana pod running mais log HTTP Server Listen non trouvé"
        record_result "$test_name" "WARN"
      fi
    else
      fail "Grafana pod non running (status: $GRAFANA_STATUS)"
      record_result "$test_name" "FAIL"
    fi
  else
    fail "Grafana pod absent"
    record_result "$test_name" "FAIL"
  fi
  GRAFANA_DEPLOY=$(kubectl get deployment -n monitoring | grep grafana | awk '{print $1}' | head -n1)
  if [ -n "$GRAFANA_DEPLOY" ]; then
    pass "Deployment Grafana détecté ($GRAFANA_DEPLOY)"
    record_result "Grafana-Deployment" "PASS"
  else
    warn "Deployment Grafana non détecté dans le namespace monitoring"
    record_result "Grafana-Deployment" "WARN"
  fi
}

function test_hpa() {
  info "Vérification autoscaling (HPA)"
  local test_name="HPA"
  HPA_NAME=$(kubectl get hpa -A | grep web-app | awk '{print $2}' | head -n1)
  if [ -n "$HPA_NAME" ]; then
    pass "HPA web-app présent"
    record_result "$test_name" "PASS"
    WEBAPP_POD=$(kubectl get pods -n default -l app=web-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$WEBAPP_POD" ]; then
      if kubectl exec -n default "$WEBAPP_POD" -- sh -c "which stress-ng" >/dev/null 2>&1; then
        kubectl exec -n default "$WEBAPP_POD" -- sh -c "stress-ng --cpu 1 --timeout 60 &" 2>/dev/null || true
        info "Attente du scaling HPA (jusqu'à 90s)..."
        SCALED=0
        for i in {1..18}; do
          REPLICAS=$(kubectl get hpa -A | grep web-app | awk '{print $5}' | grep -Eo '^[0-9]+')
          if [ -n "$REPLICAS" ] && [ "$REPLICAS" -gt 1 ]; then
            pass "Autoscaling HPA web-app fonctionne ($REPLICAS pods)"
            record_result "HPA-Scaling" "PASS"
            SCALED=1
            break
          fi
          sleep 5
        done
        if [ "$SCALED" -eq 0 ]; then
          fail "Autoscaling HPA web-app ne scale pas (1 pod après 90s de stress)"
          record_result "HPA-Scaling" "FAIL"
        fi
      else
        warn "stress-ng non présent dans l'image web-app, test autoscaling non applicable"
        record_result "HPA-Scaling" "WARN"
      fi
    else
      fail "Pod web-app non trouvé pour test autoscaling"
      record_result "HPA-Scaling" "FAIL"
    fi
  else
    fail "HPA web-app absent"
    record_result "$test_name" "FAIL"
  fi
}

function test_pod_recreation() {
  info "Test tolérance aux pannes (suppression/recréation pod web-app)"
  local test_name="Pod-Recreation"
  NAMESPACE=default
  LABEL="app=web-app"
  OLD_POD=$(kubectl get pods -n $NAMESPACE -l $LABEL -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$OLD_POD" ]; then
    fail "Aucun pod web-app trouvé, test annulé."
    record_result "$test_name" "FAIL"
    return
  fi
  info "Pod à supprimer : $OLD_POD"
  kubectl delete pod -n $NAMESPACE "$OLD_POD" --wait=true || true
  info "Attente de la disparition de l'ancien pod ..."
  for i in {1..10}; do
    kubectl get pod -n $NAMESPACE "$OLD_POD" 2>&1 | grep -q 'NotFound' && break
    sleep 1
  done
  info "Recherche d'un nouveau pod web-app ..."
  NEW_POD=""
  for i in {1..20}; do
    NEW_POD=$(kubectl get pods -n $NAMESPACE -l $LABEL -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$NEW_POD" ] && [ "$NEW_POD" != "$OLD_POD" ]; then
      STATUS=$(kubectl get pod -n $NAMESPACE "$NEW_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
      info "Nouveau pod détecté : $NEW_POD (status: $STATUS)"
      if [ "$STATUS" = "Running" ]; then
        pass "Pod web-app recréé et en Running ($NEW_POD)"
        record_result "$test_name" "PASS"
        return
      else
        info "Le nouveau pod n'est pas encore Running (status: $STATUS)"
      fi
    fi
    sleep 1
  done
  fail "Le pod web-app n'a pas été recréé correctement après suppression."
  record_result "$test_name" "FAIL"
}

# ... (toutes les autres fonctions de test, même logique, à adapter si besoin)

function test_pvc() {
  info "Vérification stockage (PVC)"
  local test_name="PVC"
  for pvc in $(kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.name} {.spec.storageClassName}{"\n"}{end}'); do
    name=$(echo $pvc | awk '{print $1}')
    sc=$(echo $pvc | awk '{print $2}')
    if [[ "local-path nfs-csi" =~ "$sc" ]]; then
      pass "PVC $name lié à StorageClass $sc"
      record_result "$test_name $name" "PASS"
    else
      fail "PVC $name lié à StorageClass inattendue ($sc)"
      record_result "$test_name $name" "FAIL"
    fi
  done
}

# ... (idem pour tous les autres tests avancés)

# === EXECUTION SEQUENTIELLE DE TOUS LES TESTS ===

# Activation automatique de metrics-server sur Minikube si nécessaire
if minikube status >/dev/null 2>&1; then
  info "Vérification/activation de metrics-server sur Minikube..."
  if ! kubectl get deployment -n kube-system metrics-server >/dev/null 2>&1; then
    minikube addons enable metrics-server
    info "Attente du démarrage de metrics-server..."
    for i in {1..20}; do
      READY=$(kubectl get deployment -n kube-system metrics-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
      if [ "$READY" = "1" ]; then
        pass "metrics-server prêt"
        record_result "metrics-server" "PASS"
        break
      fi
      sleep 3
    done
  else
    pass "metrics-server déjà actif"
    record_result "metrics-server" "PASS"
  fi
else
  warn "Minikube non détecté, metrics-server non géré automatiquement. Installe-le manuellement si besoin."
  record_result "metrics-server" "WARN"
fi

test_storageclass
test_metallb
test_certmanager
test_prometheus
test_core_resources
test_mariadb_galera
test_webapp_access
test_grafana_access
test_tls
test_grafana_pod
test_hpa
test_pod_recreation
test_pvc
# ... (ajoute ici tous les autres tests avancés, dans l'ordre souhaité)

# === SUMMARY FINAL ===

echo -e "\n====================="
echo -e " Résumé des tests "
echo -e "====================="
echo -e "${GREEN}$PASS_COUNT PASS${NC} / ${RED}$FAIL_COUNT FAIL${NC} / ${YELLOW}$WARN_COUNT WARN${NC}"

# Affichage du tableau récapitulatif détaillé
echo -e "\nDétail des tests :"
for result in "${TEST_RESULTS[@]}"; do
  status=$(echo "$result" | awk '{print $NF}')
  name=$(echo "$result" | sed 's/ : [A-Z]*$//')
  case $status in
    PASS)
      echo -e "${GREEN}$name : $status${NC}"
      ;;
    FAIL)
      echo -e "${RED}$name : $status${NC}"
      ;;
    WARN)
      echo -e "${YELLOW}$name : $status${NC}"
      ;;
    *)
      echo "$name : $status"
      ;;
  esac
done

if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "\n${GREEN}TOUT EST OK !${NC}"
else
  echo -e "\n${RED}Des erreurs ont été détectées :${NC}"
  for f in "${FAIL_LIST[@]}"; do
    echo -e "- $f"
  done
fi
if [ $WARN_COUNT -gt 0 ]; then
  echo -e "\n${YELLOW}Avertissements :${NC}"
  for w in "${WARN_LIST[@]}"; do
    echo -e "- $w"
  done
fi 
#!/bin/bash
# =============================================================================
# Esquire Kubernetes Deployment Script
# Run on the target server where K8s is installed
#
# Usage:
#   ./deploy-k8s.sh                         # auto-detect host IP
#   ./deploy-k8s.sh 10.0.0.50               # specify host IP
#   ./deploy-k8s.sh 10.0.0.50 10.0.0.100    # host IP + separate DB IP
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}[K8S]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# --- Resolve host IPs ---
DEPLOY_HOST="${1:-$(hostname -I | awk '{print $1}')}"
DB_HOST="${2:-$DEPLOY_HOST}"

log "Deploy host: $DEPLOY_HOST"
log "DB host:     $DB_HOST"

# --- Inject IPs into manifest templates ---
log "Injecting host IPs into manifests..."
sed -i "s|__DEPLOY_HOST__|${DEPLOY_HOST}|g" "$SCRIPT_DIR/configmap.yaml"
sed -i "s|__DEPLOY_HOST__|${DEPLOY_HOST}|g" "$SCRIPT_DIR/gateway.yaml"
sed -i "s|__DEPLOY_HOST__|${DEPLOY_HOST}|g" "$SCRIPT_DIR/frontend.yaml"
sed -i "s|__DB_HOST__|${DB_HOST}|g"         "$SCRIPT_DIR/postgres-endpoint.yaml"

# --- Apply manifests in order ---
log "Creating namespace..."
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

log "Applying ConfigMap and Secrets..."
kubectl apply -f "$SCRIPT_DIR/configmap.yaml"
kubectl apply -f "$SCRIPT_DIR/secret.yaml"

log "Creating external PostgreSQL endpoint..."
kubectl apply -f "$SCRIPT_DIR/postgres-endpoint.yaml"

log "Creating Keycloak realm ConfigMap..."
kubectl create configmap keycloak-realm \
  --from-file=realm.json="$DEPLOY_DIR/import/esquire.json" \
  --namespace=esquire \
  --dry-run=client -o yaml | kubectl apply -f -

log "Deploying Keycloak..."
kubectl apply -f "$SCRIPT_DIR/keycloak.yaml"
log "Waiting for Keycloak to be ready..."
kubectl rollout status deployment/keycloak -n esquire --timeout=120s

log "Deploying backend services..."
kubectl apply -f "$SCRIPT_DIR/biztree.yaml"
kubectl apply -f "$SCRIPT_DIR/enyman.yaml"
kubectl apply -f "$SCRIPT_DIR/pacman.yaml"
kubectl apply -f "$SCRIPT_DIR/keysmith.yaml"

log "Deploying Gateway..."
kubectl apply -f "$SCRIPT_DIR/gateway.yaml"
log "Waiting for Gateway to be ready..."
kubectl rollout status deployment/gateway -n esquire --timeout=120s

log "Deploying Frontend..."
kubectl apply -f "$SCRIPT_DIR/frontend.yaml"

log "Deploying HTTPS Proxy..."
kubectl apply -f "$SCRIPT_DIR/proxy.yaml"

log "Waiting for all pods..."
kubectl rollout status deployment/biztree -n esquire --timeout=90s
kubectl rollout status deployment/enyman -n esquire --timeout=90s
kubectl rollout status deployment/pacman -n esquire --timeout=90s
kubectl rollout status deployment/keysmith -n esquire --timeout=90s
kubectl rollout status deployment/frontend -n esquire --timeout=120s
kubectl rollout status deployment/proxy -n esquire --timeout=60s

echo ""
log "All deployments ready!"
echo ""
kubectl get pods -n esquire
kubectl get svc -n esquire
echo ""
log "Services available at:"
log "  Frontend (HTTPS):  https://${DEPLOY_HOST}:30443"
log "  Gateway  (HTTPS):  https://${DEPLOY_HOST}:30343"
log "  Keycloak (HTTPS):  https://${DEPLOY_HOST}:30843"
log ""
log "  Frontend (HTTP):   http://${DEPLOY_HOST}:30200"
log "  Gateway  (HTTP):   http://${DEPLOY_HOST}:30000"
log "  Keycloak (HTTP):   http://${DEPLOY_HOST}:30080"

#!/bin/bash
# =============================================================================
# Esquire Kubernetes Deployment Script
# Run on the server (192.168.1.104) where K8s is installed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}[K8S]${NC} $1"; }

# --- Apply manifests in order ---
log "Creating namespace..."
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

log "Applying ConfigMap and Secrets..."
kubectl apply -f "$SCRIPT_DIR/configmap.yaml"
kubectl apply -f "$SCRIPT_DIR/secret.yaml"

log "Creating external PostgreSQL endpoint..."
kubectl apply -f "$SCRIPT_DIR/postgres-endpoint.yaml"

# Create Keycloak realm ConfigMap from JSON file
log "Creating Keycloak realm ConfigMap..."
kubectl create configmap keycloak-realm \
  --from-file=realm.json="$SCRIPT_DIR/../import/esquire.json" \
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

log "Waiting for all pods..."
kubectl rollout status deployment/biztree -n esquire --timeout=90s
kubectl rollout status deployment/enyman -n esquire --timeout=90s
kubectl rollout status deployment/pacman -n esquire --timeout=90s
kubectl rollout status deployment/keysmith -n esquire --timeout=90s
kubectl rollout status deployment/frontend -n esquire --timeout=120s

echo ""
log "All deployments ready!"
echo ""
kubectl get pods -n esquire
kubectl get svc -n esquire
echo ""
log "Services available at:"
log "  Frontend:  http://192.168.1.104:30200"
log "  Gateway:   http://192.168.1.104:30000"
log "  Keycloak:  http://192.168.1.104:30080"

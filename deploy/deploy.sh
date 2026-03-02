#!/bin/bash
# =============================================================================
# Esquire Deployment Script
# Multi-stage: Maven builds inside Docker — no local JDK/Maven needed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"

# Load environment
source "$DEPLOY_DIR/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Fix Windows CRLF line endings in shell scripts ---
fix_crlf() {
    log "Fixing CRLF line endings in shell scripts..."
    find "$DEPLOY_DIR" -name "*.sh" -exec sed -i 's/\r$//' {} +
    find "$DEPLOY_DIR/../esquire.services" -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    find "$DEPLOY_DIR/../esquire.explorer" -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
}

# --- Build Docker images (Maven builds inside Docker) ---
build() {
    fix_crlf
    log "Building Docker images (multi-stage, Maven inside Docker)..."
    cd "$DEPLOY_DIR"
    docker compose build --parallel
    log "Docker images built successfully."
    docker images | grep esquire
}

# --- Start all services ---
up() {
    log "Starting services..."
    cd "$DEPLOY_DIR"
    docker compose up -d
    log "Waiting for services..."
    sleep 5
    docker compose ps
}

# --- Stop all services ---
down() {
    log "Stopping services..."
    cd "$DEPLOY_DIR"
    docker compose down --remove-orphans
    log "All services stopped."
}

# --- Full deploy: build + start ---
deploy() {
    build
    echo ""
    log "Stopping old containers (if any)..."
    cd "$DEPLOY_DIR"
    docker compose down --remove-orphans 2>/dev/null || true
    echo ""
    up
}

# --- Show logs ---
logs() {
    cd "$DEPLOY_DIR"
    docker compose logs -f --tail=100 "${2:-}"
}

# --- Show status ---
status() {
    cd "$DEPLOY_DIR"
    docker compose ps
}

# --- Restart a single service ---
restart_svc() {
    local svc="${2:-}"
    if [ -z "$svc" ]; then
        error "Usage: $0 restart <service-name>"
    fi
    log "Restarting $svc..."
    cd "$DEPLOY_DIR"
    docker compose restart "$svc"
    docker compose ps
}

# ======================== MAIN ========================
usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy      Build images + start all services (full deploy)"
    echo "  build       Build Docker images only"
    echo "  up          Start all services (images must exist)"
    echo "  down        Stop all services"
    echo "  restart     Restart a specific service (e.g. ./deploy.sh restart gateway)"
    echo "  status      Show running containers"
    echo "  logs        Tail logs (e.g. ./deploy.sh logs gateway)"
    echo ""
}

case "${1:-}" in
    deploy)  deploy ;;
    build)   build ;;
    up)      up ;;
    down)    down ;;
    restart) restart_svc "$@" ;;
    status)  status ;;
    logs)    logs "$@" ;;
    *)       usage; exit 1 ;;
esac

echo ""
log "Services (HTTPS via Nginx reverse-proxy):"
log "  Frontend:  https://${DEPLOY_HOST}"
log "  Gateway:   https://${DEPLOY_HOST}:3443"
log "  Keycloak:  https://${DEPLOY_HOST}:8443"

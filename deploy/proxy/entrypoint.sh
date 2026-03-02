#!/bin/sh
set -e

CERT_DIR=/etc/nginx/certs

if [ ! -f "$CERT_DIR/self-signed.crt" ]; then
  echo "==> Generating self-signed TLS certificate ..."
  mkdir -p "$CERT_DIR"
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$CERT_DIR/self-signed.key" \
    -out    "$CERT_DIR/self-signed.crt" \
    -subj   "/CN=${DEPLOY_HOST:-192.168.1.104}/O=Esquire/C=US" \
    -addext "subjectAltName=IP:${DEPLOY_HOST:-192.168.1.104}"
  echo "==> Certificate created."
fi

echo "==> Starting Nginx (HTTPS proxy) ..."
exec nginx -g "daemon off;"

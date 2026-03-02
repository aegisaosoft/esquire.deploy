#!/bin/sh
set -e

CERT_DIR=/etc/nginx/certs
MKCERT_DIR=/etc/nginx/certs-mkcert

mkdir -p "$CERT_DIR"

# Use mkcert trusted cert if available, otherwise generate self-signed
if [ -f "$MKCERT_DIR/esquire.crt" ] && [ -f "$MKCERT_DIR/esquire.key" ]; then
  echo "==> Using mkcert trusted certificate."
  cp "$MKCERT_DIR/esquire.crt" "$CERT_DIR/self-signed.crt"
  cp "$MKCERT_DIR/esquire.key" "$CERT_DIR/self-signed.key"
elif [ ! -f "$CERT_DIR/self-signed.crt" ]; then
  echo "==> Generating self-signed TLS certificate ..."
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$CERT_DIR/self-signed.key" \
    -out    "$CERT_DIR/self-signed.crt" \
    -subj   "/CN=${DEPLOY_HOST:-localhost}/O=Esquire/C=US" \
    -addext "subjectAltName=IP:${DEPLOY_HOST:-127.0.0.1}"
  echo "==> Self-signed certificate created."
fi

echo "==> Starting Nginx (HTTPS proxy) ..."
exec nginx -g "daemon off;"

FROM nginx:alpine
RUN apk add --no-cache openssl dos2unix
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh
# mkcert trusted certificate (optional — fallback to self-signed if missing)
COPY esquire.crt esquire.key /etc/nginx/certs-mkcert/
ENTRYPOINT ["/entrypoint.sh"]

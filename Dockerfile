# Imagen del nodo dns-secundario-1 de GNS3 (tag dns-secundario:1.0).
# La construye instalar.sh gns3: no hace falta tocar nada a mano.
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y bind9 bind9utils dnsutils iproute2 && \
    rm -rf /var/lib/apt/lists/*

COPY named.conf.options /etc/bind/named.conf.options
COPY named.conf.local   /etc/bind/named.conf.local
COPY entrypoint.sh      /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

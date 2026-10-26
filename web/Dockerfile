FROM php:8.2-apache

# Extensiones PHP para PostgreSQL
RUN apt-get update && apt-get install -y libpq-dev \
    && docker-php-ext-install pgsql pdo_pgsql \
    && rm -rf /var/lib/apt/lists/*

# VirtualHosts del proyecto (www, intranet, git y gns3).
# El .htpasswd NO se copia aquí: se monta desde compose.yaml (secretos/intranet.htpasswd).
COPY huesca.conf /etc/apache2/sites-available/huesca.conf
RUN a2dissite 000-default.conf && a2ensite huesca.conf

# Proxy inverso: git.huesca.empresa.lan -> Forgejo, gns3.huesca.empresa.lan -> GNS3 (en el servidor)
RUN a2enmod proxy proxy_http proxy_wstunnel

# Código de los sitios
COPY www/ /var/www/html/www/
COPY intranet/ /var/www/html/intranet/

EXPOSE 80

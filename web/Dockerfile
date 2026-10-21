FROM php:8.2-apache

# Extensiones PHP para PostgreSQL
RUN apt-get update && apt-get install -y libpq-dev \
    && docker-php-ext-install pgsql pdo_pgsql \
    && rm -rf /var/lib/apt/lists/*

# VirtualHosts del proyecto (www e intranet).
# El .htpasswd NO se copia aquí: se monta desde compose.yaml (secretos/intranet.htpasswd).
COPY huesca.conf /etc/apache2/sites-available/huesca.conf
RUN a2dissite 000-default.conf && a2ensite huesca.conf

# Código de los sitios
COPY www/ /var/www/html/www/
COPY intranet/ /var/www/html/intranet/

EXPOSE 80

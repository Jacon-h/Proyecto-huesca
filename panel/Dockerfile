# Panel del BIFI · PHP 8.3 con Apache.
# pdo_pgsql ya va instalado: en el RA6 el panel pasa de los ficheros JSON a PostgreSQL.
FROM php:8.3-apache

RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev \
 && docker-php-ext-install pdo_pgsql \
 && rm -rf /var/lib/apt/lists/*

# Solo public/ se sirve. comun/ y datos/ quedan fuera del alcance del navegador.
ENV APACHE_DOCUMENT_ROOT=/var/www/panel/public
RUN sed -ri 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
 && sed -ri 's!/var/www/!/var/www/panel/!g' /etc/apache2/apache2.conf

COPY public/ /var/www/panel/public/
COPY comun/  /var/www/panel/comun/
# Datos de ejemplo. En Compose, datos/ es un volumen: la primera vez se llena con esto.
COPY --chown=www-data:www-data datos-ejemplo/ /var/www/panel/datos/

# Panel del BIFI · PHP 8.3 con Apache.
# pdo_pgsql: todos los datos del panel están en la base bifi (comun/bd.php). El contenedor no guarda nada.
FROM php:8.3-apache

RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev \
 && docker-php-ext-install pdo_pgsql \
 && rm -rf /var/lib/apt/lists/*

# La imagen oficial viene sin php.ini, y entonces PHP enseña los errores en la página (rutas, consultas,
# a veces el usuario de la base). Con el de producción van al registro (docker logs panel) y no al navegador.
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Solo public/ se sirve. comun/ y pruebas/ quedan fuera del alcance del navegador.
ENV APACHE_DOCUMENT_ROOT=/var/www/panel/public
RUN sed -ri 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
 && sed -ri 's!/var/www/!/var/www/panel/!g' /etc/apache2/apache2.conf

COPY public/  /var/www/panel/public/
COPY comun/   /var/www/panel/comun/
# Scripts de prueba para la línea de órdenes (docker exec panel php ...). Fuera de public/: no se sirven.
COPY pruebas/ /var/www/panel/pruebas/
# datos-ejemplo/ no se copia (y .dockerignore lo deja fuera del todo): esos JSON solo los usa
# instalar.sh para la primera carga de la base.

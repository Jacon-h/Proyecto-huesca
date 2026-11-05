#!/bin/bash
# Se ejecuta UNA vez, al crear el volumen por primera vez (después de 01 y 02).
# Crea el usuario con el que entra la web: puede leer, insertar y editar,
# pero NO borrar. Si la web se ve comprometida, no puede vaciar la tabla.
# El administrador (postgres) es el dueño de la tabla y no lo usa la web.
set -e

psql -v ON_ERROR_STOP=1 -v usuario="$DB_USER" -v clave="$DB_PASSWORD" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE ROLE :"usuario" LOGIN PASSWORD :'clave';
GRANT USAGE ON SCHEMA public TO :"usuario";
GRANT SELECT, INSERT, UPDATE ON inventario TO :"usuario";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"usuario";
SQL

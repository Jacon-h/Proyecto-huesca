#!/bin/bash
# db/04_bifi.sh · Base bifi y sus usuarios de red (ASGBD RA2)
#
# Cuándo se ejecuta:
#   1. PostgreSQL lo lanza solo al crear el volumen por primera vez (después de 01, 02 y 03).
#   2. instalar.sh lo repite en cada instalación:
#        docker exec -u postgres mi-postgres bash /docker-entrypoint-initdb.d/04_bifi.sh
# Por eso está escrito para poder repetirse sin error (idempotente): crea lo que falta y vuelve a
# fijar contraseñas, límites y permisos (si cambias una contraseña en .env, se aplica al repetir).
#
# Las contraseñas llegan por variables de entorno desde .env (compose.yaml). Aquí no hay ninguna.
set -e

: "${BIFI_PANEL_PASSWORD:?falta BIFI_PANEL_PASSWORD (en .env)}"
: "${BIFI_RESP_PASSWORD:?falta BIFI_RESP_PASSWORD (en .env)}"
: "${DB_USER:?falta DB_USER (en .env)}"

if [ "$POSTGRES_DB" = bifi ]; then
    echo "04_bifi.sh: DB_NAME no puede ser 'bifi'. bifi la crea este script con colación española." >&2
    exit 1
fi

# ------------------------------------------------------------------ 1. Base bifi y usuarios
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
     -v clave_panel="$BIFI_PANEL_PASSWORD" \
     -v clave_resp="$BIFI_RESP_PASSWORD" <<'SQL'

-- P7 · bifi en UTF-8 con colación española (es_ES.UTF-8 lo genera db/Dockerfile).
-- Se parte de template0 porque template1 ya tiene otra colación y no se podría cambiar.
-- CREATE DATABASE no admite "IF NOT EXISTS": el SELECT solo produce la orden si bifi no existe,
-- y \gexec la ejecuta.
SELECT 'CREATE DATABASE bifi
            TEMPLATE   template0
            ENCODING   ''UTF8''
            LC_COLLATE ''es_ES.UTF-8''
            LC_CTYPE   ''es_ES.UTF-8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'bifi') \gexec

-- Usuarios: se crean si no existen.
--   panel     → la aplicación del panel, desde Compose (P1)
--   resp_demo → un responsable de proyecto, desde un equipo del aula (P3)
SELECT 'CREATE ROLE panel LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'panel') \gexec

SELECT 'CREATE ROLE resp_demo LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'resp_demo') \gexec

-- Mínimo privilegio: ninguno es superusuario ni puede crear bases o usuarios.
-- P5 · Límite de conexiones de cada usuario (además de max_connections en postgresql.conf).
ALTER ROLE panel     WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 10
                     PASSWORD :'clave_panel';
ALTER ROLE resp_demo WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 2
                     PASSWORD :'clave_resp';

-- P6 · Ninguna consulta de estos usuarios puede durar más de 5 segundos.
-- Va por usuario y no en postgresql.conf para no cortar al administrador (copias, mantenimiento).
ALTER ROLE panel     SET statement_timeout = '5s';
ALTER ROLE resp_demo SET statement_timeout = '5s';

-- A bifi solo entran panel y resp_demo (por defecto PostgreSQL deja conectar a todos: PUBLIC).
REVOKE ALL     ON DATABASE bifi FROM PUBLIC;
GRANT  CONNECT ON DATABASE bifi TO panel, resp_demo;
SQL

# ------------------------------------------------------------------ 2. La base de la web (DB_NAME)
# A la base de la web solo entra su usuario (DB_USER). Antes resp_demo leía inventario: se le quita.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v base="$POSTGRES_DB" -v usuario_web="$DB_USER" <<'SQL'
REVOKE ALL     ON DATABASE :"base" FROM PUBLIC;
GRANT  CONNECT ON DATABASE :"base" TO :"usuario_web";

REVOKE ALL ON DATABASE :"base"              FROM panel, resp_demo;
REVOKE ALL ON ALL TABLES IN SCHEMA public   FROM resp_demo;
REVOKE ALL ON SCHEMA public                 FROM resp_demo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM resp_demo;
SQL

echo "04_bifi.sh: base bifi y usuarios panel y resp_demo listos"

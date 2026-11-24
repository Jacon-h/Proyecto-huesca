#!/bin/bash
# db/04_bifi.sh · Base del panel del BIFI y sus usuarios de red (ASGBD RA2)
#
# Cuándo se ejecuta:
#   1. PostgreSQL lo lanza solo al crear el volumen por primera vez (después de 01, 02 y 03).
#   2. instalar.sh lo repite en cada instalación:
#        docker exec -u postgres mi-postgres bash /docker-entrypoint-initdb.d/04_bifi.sh
# Por eso está escrito para poder repetirse sin error (idempotente): crea lo que falta y vuelve a
# fijar contraseñas, límites y permisos (si cambias una contraseña en .env, se aplica al repetir).
#
# Nombres y contraseñas llegan por variables de entorno desde .env (compose.yaml). Aquí no hay ninguno:
#   BIFI_DB              la base (la práctica pide "bifi")
#   BIFI_PANEL_USER      la aplicación del panel, entra desde Compose (P1)
#   BIFI_RESP_USER       un responsable de proyecto, entra desde un equipo del aula (P3)
set -e

for v in BIFI_DB BIFI_PANEL_USER BIFI_PANEL_PASSWORD BIFI_RESP_USER BIFI_RESP_PASSWORD DB_USER; do
    if [ -z "${!v}" ]; then
        echo "04_bifi.sh: falta $v (en .env)" >&2
        exit 1
    fi
done
if [ "$POSTGRES_DB" = "$BIFI_DB" ]; then
    echo "04_bifi.sh: DB_NAME y BIFI_DB no pueden ser iguales: $BIFI_DB se crea aparte con colación española." >&2
    exit 1
fi

# En el SQL de abajo:  :'variable' = valor entre comillas (texto)   :"variable" = nombre (base o usuario)

# ------------------------------------------------------------------ 1. Base y usuarios
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
     -v base="$BIFI_DB" \
     -v usuario_panel="$BIFI_PANEL_USER" -v clave_panel="$BIFI_PANEL_PASSWORD" \
     -v usuario_resp="$BIFI_RESP_USER"   -v clave_resp="$BIFI_RESP_PASSWORD" <<'SQL'

-- P7 · La base en UTF-8 con colación española (es_ES.UTF-8 lo genera db/Dockerfile).
-- Se parte de template0 porque template1 ya tiene otra colación y no se podría cambiar.
-- CREATE DATABASE no admite "IF NOT EXISTS": el SELECT solo produce la orden si la base no existe,
-- y \gexec la ejecuta. format('%I') pone el nombre como identificador de SQL.
SELECT format('CREATE DATABASE %I
                   TEMPLATE   template0
                   ENCODING   ''UTF8''
                   LC_COLLATE ''es_ES.UTF-8''
                   LC_CTYPE   ''es_ES.UTF-8''', :'base')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'base') \gexec

-- Usuarios: se crean si no existen.
SELECT format('CREATE ROLE %I LOGIN', :'usuario_panel')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'usuario_panel') \gexec

SELECT format('CREATE ROLE %I LOGIN', :'usuario_resp')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'usuario_resp') \gexec

-- Mínimo privilegio: ninguno es superusuario ni puede crear bases o usuarios.
-- P5 · Límite de conexiones de cada usuario (además de max_connections en postgresql.conf).
ALTER ROLE :"usuario_panel" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 10
                            PASSWORD :'clave_panel';
ALTER ROLE :"usuario_resp"  WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 2
                            PASSWORD :'clave_resp';

-- P6 · Ninguna consulta de estos usuarios puede durar más de 5 segundos.
-- Va por usuario y no en postgresql.conf para no cortar al administrador (copias, mantenimiento).
ALTER ROLE :"usuario_panel" SET statement_timeout = '5s';
ALTER ROLE :"usuario_resp"  SET statement_timeout = '5s';

-- A la base solo entran estos dos (por defecto PostgreSQL deja conectar a todos: PUBLIC).
REVOKE ALL     ON DATABASE :"base" FROM PUBLIC;
GRANT  CONNECT ON DATABASE :"base" TO :"usuario_panel", :"usuario_resp";
SQL

# ------------------------------------------------------------------ 2. La base de la web (DB_NAME)
# A la base de la web solo entra su usuario (DB_USER). Ni el panel ni el responsable.
# (En versiones anteriores resp_demo leía inventario: aquí se le quita por si venía de entonces.)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v base_web="$POSTGRES_DB" -v usuario_web="$DB_USER" \
     -v usuario_panel="$BIFI_PANEL_USER" -v usuario_resp="$BIFI_RESP_USER" <<'SQL'
REVOKE ALL     ON DATABASE :"base_web" FROM PUBLIC;
GRANT  CONNECT ON DATABASE :"base_web" TO :"usuario_web";

REVOKE ALL ON DATABASE :"base_web"         FROM :"usuario_panel", :"usuario_resp";
REVOKE ALL ON ALL TABLES IN SCHEMA public  FROM :"usuario_resp";
REVOKE ALL ON SCHEMA public                FROM :"usuario_resp";
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM :"usuario_resp";
SQL

echo "04_bifi.sh: base $BIFI_DB y usuarios $BIFI_PANEL_USER y $BIFI_RESP_USER listos"

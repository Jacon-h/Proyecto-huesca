#!/bin/bash
# db/04_bifi.sh · Base del panel del BIFI, sus tablas y sus usuarios de red (ASGBD RA2)
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

# ------------------------------------------------------------------ 0. bifi creada antes con colación libc
# Las versiones anteriores creaban la base con colación libc (es_ES.UTF-8). Ahora es ICU (es-ES), y la
# colación de una base no se puede cambiar después de crearla: hay que volver a crearla.
# Solo se hace si la base está VACÍA. Si tiene tablas (las del panel, por ejemplo), se avisa y no se toca
# nada: habría que hacer copia, borrarla a mano y repetir este script.
proveedor=$(psql -qtAX -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -v base="$BIFI_DB" <<'SQL'
SELECT datlocprovider FROM pg_database WHERE datname = :'base';
SQL
)
if [ "$proveedor" = c ]; then      # c = libc, i = icu
    objetos=$(psql -qtAX -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$BIFI_DB" <<'SQL'
SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname NOT LIKE 'pg_toast%';
SQL
)
    if [ "$objetos" = 0 ]; then
        echo "04_bifi.sh: $BIFI_DB estaba con colación libc y vacía: se vuelve a crear con ICU (es-ES)"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -v base="$BIFI_DB" <<'SQL'
SELECT format('DROP DATABASE %I WITH (FORCE)', :'base') \gexec
SQL
    else
        echo "04_bifi.sh: AVISO: $BIFI_DB usa colación libc y tiene $objetos objetos: no se recrea (db/README.md, P7)" >&2
    fi
fi

# ------------------------------------------------------------------ 1. Base y usuarios
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
     -v base="$BIFI_DB" \
     -v usuario_panel="$BIFI_PANEL_USER" -v clave_panel="$BIFI_PANEL_PASSWORD" \
     -v usuario_resp="$BIFI_RESP_USER"   -v clave_resp="$BIFI_RESP_PASSWORD" <<'SQL'

-- P7 · La base en UTF-8 con colación ICU española (es-ES).
-- LOCALE_PROVIDER icu: la ordenación la hace la librería ICU (igual en cualquier sistema operativo),
-- no la libc del contenedor. LC_COLLATE/LC_CTYPE siguen siendo obligatorios para lo que no hace ICU
-- (mensajes, clasificación de caracteres); es_ES.UTF-8 lo genera db/Dockerfile.
-- Se parte de template0 porque template1 ya tiene otra colación y no se podría cambiar.
-- CREATE DATABASE no admite "IF NOT EXISTS": el SELECT solo produce la orden si la base no existe,
-- y \gexec la ejecuta. format('%I') pone el nombre como identificador de SQL.
SELECT format('CREATE DATABASE %I
                   TEMPLATE        template0
                   ENCODING        ''UTF8''
                   LOCALE_PROVIDER icu
                   ICU_LOCALE      ''es-ES''
                   LC_COLLATE      ''es_ES.UTF-8''
                   LC_CTYPE        ''es_ES.UTF-8''', :'base')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'base') \gexec

-- P7 · Zona horaria de la propia base (además de timezone en postgresql.conf, que vale para todo el servidor).
ALTER DATABASE :"base" SET timezone = 'Europe/Madrid';

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

# ------------------------------------------------------------------ 3. Tablas del panel y sus permisos
# Las crea el administrador, que queda como dueño. El panel solo trabaja con filas: no puede crear, cambiar
# ni borrar tablas, y en cada una tiene únicamente lo que usa alguna página:
#   usuarios   SELECT                   el login y los nombres. Las cuentas se dan de alta desde aquí, no desde la web
#   proyectos  SELECT, INSERT           listar y dar de alta. No hay edición ni baja de proyectos en el panel
#   miembros   SELECT, INSERT, DELETE   añadir y quitar investigadores de un proyecto
#   usos       SELECT                   el consumo lo registra el CESAR, el panel solo lo enseña
# Si un día alguien se cuela en el panel, no puede cambiar contraseñas, inventarse consumos ni vaciar tablas.
#
# El responsable (resp_demo) entra con psql desde el aula para las pruebas de conexión (P3-P6) y no necesita
# leer nada: se le quita incluso el acceso al esquema. Si más adelante tiene que consultar algo, mejor una
# vista con lo suyo que un GRANT sobre las tablas.
#
# CREATE TABLE IF NOT EXISTS porque este script se repite en cada instalación. Si se cambia la definición
# de una tabla que ya existe, aquí no se aplica: hay que hacer el ALTER TABLE a mano.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$BIFI_DB" \
     -v usuario_panel="$BIFI_PANEL_USER" -v usuario_resp="$BIFI_RESP_USER" <<'SQL'
BEGIN;

CREATE TABLE IF NOT EXISTS usuarios (
    usuario varchar(32)  PRIMARY KEY CHECK (usuario ~ '^[a-z][a-z0-9_]*$'),
    nombre  varchar(100) NOT NULL,
    perfil  varchar(20)  NOT NULL CHECK (perfil IN ('investigador', 'responsable', 'cesar')),
    hash    varchar(255) NOT NULL          -- password_hash() de PHP; nunca la contraseña
);

CREATE TABLE IF NOT EXISTS proyectos (
    codigo      varchar(8)   PRIMARY KEY CHECK (codigo ~ '^[A-Z]{3}-[0-9]{4}$'),
    titulo      varchar(120) NOT NULL CHECK (char_length(titulo) >= 5),
    responsable varchar(32)  NOT NULL REFERENCES usuarios,
    tarifa      varchar(20)  NOT NULL CHECK (tarifa IN ('academica', 'empresa'))
);

CREATE TABLE IF NOT EXISTS miembros (
    proyecto varchar(8)  REFERENCES proyectos,
    usuario  varchar(32) REFERENCES usuarios,
    PRIMARY KEY (proyecto, usuario)
);

CREATE TABLE IF NOT EXISTS usos (
    id       integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proyecto varchar(8)   NOT NULL REFERENCES proyectos,
    usuario  varchar(32)  NOT NULL REFERENCES usuarios,
    maquina  varchar(50)  NOT NULL,
    nucleos  integer      NOT NULL CHECK (nucleos > 0),
    horas    numeric(8,2) NOT NULL CHECK (horas > 0),
    fecha    date         NOT NULL
);
CREATE INDEX IF NOT EXISTS usos_proyecto ON usos (proyecto);

-- Desde PostgreSQL 15 PUBLIC ya no puede crear en el esquema public, pero sí usarlo. Se le quita todo y
-- se le da USAGE solo al panel: así resp_demo no llega ni a los nombres de las tablas.
REVOKE ALL   ON SCHEMA public FROM PUBLIC;
GRANT  USAGE ON SCHEMA public TO :"usuario_panel";

-- Primero se quita todo y luego se da lo justo: si en una versión anterior hubo más permisos, no se quedan.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM :"usuario_panel", :"usuario_resp";
GRANT SELECT                 ON usuarios, usos TO :"usuario_panel";
GRANT SELECT, INSERT         ON proyectos      TO :"usuario_panel";
GRANT SELECT, INSERT, DELETE ON miembros       TO :"usuario_panel";

COMMIT;
SQL

echo "04_bifi.sh: base $BIFI_DB, tablas del panel y usuarios $BIFI_PANEL_USER y $BIFI_RESP_USER listos"

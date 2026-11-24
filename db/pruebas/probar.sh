#!/bin/bash
# db/pruebas/probar.sh · Pruebas de ASGBD RA2 lanzadas desde el servidor
#
#   sudo ./db/pruebas/probar.sh            P1, P2, P4, P5, P6, P7, P8 y qué IP ve el gestor (no para nada)
#   sudo ./db/pruebas/probar.sh parada     además, la prueba de stop_grace_period (para y arranca la base)
#
# P3 (el responsable desde OTRO equipo del aula) se hace a mano: db/README.md, apartado "Pruebas".
# instalar.sh verificar lo lanza sin "parada". Devuelve 0 si todo va bien y 1 si algo falla.
# Las contraseñas se leen de .env y viajan por variables de entorno: no aparecen en pantalla.

cd "$(dirname "$0")/../.." || exit 1
[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con sudo:  sudo ./db/pruebas/probar.sh"; exit 1; }
[ -f .env ] || { echo "ERROR: no hay .env"; exit 1; }
set -a; source .env; set +a
source sede.env
command -v psql >/dev/null || { echo "ERROR: falta psql en el servidor (sudo ./instalar.sh web lo instala)"; exit 1; }

IP_SERVIDOR="${IP_AULA%/*}"            # la IP del servidor en el aula (sede.env)
USUARIO_SO="${SUDO_USER:-root}"        # quien ha lanzado sudo: es quien tiene ~/.pgpass
FALLOS=0

titulo() { echo; echo "== $*"; }
bien()   { echo "OK    $*"; }
mal()    { echo "FALLO $*"; FALLOS=1; }

# --- Formas de conectarse --------------------------------------------------------------------

# Administrador por socket dentro del contenedor (línea 1 de pg_hba.conf: peer)
admin_sql() {                    # admin_sql <base> <sql>
    docker exec -u postgres mi-postgres psql -d "$1" -tAc "$2" 2>&1
}

# Cliente psql del propio servidor, por red
servidor_sql() {                 # servidor_sql <ip> <usuario> <clave> <sql>
    PGPASSWORD="$3" PGCONNECT_TIMEOUT=5 psql -h "$1" -U "$2" -d bifi -tAc "$4" 2>&1
}

# ¿La respuesta es un rechazo de pg_hba.conf?
rechazado() { grep -q "pg_hba.conf rejects connection"; }

# --- P7 · bifi en UTF-8 con colación española --------------------------------------------------
titulo "P7 · Base bifi"
r=$(admin_sql postgres "SELECT pg_encoding_to_char(encoding) || ' ' || datcollate || ' ' || datctype
                        FROM pg_database WHERE datname = 'bifi'")
if [ "$r" = "UTF8 es_ES.UTF-8 es_ES.UTF-8" ]; then bien "bifi: $r"; else mal "bifi: esperaba 'UTF8 es_ES.UTF-8 es_ES.UTF-8' y salió '$r'"; fi

r=$(admin_sql bifi "SELECT string_agg(palabra, ' ' ORDER BY palabra)
                    FROM (VALUES ('oso'), ('ñu'), ('nube'), ('Ávila'), ('zorro')) AS t(palabra)")
if [ "$r" = "Ávila nube ñu oso zorro" ]; then bien "orden español: $r"; else mal "orden: salió '$r' (con colación C sería 'nube oso zorro Ávila ñu')"; fi

# --- P1 · El panel entra desde Compose ---------------------------------------------------------
titulo "P1 · El panel entra en bifi desde Compose"
r=$(docker exec panel php /var/www/panel/pruebas/estado-bifi.php 2>&1)
echo "$r" | sed 's/^/      /'
if echo "$r" | grep -q "^usuario: panel$"; then bien "el panel entra como 'panel'"; else mal "el panel no entra en bifi"; fi
IP_DESDE_COMPOSE=$(echo "$r" | awk -F': ' '$1 == "IP que ve el gestor" {print $2}')

# --- Aislamiento · La base del panel es SOLO del panel ----------------------------------------
# bifi (BIFI_DB) es la base del panel; DB_NAME es la de la web. Ninguno de los dos usuarios
# de aplicación puede abrir la base del otro (los permisos CONNECT los pone db/04_bifi.sh).
titulo "Aislamiento · cada aplicación con su base"
if [ "$BIFI_DB" != "$DB_NAME" ]; then bien "base del panel ($BIFI_DB) distinta de la de la web ($DB_NAME)"; else mal "BIFI_DB y DB_NAME son la misma base"; fi
r=$(docker exec -e PGPASSWORD="$BIFI_PANEL_PASSWORD" mi-postgres psql -h db -U "$BIFI_PANEL_USER" -d "$DB_NAME" -tAc 'SELECT 1' 2>&1)
if echo "$r" | grep -q "permission denied for database"; then bien "$BIFI_PANEL_USER no puede abrir la base de la web ($DB_NAME)"; else mal "$BIFI_PANEL_USER en $DB_NAME: $r"; fi
r=$(docker exec -e PGPASSWORD="$DB_PASSWORD" mi-postgres psql -h db -U "$DB_USER" -d "$BIFI_DB" -tAc 'SELECT 1' 2>&1)
if echo "$r" | grep -q "permission denied for database"; then bien "$DB_USER (web) no puede abrir la base del panel ($BIFI_DB)"; else mal "$DB_USER en $BIFI_DB: $r"; fi

# --- P2 · El administrador no entra por red ----------------------------------------------------
titulo "P2 · El administrador no entra por red"
r=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" mi-postgres psql -h db -U postgres -d postgres -tAc 'SELECT 1' 2>&1)
if echo "$r" | rechazado; then bien "postgres desde Compose: rechazado por pg_hba.conf"; else mal "postgres desde Compose: $r"; fi
r=$(servidor_sql "$IP_SERVIDOR" postgres "$POSTGRES_PASSWORD" 'SELECT 1')
if echo "$r" | rechazado; then bien "postgres por $IP_SERVIDOR:5432: rechazado por pg_hba.conf"; else mal "postgres por la IP del aula: $r"; fi
r=$(admin_sql postgres 'SELECT current_user')
if [ "$r" = postgres ]; then bien "postgres por socket dentro del contenedor (docker exec -u postgres): entra"; else mal "admin por socket: $r"; fi

# --- Qué IP ve el gestor -------------------------------------------------------------------
titulo "Qué IP ve el gestor (Maestro)"
IP_DESDE_AULA_IP=$(servidor_sql "$IP_SERVIDOR" resp_demo "$BIFI_RESP_PASSWORD" 'SELECT inet_client_addr()')
IP_DESDE_LOCALHOST=$(servidor_sql 127.0.0.1 resp_demo "$BIFI_RESP_PASSWORD" 'SELECT inet_client_addr()')
echo "      desde Compose (contenedor panel)              -> ${IP_DESDE_COMPOSE:-?}"
echo "      desde el servidor a su IP del aula ($IP_SERVIDOR) -> $IP_DESDE_AULA_IP"
echo "      desde el servidor a 127.0.0.1                 -> $IP_DESDE_LOCALHOST"
echo "      desde otro equipo del aula                    -> su propia IP (prueba P3, a mano)"
echo "      redes de Compose que ve el contenedor (samenet):"
docker inspect -f '{{range $red, $c := .NetworkSettings.Networks}}        {{$red}}: {{$c.IPAddress}}/{{$c.IPPrefixLen}} (puerta {{$c.Gateway}}){{"\n"}}{{end}}' mi-postgres

# --- P4 · Nadie más entra ----------------------------------------------------------------------
titulo "P4 · Nadie más entra (última línea reject)"
if [ "$IP_DESDE_AULA_IP" = "$IP_SERVIDOR" ]; then
    # El gestor ve al servidor con su IP del aula: estas conexiones prueban las líneas del aula y el reject.
    r=$(servidor_sql "$IP_SERVIDOR" panel "$BIFI_PANEL_PASSWORD" 'SELECT 1')
    if echo "$r" | rechazado; then bien "panel desde el aula: rechazado"; else mal "panel desde el aula: $r"; fi
    r=$(PGPASSWORD="$DB_PASSWORD" PGCONNECT_TIMEOUT=5 psql -h "$IP_SERVIDOR" -U "$DB_USER" -d "$DB_NAME" -tAc 'SELECT 1' 2>&1)
    if echo "$r" | rechazado; then bien "$DB_USER (web) desde el aula: rechazado"; else mal "$DB_USER desde el aula: $r"; fi
    r=$(servidor_sql "$IP_SERVIDOR" nadie x 'SELECT 1')
    if echo "$r" | rechazado; then bien "usuario cualquiera desde el aula: rechazado"; else mal "usuario cualquiera: $r"; fi
    r=$(PGPASSWORD="$BIFI_RESP_PASSWORD" PGCONNECT_TIMEOUT=5 psql -h "$IP_SERVIDOR" -U resp_demo -d "$DB_NAME" -tAc 'SELECT 1' 2>&1)
    if echo "$r" | rechazado; then bien "resp_demo a otra base que no es bifi: rechazado"; else mal "resp_demo a $DB_NAME: $r"; fi
else
    echo "AVISO: el gestor no ve al servidor como $IP_SERVIDOR (ve '$IP_DESDE_AULA_IP'): P4 hay que probarlo"
    echo "       desde otro equipo del aula (db/README.md)."
fi

# --- P3 · Las redes del aula de pg_hba.conf son las de sede.env --------------------------------
titulo "P3 · Redes del aula en pg_hba.conf (la conexión desde otro equipo se prueba a mano)"
for red in $REDES_AULA; do
    if grep -Eq "^host[[:space:]]+bifi[[:space:]]+resp_demo[[:space:]]+$red[[:space:]]" db/conf/pg_hba.conf; then
        bien "resp_demo puede entrar desde $red (REDES_AULA)"
    else
        mal "falta en db/conf/pg_hba.conf la línea de resp_demo para $red (está en REDES_AULA de sede.env)"
    fi
done

# --- P5 · Límite de conexiones -----------------------------------------------------------------
titulo "P5 · Límite de conexiones (resp_demo: 2)"
for _ in 1 2; do
    servidor_sql "$IP_SERVIDOR" resp_demo "$BIFI_RESP_PASSWORD" 'SELECT pg_sleep(4)' >/dev/null &
done
sleep 1
r=$(servidor_sql "$IP_SERVIDOR" resp_demo "$BIFI_RESP_PASSWORD" 'SELECT 1')
wait
if echo "$r" | grep -q 'too many connections for role "resp_demo"'; then bien "tercera conexión: too many connections for role"; else mal "tercera conexión: $r"; fi
r=$(admin_sql postgres 'SHOW max_connections')
if [ "$r" = 50 ]; then bien "max_connections = 50"; else mal "max_connections = $r"; fi

# --- P6 · statement_timeout --------------------------------------------------------------------
titulo "P6 · statement_timeout (5 s)"
r=$(servidor_sql "$IP_SERVIDOR" resp_demo "$BIFI_RESP_PASSWORD" 'SELECT pg_sleep(6)')
if echo "$r" | grep -q "canceling statement due to statement timeout"; then bien "consulta de 6 s cortada a los 5 s"; else mal "pg_sleep(6): $r"; fi

# --- P8 · psql service=bifi con .pgpass en 600 -------------------------------------------------
titulo "P8 · psql service=bifi con ~/.pgpass (usuario $USUARIO_SO)"
CASA=$(getent passwd "$USUARIO_SO" | cut -d: -f6)
permisos=$(stat -c %a "$CASA/.pgpass" 2>/dev/null || echo "no existe")
if [ "$permisos" = 600 ]; then bien "$CASA/.pgpass en modo 600"; else mal "$CASA/.pgpass: $permisos"; fi
r=$(sudo -H -u "$USUARIO_SO" psql service=bifi -w -tAc 'SELECT current_user' 2>&1)
if [ "$r" = resp_demo ]; then bien "psql service=bifi entra como resp_demo sin pedir contraseña"; else mal "psql service=bifi: $r"; fi
if [ -z "$(find . -name .pgpass -o -name pgpass.conf)" ]; then bien "no hay ningún .pgpass dentro del repositorio"; else mal "hay un .pgpass dentro del repositorio"; fi

# --- stop_grace_period (solo con "parada") -----------------------------------------------------
esperar_sana() {
    for _ in $(seq 1 60); do
        [ "$(docker inspect -f '{{.State.Health.Status}}' mi-postgres 2>/dev/null)" = healthy ] && return 0
        sleep 1
    done
    return 1
}

if [ "${1:-}" = parada ]; then
    titulo "stop_grace_period"
    echo "      Docker esperará: $(docker inspect -f '{{.Config.StopTimeout}}' mi-postgres) s; señal: $(docker inspect -f '{{.Config.StopSignal}}' mi-postgres)"
    desde=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    inicio=$(date +%s)
    docker compose stop db >/dev/null 2>&1
    echo "      La parada ha tardado $(( $(date +%s) - inicio )) s"
    docker logs --since "$desde" mi-postgres 2>&1 | grep -E "fast shutdown request|database system is shut down" | sed 's/^/      /'
    desde=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    docker compose start db >/dev/null 2>&1
    esperar_sana || mal "la base no vuelve a estar healthy"
    if docker logs --since "$desde" mi-postgres 2>&1 | grep -q "not properly shut down"; then
        mal "el arranque ha necesitado recuperación: la parada no fue limpia"
    else
        bien "parada limpia: el siguiente arranque no necesita recuperación"
    fi
fi

echo
if [ "$FALLOS" -eq 0 ]; then echo "=== ASGBD RA2: todas las pruebas automáticas correctas (falta P3 desde otro equipo) ==="
else echo "=== ASGBD RA2: HAY PRUEBAS FALLIDAS ==="; fi
exit "$FALLOS"

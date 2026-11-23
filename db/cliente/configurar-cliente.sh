#!/bin/bash
# db/cliente/configurar-cliente.sh · Deja listo  psql service=bifi  para el usuario que lo ejecuta (P8)
#
#   bash configurar-cliente.sh <IP_DEL_SERVIDOR>
#
# Crea dos ficheros en el $HOME del usuario (FUERA del repositorio), los dos en modo 600:
#   ~/.pg_service.conf   a qué servidor, puerto, base y usuario apunta el servicio "bifi" (sin clave)
#   ~/.pgpass            la contraseña de resp_demo para ese servidor (psql solo lo lee si es 600)
#
# La contraseña se pide por teclado sin mostrarla. instalar.sh se la pasa por la entrada estándar.
# Se puede repetir: sustituye la entrada "bifi" anterior en los dos ficheros y deja el resto igual.
set -e

SERVIDOR="${1:-}"
PUERTO=5432
BASE=bifi
USUARIO=resp_demo

if [ -z "$SERVIDOR" ]; then
    echo "Uso: bash $0 <IP_DEL_SERVIDOR>     (por ejemplo: bash $0 192.168.6.105)"
    exit 1
fi
command -v psql >/dev/null || echo "AVISO: no hay psql en este equipo (Ubuntu/Debian: sudo apt install postgresql-client)"

# 1. Contraseña: del teclado (sin eco) o de la entrada estándar si viene por tubería
if [ -t 0 ]; then
    read -r -s -p "Contraseña de $USUARIO: " CLAVE; echo
else
    read -r CLAVE
fi
[ -n "$CLAVE" ] || { echo "ERROR: contraseña vacía"; exit 1; }

# En .pgpass los caracteres \ y : de la contraseña tienen que ir precedidos de \
CLAVE_PGPASS="${CLAVE//\\/\\\\}"
CLAVE_PGPASS="${CLAVE_PGPASS//:/\\:}"

umask 077    # todo lo que se cree aquí nace con permisos 600

# 2. ~/.pg_service.conf: se quita la sección [bifi] anterior (si la hay) y se escribe la nueva
SERVICIOS="$HOME/.pg_service.conf"
touch "$SERVICIOS"
awk '/^\[/ { dentro = ($0 == "[bifi]") } !dentro' "$SERVICIOS" > "$SERVICIOS.nuevo"
cat >> "$SERVICIOS.nuevo" <<EOF
[bifi]
host=$SERVIDOR
port=$PUERTO
dbname=$BASE
user=$USUARIO
EOF
mv "$SERVICIOS.nuevo" "$SERVICIOS"
chmod 600 "$SERVICIOS"

# 3. ~/.pgpass: se quita la línea de este servidor/base/usuario (si la hay) y se escribe la nueva
PGPASS="$HOME/.pgpass"
touch "$PGPASS"
awk -v inicio="$SERVIDOR:$PUERTO:$BASE:$USUARIO:" 'index($0, inicio) != 1' "$PGPASS" > "$PGPASS.nuevo"
printf '%s:%s:%s:%s:%s\n' "$SERVIDOR" "$PUERTO" "$BASE" "$USUARIO" "$CLAVE_PGPASS" >> "$PGPASS.nuevo"
mv "$PGPASS.nuevo" "$PGPASS"
chmod 600 "$PGPASS"

echo "Listo para $(whoami): $SERVICIOS y $PGPASS (modo 600)."
echo "Prueba:  psql service=bifi -c 'SELECT current_user, inet_client_addr();'"

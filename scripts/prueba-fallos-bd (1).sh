#!/bin/bash
# Provoca los 9 fallos de la tabla de la pregunta 7 contra la base REAL del repo
# (compose.yaml + .env) y guarda lo que ve el cliente y lo que dice el registro.
#
#   sudo ./scripts/prueba-fallos-bd.sh        (con la sede levantada: sudo ./instalar.sh)
#
# No modifica datos: el DELETE lo rechaza el propio gestor y el fallo 9 usa una COPIA del volumen.
# Las contraseñas se leen de .env y NO se escriben en el fichero de evidencias.
set -u
cd "$(dirname "$0")/.."

[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con sudo:  sudo ./scripts/prueba-fallos-bd.sh"; exit 1; }
[ -f .env ] || { echo "ERROR: no hay .env en $(pwd). Rellénalo y levanta la sede con: sudo ./instalar.sh"; exit 1; }
set -a; source .env; set +a
[ -f sede.env ] && source sede.env
[ "$(docker inspect -f '{{.State.Running}}' mi-postgres 2>/dev/null)" = true ] \
  || { echo "ERROR: mi-postgres no está en marcha. Levanta la sede (sudo ./instalar.sh) y espera a que esté healthy."; exit 1; }
for v in DB_NAME DB_USER DB_PASSWORD; do
  [ -n "${!v:-}" ] || { echo "ERROR: falta $v en .env"; exit 1; }
done

IMG=$(docker inspect -f '{{.Config.Image}}' mi-postgres)      # la imagen que usa la sede (p. ej. postgres:16)
OUT=evidencias/fallos-bd.txt
mkdir -p evidencias
: > "$OUT"

titulo()  { { echo; echo "=========================================================="; echo "## $1"; } | tee -a "$OUT"; }
cliente() { # la orden se muestra tal cual; las contraseñas viajan por entorno, no en la línea
  { echo "\$ $*"; echo "--- cliente ($(date '+%F %T')) ---"; } | tee -a "$OUT"
  "$@" 2>&1 | tee -a "$OUT"
  echo "(código de salida: ${PIPESTATUS[0]})" | tee -a "$OUT"
}
registro() {
  sleep 1
  echo "--- registro (docker logs --since 15s mi-postgres) ---" | tee -a "$OUT"
  docker logs --since 15s mi-postgres 2>&1 | grep -E 'FATAL|ERROR|DETAIL|STATEMENT' | tee -a "$OUT"
}

{ echo "Evidencias de fallos de la base de datos · $(date '+%F %T') · $(hostname)"
  echo "Imagen: $IMG · Versión: $(docker exec mi-postgres psql -U postgres -d "$DB_NAME" -tAc 'SHOW server_version;' 2>&1)"
  echo "Usuario de la web: $DB_USER · Base: $DB_NAME"; } | tee -a "$OUT"

titulo "1. Contraseña mal"
cliente docker exec -e PGPASSWORD=mala mi-postgres psql -h db -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1"; registro

titulo "2a. Usuario que no existe (por red, scram-sha-256)"
cliente docker exec -e PGPASSWORD=x mi-postgres psql -h db -U usuario_falso -d "$DB_NAME" -c "SELECT 1"; registro
titulo "2b. Usuario que no existe (socket local, trust)"
cliente docker exec mi-postgres psql -U usuario_falso -d "$DB_NAME" -c "SELECT 1"; registro

titulo "3. Base que no existe (contraseña buena)"
PGPASSWORD="$DB_PASSWORD" cliente docker exec -e PGPASSWORD mi-postgres psql -h db -U "$DB_USER" -d db_falsa -c "SELECT 1"; registro

titulo "4. La web intenta borrar (el usuario solo puede leer, insertar y editar)"
PGPASSWORD="$DB_PASSWORD" cliente docker exec -e PGPASSWORD mi-postgres psql -h db -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM inventario WHERE false;"; registro

titulo "5. Tabla que no existe"
PGPASSWORD="$DB_PASSWORD" cliente docker exec -e PGPASSWORD mi-postgres psql -h db -U "$DB_USER" -d "$DB_NAME" -c "SELECT * FROM tabla_falsa;"; registro

titulo "6. Cliente fuera de la red (HACER A MANO desde OTRA máquina del aula)"
IP_SRV="${IP_AULA%/*}"; [ -n "$IP_SRV" ] || IP_SRV=$(hostname -I | awk '{print $1}')
echo "En otra máquina: nc -zv -w 3 $IP_SRV 5432   -> anota la salida aquí" | tee -a "$OUT"
echo "Después, en el servidor: docker logs --tail 20 mi-postgres  (no debe aparecer ese intento)" | tee -a "$OUT"
echo "Puertos que publica la base (debe salir vacío): '$(docker port mi-postgres)'" | tee -a "$OUT"

titulo "7. Primer arranque sin contraseña"
cliente docker run --rm --name test-sin-pass "$IMG"

titulo "8. Error en el SQL de inicialización"
rm -rf /tmp/init-malo && mkdir -p /tmp/init-malo && echo 'SELEC 1;' > /tmp/init-malo/xx.sql
cliente docker run --rm --name test-init-malo -e POSTGRES_PASSWORD=prueba -v /tmp/init-malo:/docker-entrypoint-initdb.d:ro "$IMG"
rm -rf /tmp/init-malo

titulo "9. Otra versión mayor (postgres:17) con una COPIA del volumen; el real no se toca"
VOL=$(docker volume ls -q | grep -E '(^|_)datos$' | head -1)
if [ -z "$VOL" ]; then
  echo "No encuentro el volumen de datos (…_datos). Mira: docker volume ls" | tee -a "$OUT"
else
  echo "Volumen copiado: $VOL" | tee -a "$OUT"
  docker volume rm -f pgcopia-v17 >/dev/null 2>&1; docker volume create pgcopia-v17 >/dev/null
  docker run --rm -v "$VOL":/o:ro -v pgcopia-v17:/d alpine:3.20 sh -c 'cp -a /o/. /d/' >/dev/null 2>&1
  cliente timeout 60 docker run --rm --name test-v17 -e POSTGRES_PASSWORD=prueba -v pgcopia-v17:/var/lib/postgresql/data postgres:17
  docker volume rm -f pgcopia-v17 >/dev/null
fi

echo; echo "Listo: revisa $OUT y copia cada salida a la tabla."

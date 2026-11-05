#!/bin/bash
# Provoca los 9 fallos de la tabla de la pregunta 7 y guarda lo que ve el cliente
# y lo que dice el registro. Ejecutar en el servidor, en /home/asir2/proyecto_huesca,
# con la sede levantada. No modifica datos (el DELETE lo rechaza el propio gestor).
set -u
OUT=evidencias/fallos-bd.txt
mkdir -p evidencias
: > "$OUT"

titulo() { { echo; echo "=========================================================="; echo "## $1"; } | tee -a "$OUT"; }
cliente() { # orden completa como argumentos
  { echo "\$ $*"; echo "--- cliente ($(date '+%F %T')) ---"; } | tee -a "$OUT"
  "$@" 2>&1 | tee -a "$OUT"
  echo "(código de salida: ${PIPESTATUS[0]})" | tee -a "$OUT"
}
registro() {
  sleep 1
  { echo "--- registro (docker logs --since 15s mi-postgres) ---"; } | tee -a "$OUT"
  docker logs --since 15s mi-postgres 2>&1 | grep -E 'FATAL|ERROR|DETAIL|STATEMENT' | tee -a "$OUT"
}
WEB='PGPASSWORD=$(cat /run/secrets/db_web_password) psql -h db -U web_huesca'

titulo "1. Contraseña mal"
cliente docker exec -e PGPASSWORD=mala mi-postgres psql -h db -U web_huesca -d mi_base_datos -c "SELECT 1"; registro

titulo "2a. Usuario que no existe (por red, scram-sha-256)"
cliente docker exec -e PGPASSWORD=x mi-postgres psql -h db -U usuario_falso -d mi_base_datos -c "SELECT 1"; registro
titulo "2b. Usuario que no existe (socket local, trust)"
cliente docker exec mi-postgres psql -U usuario_falso -d mi_base_datos -c "SELECT 1"; registro

titulo "3. Base que no existe (contraseña buena)"
cliente docker exec mi-postgres sh -c "$WEB -d db_falsa -c 'SELECT 1'"; registro

titulo "4. La web intenta borrar"
cliente docker exec mi-postgres sh -c "$WEB -d mi_base_datos -c 'DELETE FROM inventario;'"; registro

titulo "5. Tabla que no existe"
cliente docker exec mi-postgres sh -c "$WEB -d mi_base_datos -c 'SELECT * FROM tabla_falsa;'"; registro

titulo "6. Cliente fuera de la red (HACER A MANO desde OTRA máquina del aula)"
echo "En otra máquina: nc -zv -w 3 $(hostname -I | awk '{print $1}') 5432   -> pega aquí la salida (y confirma que docker logs no muestra nada)" | tee -a "$OUT"

titulo "7. Primer arranque sin contraseña"
cliente docker run --rm --name test-sin-pass postgres:16.15

titulo "8. Error en el SQL de inicialización"
rm -rf /tmp/init-malo && mkdir -p /tmp/init-malo && echo 'SELEC 1;' > /tmp/init-malo/xx.sql
cliente docker run --rm --name test-init-malo -e POSTGRES_PASSWORD=prueba -v /tmp/init-malo:/docker-entrypoint-initdb.d:ro postgres:16.15
rm -rf /tmp/init-malo

titulo "9. Otra versión mayor con una COPIA del volumen (el real no se toca)"
VOL=$(docker volume ls -q | grep postgres_data | head -1)
docker volume rm -f pgcopia-v17 >/dev/null 2>&1; docker volume create pgcopia-v17 >/dev/null
docker run --rm -v "$VOL":/o:ro -v pgcopia-v17:/d alpine:3.20 sh -c 'cp -a /o/. /d/'
cliente timeout 60 docker run --rm --name test-v17 -e POSTGRES_PASSWORD=prueba -v pgcopia-v17:/var/lib/postgresql/data postgres:17
docker volume rm -f pgcopia-v17 >/dev/null

echo; echo "Listo: revisa y copia a la tabla desde $OUT"

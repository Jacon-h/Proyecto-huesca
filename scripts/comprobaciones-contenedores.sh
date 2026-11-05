#!/bin/bash
# Parte 1: apartado 5 (sede). Parte 2: los 3 fallos del paso 8 en el LABORATORIO "pila".
# Uso:  ./comprobaciones-contenedores.sh sede        (solo lectura, en /home/asir2/proyecto_huesca)
#       ./comprobaciones-contenedores.sh pila        (en la carpeta del laboratorio; BORRA el volumen del lab)
set -u
mkdir -p evidencias
OUT=evidencias/contenedores-$1.txt
: > "$OUT"
t() { { echo; echo "=== $1 ==="; } | tee -a "$OUT"; }
c() { { echo "\$ $*"; } | tee -a "$OUT"; bash -c "$*" 2>&1 | tee -a "$OUT"; }

if [ "${1:-}" = "sede" ]; then
  t "1. Compose válido";            c 'docker compose config -q; echo $?'
  t "2. Estado y salud";            c 'docker compose ps'
  t "6. Puertos publicados";        c "ss -lntp | grep -E ':(80|2222|53|5432)' || true"
  t "7. Red trasera interna";       c "for n in \$(docker network ls --format '{{.Name}}' | grep trasera); do echo \$n; docker network inspect \$n --format '{{.Internal}}'; done"
  t "4. (manual) tras 'sudo reboot'"; echo "Ejecuta después: uptime -s ; systemctl is-enabled docker ; docker compose ps" | tee -a "$OUT"
  t "5. (manual, otra máquina)";      echo "nc -zv -w 3 IP_SERVIDOR 5432   y   nc -zv -w 3 IP_SERVIDOR 80" | tee -a "$OUT"

elif [ "${1:-}" = "pila" ]; then
  grep -q '^name: pila' compose.yaml || { echo "ABORTO: esta carpeta no es el laboratorio 'pila'."; exit 1; }
  cp .env .env.bak
  t "Fallo 1: borrar DB_CLAVE"
  sed -i '/DB_CLAVE/d' .env
  c 'docker compose down -v'; c 'docker compose up -d'; c 'docker compose config -q'
  c 'docker compose ps -a'; c 'docker compose logs --tail=50 db'
  c "docker inspect pila-db-1 --format '{{.State.Status}} {{.State.ExitCode}}'"
  cp .env.bak .env; docker compose down -v >/dev/null 2>&1

  t "Fallo 2: puerto ocupado"
  (python3 -m http.server 8080 >/dev/null 2>&1 & echo $! > /tmp/pid8080)
  sleep 1
  c 'docker compose up -d'; c 'docker compose ps -a'; c "ss -lntp | grep 8080"
  kill "$(cat /tmp/pid8080)" 2>/dev/null; docker compose down -v >/dev/null 2>&1

  t "Fallo 3: nombre de imagen mal puesto"
  sed 's#image: postgres:16#image: postgress:16#' compose.yaml > compose.mal.yaml
  c 'docker compose -f compose.mal.yaml config -q; echo $?'
  c 'docker compose -f compose.mal.yaml pull'
  c 'docker compose -f compose.mal.yaml up -d'
  rm -f compose.mal.yaml
  t "Fallo 3b: etiqueta inexistente"
  sed 's#image: postgres:16#image: postgres:99#' compose.yaml > compose.mal.yaml
  c 'docker compose -f compose.mal.yaml up -d'
  rm -f compose.mal.yaml
else
  echo "Uso: $0 sede|pila"; exit 1
fi
echo; echo "Listo: copia la salida desde $OUT"

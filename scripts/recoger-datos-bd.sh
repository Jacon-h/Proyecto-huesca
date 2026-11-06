#!/bin/bash
# Recoge, SOLO LECTURA, los datos reales de la base para terminar la investigación.
# No imprime contraseñas. Uso:  sudo ./scripts/recoger-datos-bd.sh   (desde la raíz del repo)
set -u
cd "$(dirname "$0")/.."
[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con sudo"; exit 1; }
set -a; source .env; set +a
OUT=evidencias/datos-bd.txt; mkdir -p evidencias; : > "$OUT"
c() { { echo; echo "\$ $*"; } | tee -a "$OUT"; bash -c "$*" 2>&1 | tee -a "$OUT"; }
PSQL="docker exec mi-postgres psql -U postgres -d $DB_NAME"

{ echo "Datos de la base · $(date '+%F %T') · $(hostname)"; } | tee -a "$OUT"
c "docker compose ps"
c "docker top mi-postgres"
c "docker stats --no-stream --format 'cpu={{.CPUPerc}} mem={{.MemUsage}} red={{.NetIO}} disco={{.BlockIO}}' mi-postgres"
c "docker inspect mi-postgres --format 'imagen={{.Config.Image}} reinicio={{.HostConfig.RestartPolicy.Name}} puertos={{json .HostConfig.PortBindings}} redes={{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}} {{end}}'"
c "docker network inspect \$(docker network ls --format '{{.Name}}' | grep trasera) --format 'red={{.Name}} interna={{.Internal}}'"
c "docker volume ls"
c "docker volume inspect \$(docker volume ls -q | grep -E '(^|_)datos\$' | head -1) --format '{{.Name}} -> {{.Mountpoint}}'"
c "$PSQL -c 'SELECT version();'"
c "$PSQL -c '\\du'"
c "$PSQL -c '\\dp inventario'"
c "$PSQL -c 'SELECT count(*) FROM inventario;'"
c "$PSQL -c \"SELECT name, setting FROM pg_settings WHERE name IN ('listen_addresses','port','max_connections','shared_buffers','password_encryption','log_connections','log_disconnections','log_line_prefix','data_directory','hba_file') ORDER BY 1;\""
c "docker exec mi-postgres sh -c \"grep -v '^#' /var/lib/postgresql/data/pg_hba.conf | grep -v '^\$'\""
c "docker exec mi-postgres ls -la /var/lib/postgresql/data"
c "docker exec mi-postgres sh -c 'ls /docker-entrypoint-initdb.d'"
c "docker logs --tail 15 mi-postgres"
c "docker port mi-postgres; echo \"(salida vacía = no publica nada)\"; ss -ltn | grep -c ':5432 ' || true"
echo; echo "Listo: pásame $OUT"

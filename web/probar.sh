#!/bin/bash
# Pruebas HTTP de la sede. Devuelve 0 si todo es correcto y 1 si algo falla.
cd "$(dirname "$0")/.."
set -a; source .env; set +a

FALLOS=0
probar() {                         # probar "nombre" código_esperado args_de_curl...
    local nombre="$1" esperado="$2" code=""; shift 2
    for _ in 1 2 3 4 5 6 7 8 9 10; do          # Apache y la BD pueden tardar unos segundos
        code=$(curl -s -o /dev/null -w '%{http_code}' "$@" || true)
        [ "$code" = "$esperado" ] && break
        sleep 3
    done
    if [ "$code" = "$esperado" ]; then echo "OK    $nombre ($code)"
    else echo "FALLO $nombre: esperado $esperado, recibido $code"; FALLOS=1; fi
}

WWW="Host: www.huesca.empresa.lan"
INTRA="Host: intranet.huesca.empresa.lan"
GIT="Host: git.huesca.empresa.lan"

probar "1. Web pública"          200 -H "$WWW"   http://localhost/
probar "2. Intranet sin clave"   401 -H "$INTRA" http://localhost/
probar "3. Intranet con clave"   200 -u "$INTRANET_USUARIO:$INTRANET_CLAVE" -H "$INTRA" http://localhost/
probar "4. Recurso inexistente"  404 -H "$WWW"   http://localhost/noexiste
probar "5. Git (proxy a Forgejo)" 200 -H "$GIT"   http://localhost/api/healthz

exit $FALLOS

# shellcheck shell=bash
# scripts/gns3.sh · Fase "gns3": servidor GNS3 y proyecto de la red interna.
# No se ejecuta solo: lo carga instalar.sh (usa sus variables y funciones).
#   sudo ./instalar.sh gns3
GNS3_VERSION_PIP="2.2.61"
GNS3_PUERTO=3080
GNS3_LOG=/var/log/instalar-gns3.log
GNS3_API="http://127.0.0.1:$GNS3_PUERTO/v2"
GNS3_PROYECTO="gns3/red_huesca.gns3project"
GNS3_IMAGEN_NUEVA=0

gns3_usuario() {
    id gns3 &>/dev/null || useradd --system --create-home --home-dir /opt/gns3 --shell /usr/sbin/nologin gns3
    mkdir -p /opt/gns3
    for g in docker kvm ubridge; do
        getent group "$g" >/dev/null && usermod -aG "$g" gns3
    done
    return 0
}

gns3_paquetes_ppa() {
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:gns3/ppa
    apt-get update
    apt-get install -y gns3-server ubridge dynamips vpcs
}

gns3_paquetes_pip() {
    apt-get install -y python3-venv python3-pip build-essential libpcap-dev git dynamips
    python3 -m venv /opt/gns3/venv
    /opt/gns3/venv/bin/pip install --upgrade pip
    /opt/gns3/venv/bin/pip install "gns3-server==$GNS3_VERSION_PIP"
    ln -sf /opt/gns3/venv/bin/gns3server /usr/local/bin/gns3server

    local tmp; tmp=$(mktemp -d)
    git clone --depth 1 --branch v0.9.19 https://github.com/GNS3/ubridge.git "$tmp/ubridge"
    make -C "$tmp/ubridge"
    install -m 755 "$tmp/ubridge/ubridge" /usr/local/bin/ubridge
    git clone --depth 1 --branch v0.8.5 https://github.com/GNS3/vpcs.git "$tmp/vpcs"
    (cd "$tmp/vpcs/src" && ./mk.sh)
    install -m 755 "$tmp/vpcs/src/vpcs" /usr/local/bin/vpcs
    rm -rf "$tmp"
}

gns3_instalar_servidor() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y curl ca-certificates libcap2-bin gettext-base >/dev/null
    gns3_usuario

    if command -v gns3server &>/dev/null && command -v ubridge &>/dev/null \
       && command -v vpcs &>/dev/null && command -v dynamips &>/dev/null; then
        echo "    GNS3 ya está instalado ($(gns3server --version 2>/dev/null | tail -1))"
    else
        echo "    Instalando GNS3 (puede tardar unos minutos; detalle en $GNS3_LOG)"
        if ( gns3_paquetes_ppa ) >>"$GNS3_LOG" 2>&1; then
            echo "    Instalado desde el PPA oficial de GNS3"
        else
            echo "    El PPA no ha servido; instalo con pip y compilo ubridge y vpcs"
            add-apt-repository -r -y ppa:gns3/ppa >>"$GNS3_LOG" 2>&1 || true
            if ! ( gns3_paquetes_pip ) >>"$GNS3_LOG" 2>&1; then
                echo "ERROR: no he podido instalar GNS3. Últimas líneas de $GNS3_LOG:"; tail -15 "$GNS3_LOG"; exit 1
            fi
        fi
    fi

    gns3_usuario
    gns3_permisos_ubridge
    chown -R gns3:gns3 /opt/gns3
}

gns3_permisos_ubridge() {
    local U; U="$(command -v ubridge)" || return 0
    U="$(readlink -f "$U")"
    if [ -u "$U" ]; then
        setcap -r "$U" 2>/dev/null || true
        getent group ubridge >/dev/null && chgrp ubridge "$U" && chmod 4750 "$U"
    else
        setcap cap_net_admin,cap_net_raw,cap_sys_admin,cap_sys_ptrace=ep "$U" 2>/dev/null || true
        chmod 755 "$U"
    fi
    return 0
}

gns3_imagen_dns_secundario() {
    { [ -f generado/tsig.conf ] && [ -f generado/dns-secundario/named.conf.local ]; } || dns
    local ctx=generado/dns-secundario/imagen antes despues
    rm -rf "$ctx"; mkdir -p "$ctx"
    cp gns3/dns-secundario/Dockerfile gns3/dns-secundario/named.conf.options "$ctx/"
    cp generado/dns-secundario/named.conf.local generado/tsig.conf "$ctx/"
    export IP_DNS_SECUNDARIO IP_INTERNA_SOLO="${IP_INTERNA%/*}" PREFIJO_INTERNA="${IP_INTERNA#*/}"
    envsubst '${IP_DNS_SECUNDARIO} ${PREFIJO_INTERNA} ${IP_INTERNA_SOLO}' \
        < gns3/dns-secundario/entrypoint.sh.tpl > "$ctx/entrypoint.sh"

    antes=$(docker images -q dns-secundario:1.0)
    docker build -q -t dns-secundario:1.0 "$ctx" >/dev/null
    despues=$(docker images -q dns-secundario:1.0)
    # Si la imagen ha cambiado (p. ej. nueva clave TSIG), el nodo de GNS3 debe crearse de nuevo
    [ "$antes" = "$despues" ] || GNS3_IMAGEN_NUEVA=1
    echo "    Imagen dns-secundario:1.0 lista"
}

gns3_servicio() {
    local bin espera=""; bin=$(command -v gns3server)
    if [ -f /etc/netplan/60-sede.yaml ]; then
        cat > /usr/local/sbin/gns3-espera-puente.sh <<'ESPERA'
#!/bin/bash
for _ in $(seq 1 30); do ip link show "$1" >/dev/null 2>&1 && exit 0; sleep 1; done
exit 0
ESPERA
        chmod 755 /usr/local/sbin/gns3-espera-puente.sh
        espera="ExecStartPre=-/usr/local/sbin/gns3-espera-puente.sh $BRIDGE_INTERNA"
    fi
    cat > /etc/systemd/system/gns3server.service <<UNIT
[Unit]
Description=GNS3 server (sede $SEDE)
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
User=gns3
Group=gns3
WorkingDirectory=/opt/gns3
$espera
ExecStart=$bin --host 0.0.0.0 --port $GNS3_PUERTO
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable gns3server >/dev/null 2>&1
    systemctl restart gns3server

    ufw allow from 172.16.0.0/12 to any port "$GNS3_PUERTO" proto tcp >/dev/null 2>&1 || true

    for _ in $(seq 1 60); do
        curl -fs "$GNS3_API/version" >/dev/null 2>&1 && return 0
        sleep 1
    done
    echo "ERROR: gns3server no responde en el puerto $GNS3_PUERTO"; journalctl -u gns3server -n 20 --no-pager || true
    exit 1
}

gns3_nodos_parados() {
    curl -s "$GNS3_API/projects/$1/nodes" 2>/dev/null | python3 -c '
import sys, json
try: print(sum(1 for n in json.load(sys.stdin) if n.get("status") != "started"))
except Exception: print(99)'
}

gns3_importar() {
    curl -fsS -o /dev/null -X POST -H 'Content-Type: application/octet-stream' \
        --data-binary @"$GNS3_PROYECTO" "$GNS3_API/projects/$1/import?name=red%20huesca"
    curl -fsS -o /dev/null -X PUT -H 'Content-Type: application/json' \
        -d '{"auto_open":true,"auto_start":true}' "$GNS3_API/projects/$1"
}

gns3_proyecto() {
    local id code parados
    id=$(python3 -c 'import sys,json,zipfile; print(json.loads(zipfile.ZipFile(sys.argv[1]).read("project.gns3"))["project_id"])' "$GNS3_PROYECTO")
    code=$(curl -s -o /dev/null -w '%{http_code}' "$GNS3_API/projects/$id")
    if [ "$code" != 404 ] && [ "$GNS3_IMAGEN_NUEVA" = 1 ]; then
        echo "    La imagen del DNS secundario ha cambiado: recreo el proyecto para que la use"
        curl -s -o /dev/null -X DELETE "$GNS3_API/projects/$id"
        code=404
    fi
    if [ "$code" = 404 ]; then
        echo "    Importando el proyecto de la red interna"
        gns3_importar "$id" || { echo "ERROR: no he podido importar $GNS3_PROYECTO"; exit 1; }
    fi

    for intento in 1 2 3; do
        curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{}' "$GNS3_API/projects/$id/open"
        curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{}' "$GNS3_API/projects/$id/nodes/start"
        sleep 3
        parados=$(gns3_nodos_parados "$id")
        [ "$parados" = 0 ] && break
        if [ "$intento" = 2 ]; then
            echo "    Los nodos no arrancan; vuelvo a importar el proyecto desde cero"
            curl -s -o /dev/null -X DELETE "$GNS3_API/projects/$id"
            gns3_importar "$id" || true
        fi
    done

    if [ "$parados" = 0 ]; then echo "    Proyecto 'red huesca' abierto y con todos los nodos arrancados"
    else
        echo "AVISO: $parados nodo(s) de GNS3 sin arrancar (¿existe $BRIDGE_INTERNA? ¿está la imagen dns-secundario:1.0?)"
        echo "   ubridge: $(ls -l "$(command -v ubridge)" 2>/dev/null | awk '{print $1, $3, $4}')  caps: $(getcap "$(command -v ubridge)" 2>/dev/null)"
        echo "   usuario gns3: $(id gns3 2>/dev/null)"
        journalctl -u gns3server -n 15 --no-pager 2>/dev/null || true
    fi
}

gns3() {
    echo "== GNS3 (servidor y proyecto de la red interna)"
    gns3_instalar_servidor
    gns3_imagen_dns_secundario
    gns3_servicio
    gns3_proyecto
}


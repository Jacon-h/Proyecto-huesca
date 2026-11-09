#!/bin/bash
#
# instalar.sh · Despliegue de la sede Huesca
#
#   sudo ./instalar.sh             todas las fases, una detrás de otra
#   sudo ./instalar.sh <fase>      solo una fase (comprobar va siempre delante)
#
# Se puede repetir sin romper nada: cada fase mira primero qué hay hecho.
# (Excepción: la fase web recrea ldap y lam y BORRA sus volúmenes, como antes.)

set -eo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------- Correcciones previas de entorno
# Auto-corregir formato de saltos de línea Windows (CRLF a LF) si se editó en Windows
if command -v sed &>/dev/null; then
    find . -maxdepth 3 -type f -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
fi

# Asignar permisos de ejecución a todos los scripts .sh del proyecto de forma automática
find . -maxdepth 3 -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con sudo:  sudo ./instalar.sh"; exit 1; }

# Solo un instalar.sh a la vez (dos a la vez se pisarían)
exec 9>/var/lock/instalar-sede.lock
flock -n 9 || { echo "ERROR: ya hay otro instalar.sh en marcha"; exit 1; }

FALLOS=0
titulo() { echo "== $*"; }
bien()   { echo "OK    $*"; }
mal()    { echo "FALLO $*"; FALLOS=1; }

# ---------------------------------------------------------------- Garantía de Conectividad DNS
# Garantiza que el sistema conserve resolución de nombres hacia Internet incluso si systemd-resolved o BIND cambian
asegurar_dns() {
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        return 0 # Si no hay ni enlace IP a Internet, no forzamos cambio de resolv.conf
    fi
    if ! host ppa.launchpadcontent.net &>/dev/null && ! host github.com &>/dev/null; then
        echo "    [+] Restaurando resolución DNS hacia Internet (8.8.8.8)..."
        if [ -L /etc/resolv.conf ]; then
            rm -f /etc/resolv.conf
        fi
        printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf
    fi
}

# ---------------------------------------------------------------- Requisitos
if ! command -v docker &>/dev/null; then
    titulo "Docker no está instalado. Instalándolo..."
    asegurar_dns
    apt-get update && apt-get install -y docker.io docker-compose-v2
    usermod -aG docker "${SUDO_USER:-root}" || true
fi
command -v openssl &>/dev/null || apt-get install -y openssl

# Verificación y autocopia de sede.env para evitar fallos al realizar source
if [ ! -f sede.env ]; then
    if [ -f sede.env.example ]; then
        echo "[+] Creando sede.env a partir de sede.env.example..."
        cp sede.env.example sede.env
    else
        echo "AVISO: No se encontró sede.env ni sede.env.example."
    fi
fi

if [ -f sede.env ]; then
    source sede.env          # SEDE, DOMINIO, IP_AULA, BRIDGE_INTERNA…
fi

# Valores derivados de sede.env, calculados una sola vez (con valores por defecto seguros)
IP_AULA_SOLO="${IP_AULA%/*}"
IP_INTERNA_SOLO="${IP_INTERNA%/*}"
PREFIJO_INTERNA="${IP_INTERNA#*/}"
IMAGEN_BIND="${IMAGEN_BIND:-internetsystemsconsortium/bind9:9.18}"


# ================================================================== FASES

# El reloj de la VM se atrasa (pausas, cuelgues de CPU) y entonces apt rechaza los repositorios
# ("Not live until ...") y los docker build fallan. Se compara con la hora HTTP de un servidor
# fiable y, si hay más de 60 s de diferencia, se corrige (también en el reloj hardware).
ajustar_reloj() {
    asegurar_dns
    command -v curl &>/dev/null || { echo "    AVISO: no hay curl, no compruebo el reloj"; return 0; }
    local fecha="" url ref ahora dif
    for url in https://deb.debian.org https://www.google.com; do
        fecha=$(curl -sI --max-time 5 "$url" 2>/dev/null | tr -d '\r' \
                | awk -F': ' 'tolower($1)=="date" {print $2; exit}') || true
        [ -z "$fecha" ] || break
    done
    [ -n "$fecha" ] || { echo "    AVISO: no he podido consultar la hora en Internet; no compruebo el reloj"; return 0; }
    ref=$(date -u -d "$fecha" +%s 2>/dev/null) || return 0
    ahora=$(date -u +%s)
    dif=$(( ref - ahora )); [ "$dif" -ge 0 ] || dif=$(( -dif ))
    if [ "$dif" -gt 60 ]; then
        echo "    AVISO: el reloj de la VM se desvía $dif s; lo corrijo"
        date -u -s "@$ref" >/dev/null
        hwclock --systohc 2>/dev/null || true
    fi
    timedatectl set-ntp true 2>/dev/null || true
}

comprobar() {
    titulo "Comprobando que se puede instalar"
    asegurar_dns
    ajustar_reloj
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            cp .env.example .env
            chown "${SUDO_USER:-root}:$(id -gn "${SUDO_USER:-root}")" .env 2>/dev/null || true
            chmod 600 .env
            echo "ERROR: no había .env; lo he creado desde .env.example. Rellénalo (nano .env) y vuelve a ejecutar."
            exit 1
        else
            echo "ERROR: no existe .env ni .env.example."
            exit 1
        fi
    fi
    set -a; source .env; set +a
    for v in DB_NAME DB_USER DB_PASSWORD POSTGRES_PASSWORD INTRANET_USUARIO INTRANET_CLAVE LDAP_ADMIN_PASSWORD LDAP_CONFIG_PASSWORD LAM_PASSWORD; do
        [ -n "${!v:-}" ] || { echo "ERROR: falta $v en .env"; exit 1; }
    done
    [ "$DB_USER" != postgres ] || { echo "ERROR: DB_USER no puede ser 'postgres' (es el administrador)"; exit 1; }
    if ! docker compose version >/dev/null 2>&1 && ! docker-compose version >/dev/null 2>&1; then
        echo "ERROR: falta el plugin docker compose"; exit 1;
    fi
    echo "    Todo listo para instalar la sede ${SEDE:-Huesca}"
}


# Descarga las imágenes de Docker en segundo plano mientras se hacen otras fases
# (GNS3 tarda minutos). Si falla, no pasa nada: "compose up" volverá a intentarlo
# y mostrará el error de verdad.
PULL_PID=""
precargar_imagenes() {
    ( docker compose pull -q --ignore-buildable >/var/log/instalar-pull.log 2>&1 || docker-compose pull -q --ignore-buildable >/var/log/instalar-pull.log 2>&1 ) &
    PULL_PID=$!
}
esperar_imagenes() {
    [ -z "$PULL_PID" ] || wait "$PULL_PID" || echo "AVISO: alguna imagen no se ha podido descargar (ver /var/log/instalar-pull.log)"
    PULL_PID=""
}


red() {
    titulo "Red"
    asegurar_dns
    apt-get install -y iptables gettext-base >/dev/null

    export INTERFAZ_AULA IP_AULA PUERTA_AULA RESOLUTOR_CENTRO IP_INTERNA BRIDGE_INTERNA
    envsubst < red/60-sede.yaml.tpl > /tmp/60-sede.yaml
    if ! cmp -s /tmp/60-sede.yaml /etc/netplan/60-sede.yaml; then
        mkdir -p /etc/netplan/original
        for f in /etc/netplan/*.yaml; do
            [ "$f" = /etc/netplan/60-sede.yaml ] || [ ! -e "$f" ] || mv "$f" /etc/netplan/original/
        done
        install -m 600 /tmp/60-sede.yaml /etc/netplan/60-sede.yaml
        netplan generate
        netplan apply
    fi

    install -m 644 red/99-sede.conf /etc/sysctl.d/99-sede.conf
    sysctl --system >/dev/null

    mkdir -p /etc/sede
    install -m 644 sede.env /etc/sede/sede.env
    install -m 755 red/sede-nat.sh /usr/local/sbin/sede-nat.sh
    install -m 644 red/sede-nat.service /etc/systemd/system/sede-nat.service
    systemctl daemon-reload
    systemctl enable sede-nat.service >/dev/null
    systemctl restart sede-nat.service
}

# La fase red cambia la IP del servidor: solo se aplica sola si NO puede cortarte el acceso,
# es decir, si la interfaz del aula existe y ya tiene la IP que dice sede.env.
red_automatica() {
    if ip -4 -br addr show "${INTERFAZ_AULA:-eth0}" 2>/dev/null | grep -q "$IP_AULA_SOLO"; then
        red
    else
        echo "AVISO: ${INTERFAZ_AULA:-interfaz} no existe o no tiene $IP_AULA_SOLO: salto la fase red."
        echo "       Si es el servidor real, ejecuta:  sudo ./instalar.sh red"
    fi
}


sistema() {
    titulo "Sistema, usuarios y cortafuegos"
    asegurar_dns
    apt-get install -y openssh-server >/dev/null
    mkdir -p /etc/ssh/sshd_config.d
    bash sistema/config_red_ufw.sh
    bash sistema/usuarios/crear_usuario.sh

    # Solo se prohíbe la contraseña si alguien puede entrar con clave: si no, nos quedaríamos fuera.
    if [ -f sistema/usuarios/sshd_seguridad.conf ] && ls /home/*/.ssh/authorized_keys &>/dev/null; then
        install -m 644 sistema/usuarios/sshd_seguridad.conf /etc/ssh/sshd_config.d/seguridad.conf
        if sshd -t; then systemctl restart ssh
        else rm -f /etc/ssh/sshd_config.d/seguridad.conf; echo "AVISO: sshd_config inválido, revertido"; fi
    else
        echo "AVISO: no hay claves SSH instaladas; no aplico el hardening de sshd."
    fi
}


# ---------------------------------------------------------------- DNS

liberar_puerto_53() {
    # Ubuntu arranca systemd-resolved escuchando en 127.0.0.53:53 y BIND no puede usar el 53.
    if ss -lntup 2>/dev/null | grep -qE '127\.0\.0\.53(%lo)?:53 '; then
        echo "    Liberando el puerto 53 (systemd-resolved)"
        mkdir -p /etc/systemd/resolved.conf.d
        printf '[Resolve]\nDNSStubListener=no\nDNS=8.8.8.8 1.1.1.1\nFallbackDNS=8.8.4.4\n' > /etc/systemd/resolved.conf.d/sede-nostub.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    fi
    asegurar_dns
}

# Clave TSIG: firma las transferencias de zona entre el DNS principal y el secundario de GNS3.
# Se crea UNA sola vez (si cambiara, el secundario dejaría de recibir las zonas) y se reparte
# a BIND (generado/dns/tsig.conf) y al contexto de la imagen del secundario.
clave_tsig() {
    mkdir -p generado/dns
    if [ ! -f generado/tsig.conf ]; then
        ( umask 077
          printf 'key "clave-transferencia" {\n    algorithm hmac-sha256;\n    secret "%s";\n};\n' \
                 "$(openssl rand -base64 32)" > generado/tsig.conf )
        echo "    Clave TSIG creada en generado/tsig.conf"
    fi
    install -m 644 generado/tsig.conf generado/dns/tsig.conf
}

dns() {
    titulo "Servidor DNS (BIND9)"
    liberar_puerto_53

    # --- Valores derivados de sede.env
    IFS=. read -r o1 o2 o3 _ <<< "${RED_INTERNA:-10.2.0.0/16}"
    ZONA_INVERSA="${o2}.${o1}.in-addr.arpa"                  # 2.10.in-addr.arpa
    PTR_SERVIDOR="${IP_INTERNA_SOLO##*.}.${o3}"              # 1.0 (dentro de la zona anterior)
    ACL_AULA=""; for r in ${REDES_AULA:-}; do ACL_AULA+="$r; "; done

    # Serial siempre creciente (YYYYMMDDHH, o el anterior +1): así el secundario se entera de cada cambio
    mkdir -p generado/dns/interna generado/dns/aula generado/dns-secundario
    SERIAL=$(date +%Y%m%d%H)
    if [ -f generado/serial ] && [ "$SERIAL" -le "$(cat generado/serial)" ]; then SERIAL=$(( $(cat generado/serial) + 1 )); fi
    echo "$SERIAL" > generado/serial

    export DOMINIO RED_INTERNA IP_INTERNA_SOLO IP_AULA_SOLO IP_DNS_SECUNDARIO ZONA_INVERSA PTR_SERVIDOR ACL_AULA SERIAL
    # envsubst SOLO con esta lista, para no tocar los $TTL de las zonas
    VARS='${DOMINIO} ${RED_INTERNA} ${IP_INTERNA_SOLO} ${IP_AULA_SOLO} ${IP_DNS_SECUNDARIO} ${ZONA_INVERSA} ${PTR_SERVIDOR} ${ACL_AULA} ${SERIAL}'

    cp dns/named.conf dns/named.conf.options generado/dns/
    envsubst "$VARS" < dns/named.conf.local.tpl   > generado/dns/named.conf.local
    envsubst "$VARS" < dns/interna/db.directa.tpl > "generado/dns/interna/db.$DOMINIO"
    envsubst "$VARS" < dns/interna/db.inversa.tpl > generado/dns/interna/db.inversa
    envsubst "$VARS" < dns/aula/db.directa.tpl    > "generado/dns/aula/db.$DOMINIO"
    chmod -R a+rX generado/dns
    clave_tsig

    # Configuración del DNS secundario (vive en GNS3, no en este servidor)
    envsubst "$VARS" < dns/secundario/named.conf.local.tpl > generado/dns-secundario/named.conf.local
    echo "    Config del secundario generada en generado/dns-secundario/named.conf.local (ver dns/README.md)"

    # --- Validar ANTES de tocar el contenedor: si hay un error, el DNS que ya funciona sigue vivo
    docker image inspect "$IMAGEN_BIND" &>/dev/null || docker pull -q "$IMAGEN_BIND" >/dev/null
    rc=0
    docker run --rm -v "$PWD/generado/dns:/etc/bind:ro" --entrypoint named-checkconf \
        "$IMAGEN_BIND" -z /etc/bind/named.conf || rc=$?
    if [ "$rc" -ge 125 ]; then
        # 125-127: Docker no pudo ejecutar el comando; no es un error de la config
        echo "AVISO: no he podido validar la configuración con named-checkconf; sigo adelante."
    elif [ "$rc" -ne 0 ]; then
        echo "ERROR: la configuración de BIND no es válida (arriba está el motivo). No toco el DNS actual."
        exit 1
    fi

    docker rm -f mi-bind9 2>/dev/null || true          # restos de intentos anteriores
    if command -v docker compose &>/dev/null && docker compose version &>/dev/null; then
        docker compose up -d --force-recreate dns
    else
        docker-compose up -d --force-recreate dns
    fi
}


# ---------------------------------------------------------------- GNS3
# Servidor GNS3 en este servidor (puerto 3080, lo que muestra gns3.$DOMINIO por Apache),
# imagen del DNS secundario y proyecto de la red interna importado y arrancado.
GNS3_VERSION_PIP="2.2.61"        # solo se usa si el PPA no sirve
GNS3_PUERTO=3080
GNS3_LOG=/var/log/instalar-gns3.log
GNS3_API="http://127.0.0.1:$GNS3_PUERTO/v2"
GNS3_PROYECTO="gns3/red_huesca.gns3project"

gns3_usuario() {
    id gns3 &>/dev/null || useradd --system --create-home --home-dir /opt/gns3 --shell /usr/sbin/nologin gns3
    mkdir -p /opt/gns3
    for g in docker kvm ubridge; do                      # solo los grupos que existan
        getent group "$g" >/dev/null && usermod -aG "$g" gns3
    done
    return 0
}

gns3_paquetes_ppa() {
    asegurar_dns
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:gns3/ppa
    apt-get update
    apt-get install -y gns3-server ubridge dynamips vpcs
}

gns3_paquetes_pip() {
    asegurar_dns
    # gns3-server por pip; ubridge y vpcs desde el código oficial (el vpcs de Ubuntu es demasiado viejo)
    apt-get install -y python3-venv python3-pip build-essential libpcap-dev git dynamips
    python3 -m venv /opt/gns3/venv
    /opt/gns3/venv/bin/pip install --upgrade pip
    /opt/gns3/venv/bin/pip install "gns3-server==$GNS3_VERSION_PIP"
    ln -sf /opt/gns3/venv/bin/gns3server /usr/local/bin/gns3server

    local tmp; tmp=$(mktemp -d)
    git clone --connect-timeout 10 --depth 1 --branch v0.9.19 https://github.com/GNS3/ubridge.git "$tmp/ubridge"
    make -C "$tmp/ubridge"
    install -m 755 "$tmp/ubridge/ubridge" /usr/local/bin/ubridge
    git clone --connect-timeout 10 --depth 1 --branch v0.8.5 https://github.com/GNS3/vpcs.git "$tmp/vpcs"
    (cd "$tmp/vpcs/src" && ./mk.sh)
    install -m 755 "$tmp/vpcs/src/vpcs" /usr/local/bin/vpcs
    rm -rf "$tmp"
}

gns3_instalar_servidor() {
    export DEBIAN_FRONTEND=noninteractive
    asegurar_dns
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

    # Ahora que los paquetes ya han creado el grupo "ubridge", metemos al usuario gns3 en él
    gns3_usuario
    gns3_permisos_ubridge
    chown -R gns3:gns3 /opt/gns3
}

gns3_permisos_ubridge() {
    # ubridge conecta Cloud1 con br-virtual (net_admin y net_raw) y mete la interfaz de los
    # nodos Docker en el namespace del contenedor (además sys_admin y sys_ptrace).
    local U; U="$(command -v ubridge)" || return 0
    U="$(readlink -f "$U")"
    if [ -u "$U" ]; then
        # ubridge del PPA: setuid root. Con capabilities además, el kernel ignora el setuid: se quitan.
        setcap -r "$U" 2>/dev/null || true
        getent group ubridge >/dev/null && chgrp ubridge "$U" && chmod 4750 "$U"
    else
        # ubridge compilado a mano: capacidades completas
        setcap cap_net_admin,cap_net_raw,cap_sys_admin,cap_sys_ptrace=ep "$U" 2>/dev/null || true
        chmod 755 "$U"
    fi
    return 0
}

gns3_imagen_dns_secundario() {
    # El nodo Docker del proyecto usa la imagen dns-secundario:1.0, construida con las zonas
    # que ha generado la fase dns.
    [ -f generado/dns-secundario/named.conf.local ] || dns
    local ctx=generado/dns-secundario/imagen
    rm -rf "$ctx"; mkdir -p "$ctx"
    cp gns3/dns-secundario/Dockerfile gns3/dns-secundario/named.conf.options "$ctx/"
    cp generado/dns-secundario/named.conf.local "$ctx/"
    clave_tsig
    cp generado/tsig.conf "$ctx/"
    export IP_DNS_SECUNDARIO IP_INTERNA_SOLO PREFIJO_INTERNA
    envsubst '${IP_DNS_SECUNDARIO} ${PREFIJO_INTERNA} ${IP_INTERNA_SOLO}' \
        < gns3/dns-secundario/entrypoint.sh.tpl > "$ctx/entrypoint.sh"
    docker build -q -t dns-secundario:1.0 "$ctx" >/dev/null
    echo "    Imagen dns-secundario:1.0 lista"
}

gns3_servicio() {
    # Unidad systemd propia: escucha en 0.0.0.0:3080, arranca después de Docker y sobrevive a reinicios.
    local bin espera=""; bin=$(command -v gns3server)
    # Tras un reinicio, GNS3 espera (máx. 30 s) a que exista el puente antes de arrancar los nodos
    if [ -f /etc/netplan/60-sede.yaml ]; then
        cat > /usr/local/sbin/gns3-espera-puente.sh <<'ESPERA'
#!/bin/bash
for _ in $(seq 1 30); do ip link show "$1" >/dev/null 2>&1 && exit 0; sleep 1; done
exit 0
ESPERA
        chmod 755 /usr/local/sbin/gns3-espera-puente.sh
        espera="ExecStartPre=-/usr/local/sbin/gns3-espera-puente.sh ${BRIDGE_INTERNA:-br-virtual}"
    fi

    local unidad; unidad=$(cat <<UNIT
[Unit]
Description=GNS3 server (sede ${SEDE:-Huesca})
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
)
    # Solo se toca systemd (y se reinicia GNS3) si la unidad ha cambiado o el servicio no responde
    local f=/etc/systemd/system/gns3server.service
    if [ "$unidad" != "$(cat "$f" 2>/dev/null)" ]; then
        printf '%s\n' "$unidad" > "$f"
        systemctl daemon-reload
        systemctl enable gns3server >/dev/null 2>&1
        systemctl restart gns3server
    elif ! curl -fs "$GNS3_API/version" >/dev/null 2>&1; then
        systemctl enable gns3server >/dev/null 2>&1
        systemctl restart gns3server
    fi

    # Apache (en un contenedor) llega al servidor por la red de Docker: se lo permitimos a UFW.
    ufw allow from 172.16.0.0/12 to any port "$GNS3_PUERTO" proto tcp >/dev/null 2>&1 || true

    for _ in $(seq 1 60); do
        curl -fs "$GNS3_API/version" >/dev/null 2>&1 && return 0
        sleep 1
    done
    echo "ERROR: gns3server no responde en el puerto $GNS3_PUERTO"; journalctl -u gns3server -n 20 --no-pager || true
    exit 1
}

gns3_id_proyecto() {
    python3 -c 'import sys,json,zipfile; print(json.loads(zipfile.ZipFile(sys.argv[1]).read("project.gns3"))["project_id"])' "$GNS3_PROYECTO"
}

gns3_nodos_parados() {      # imprime cuántos nodos del proyecto NO están arrancados
    curl -s "$GNS3_API/projects/$1/nodes" 2>/dev/null | python3 -c '
import sys, json
try: print(sum(1 for n in json.load(sys.stdin) if n.get("status") != "started"))
except Exception: print(99)'
}

gns3_importar() {           # $1 = id del proyecto
    curl -fsS -o /dev/null -X POST -H 'Content-Type: application/octet-stream' \
        --data-binary @"$GNS3_PROYECTO" "$GNS3_API/projects/$1/import?name=red%20huesca"
    # Que se abra y arranque solo cada vez que arranque el servidor GNS3 (también tras un reinicio)
    curl -fsS -o /dev/null -X PUT -H 'Content-Type: application/json' \
        -d '{"auto_open":true,"auto_start":true}' "$GNS3_API/projects/$1"
}

gns3_proyecto() {
    local id code parados=99
    id=$(gns3_id_proyecto)
    code=$(curl -s -o /dev/null -w '%{http_code}' "$GNS3_API/projects/$id")
    if [ "$code" = 404 ]; then
        echo "    Importando el proyecto de la red interna"
        gns3_importar "$id" || { echo "ERROR: no he podido importar $GNS3_PROYECTO"; exit 1; }
    fi

    for intento in 1 2 3; do
        curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{}' "$GNS3_API/projects/$id/open"
        curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{}' "$GNS3_API/projects/$id/nodes/start"
        # En vez de esperar 3 s a ciegas, se mira cada segundo (hasta 15) si ya están todos arrancados
        for _ in $(seq 1 15); do
            parados=$(gns3_nodos_parados "$id")
            [ "$parados" = 0 ] && break
            sleep 1
        done
        [ "$parados" = 0 ] && break
        if [ "$intento" = 2 ]; then       # último recurso: proyecto limpio (p. ej. si borraron su contenedor)
            echo "    Los nodos no arrancan; vuelvo a importar el proyecto desde cero"
            curl -s -o /dev/null -X DELETE "$GNS3_API/projects/$id"
            gns3_importar "$id" || true
        fi
    done

    if [ "$parados" = 0 ]; then echo "    Proyecto 'red huesca' abierto y con todos los nodos arrancados"
    else
        echo "AVISO: $parados nodo(s) de GNS3 sin arrancar (¿existe ${BRIDGE_INTERNA:-br-virtual}? ¿está la imagen dns-secundario:1.0?)"
        echo "    ubridge: $(ls -l "$(command -v ubridge)" 2>/dev/null | awk '{print $1, $3, $4}')  caps: $(getcap "$(command -v ubridge)" 2>/dev/null)"
        echo "    usuario gns3: $(id gns3 2>/dev/null)"
        journalctl -u gns3server -n 15 --no-pager 2>/dev/null || true
    fi
}

gns3() {
    titulo "GNS3 (servidor y proyecto de la red interna)"
    asegurar_dns
    gns3_instalar_servidor
    gns3_imagen_dns_secundario
    gns3_servicio
    gns3_proyecto
}


# ---------------------------------------------------------------- Forgejo
# Restaura en este Forgejo los datos de OTRO Forgejo y deja el SSH (puerto 2222) funcionando.
# Solo restaura si NO hay datos todavía: nunca pisa un Forgejo que ya funciona.
#
#   restauracion/forgejo-dump.zip   copia hecha con `forgejo dump` en el Forgejo de origen
#   restauracion/forgejo-ssh/       (opcional) carpeta /data/ssh del origen: conserva la huella del servidor
# La carpeta restauracion/ NO va a Git (lleva contraseñas, claves y todos los repositorios).
FORGEJO_DATOS=forgejo-docker
FORGEJO_DUMP=restauracion/forgejo-dump.zip
FORGEJO_SSH_ORIGEN=restauracion/forgejo-ssh
FORGEJO_UID=1000                 # el mismo USER_UID/USER_GID de compose.yaml

forgejo_entorno() {              # variables que lee compose.yaml en el servicio git
    export DOMINIO
    # El bloqueo del instalador solo se activa si la base de datos ya existe en disco
    if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then FORGEJO_INSTALL_LOCK=true
    else FORGEJO_INSTALL_LOCK=false; fi
    export FORGEJO_INSTALL_LOCK
}

forgejo_restaurar() {
    [ -f "$FORGEJO_DUMP" ] || return 0

    # sqlite3 y unzip ANTES de contar usuarios. Antes se instalaban después: sin sqlite3 el recuento
    # daba 0 y se restauraba encima de un Forgejo que ya tenía datos.
    command -v sqlite3 &>/dev/null && command -v unzip &>/dev/null \
        || { asegurar_dns; apt-get install -y unzip sqlite3 >/dev/null; }

    local num_usuarios=0
    if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then
        num_usuarios=$(sqlite3 "$FORGEJO_DATOS/gitea/gitea.db" "SELECT COUNT(*) FROM user;" 2>/dev/null || echo 0)
    fi

    if [ "$num_usuarios" -ne 0 ]; then
        echo "    Forgejo ya cuenta con usuarios en la BBDD: omitiendo restauración."
        return 0
    fi

    echo "    Base de datos vacía o no existente. Restaurando desde $FORGEJO_DUMP..."
    docker rm -f forgejo 2>/dev/null || true

    local tmp; tmp=$(mktemp -d)
    unzip -q "$FORGEJO_DUMP" -d "$tmp"

    mkdir -p "$FORGEJO_DATOS/gitea/conf" "$FORGEJO_DATOS/git/repositories"
    if [ -f "$tmp/app.ini" ]; then cp "$tmp/app.ini" "$FORGEJO_DATOS/gitea/conf/app.ini"; fi
    if [ -d "$tmp/data" ];  then cp -a "$tmp/data/."  "$FORGEJO_DATOS/gitea/"; fi
    if [ -d "$tmp/repos" ]; then cp -a "$tmp/repos/." "$FORGEJO_DATOS/git/repositories/"; fi

    local sql; sql=$(ls "$tmp"/*-db.sql 2>/dev/null | head -1 || true)
    if [ -n "$sql" ]; then
        rm -f "$FORGEJO_DATOS/gitea/gitea.db"
        sqlite3 "$FORGEJO_DATOS/gitea/gitea.db" < "$sql"
    fi
    rm -rf "$tmp"

    # Forzar INSTALL_LOCK = true en app.ini
    local ini="$FORGEJO_DATOS/gitea/conf/app.ini"
    if [ -f "$ini" ]; then
        if grep -q "INSTALL_LOCK" "$ini"; then sed -i 's/INSTALL_LOCK.*/INSTALL_LOCK = true/' "$ini"
        else printf '\n[security]\nINSTALL_LOCK = true\n' >> "$ini"; fi
    fi

    chown -R "$FORGEJO_UID:$FORGEJO_UID" "$FORGEJO_DATOS"
    echo "    Datos de Forgejo restaurados correctamente."
}

forgejo_ssh_preparar() {         # claves del servidor y permisos que exige sshd dentro del contenedor
    mkdir -p "$FORGEJO_DATOS/ssh" "$FORGEJO_DATOS/git/.ssh"
    # Misma huella que el Forgejo de origen. Si no hay claves, el contenedor genera unas nuevas.
    if [ -d "$FORGEJO_SSH_ORIGEN" ] && ! ls "$FORGEJO_DATOS"/ssh/ssh_host_*_key &>/dev/null; then
        cp -a "$FORGEJO_SSH_ORIGEN"/ssh_host_* "$FORGEJO_DATOS/ssh/"
    fi
    chown -R "$FORGEJO_UID:$FORGEJO_UID" "$FORGEJO_DATOS"
    chmod 755 "$FORGEJO_DATOS/git"                      # sshd rechaza un home con permisos de escritura para otros
    chmod 700 "$FORGEJO_DATOS/git/.ssh"
    [ ! -f "$FORGEJO_DATOS/git/.ssh/authorized_keys" ] || chmod 600 "$FORGEJO_DATOS/git/.ssh/authorized_keys"
    chmod 600 "$FORGEJO_DATOS"/ssh/ssh_host_*_key 2>/dev/null || true
    chmod 644 "$FORGEJO_DATOS"/ssh/ssh_host_*_key.pub 2>/dev/null || true
}

forgejo_ssh_activar() {          # con el contenedor en marcha: authorized_keys y hooks salen de la base de datos
    if command -v docker compose &>/dev/null && docker compose version &>/dev/null; then
        docker compose up -d git
    else
        docker-compose up -d git
    fi
    for _ in $(seq 1 60); do
        curl -fs http://127.0.0.1:3000/api/healthz >/dev/null 2>&1 && break
        sleep 1
    done
    docker exec -u "$FORGEJO_UID" forgejo forgejo admin regenerate hooks \
        || echo "AVISO: no he podido regenerar los hooks de Forgejo"
    docker exec -u "$FORGEJO_UID" forgejo forgejo admin regenerate keys \
        || echo "AVISO: no he podido regenerar authorized_keys: el SSH de Forgejo no funcionará"
}

forgejo() {
    titulo "Forgejo (datos de otro Forgejo y SSH)"
    forgejo_restaurar          # 1. restaura el .zip (crea gitea.db)
    forgejo_ssh_preparar       # 2. permisos
    forgejo_entorno            # 3. FORGEJO_INSTALL_LOCK (ahora ya ve gitea.db)
    if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then forgejo_ssh_activar; fi
}


# ---------------------------------------------------------------- Web, BD, LDAP

web() {
    titulo "Servidor Web, Base de Datos, Forgejo y OpenLDAP/LAM"

    mkdir -p secretos
    [ -d secretos/intranet.htpasswd ] && rm -rf secretos/intranet.htpasswd   # Docker lo crea como carpeta si no existe
    printf '%s:%s\n' "${INTRANET_USUARIO:-admin}" "$(openssl passwd -apr1 "${INTRANET_CLAVE:-secret}")" > secretos/intranet.htpasswd
    chmod 755 secretos
    chmod 644 secretos/intranet.htpasswd

    # LDIF de estructura desde la plantilla, si existe
    if [ -f ldif/01_estructura.ldif.tpl ]; then
        echo "    Generando ldif/01_estructura.ldif desde plantilla..."
        envsubst < ldif/01_estructura.ldif.tpl > ldif/01_estructura.ldif
    fi

    forgejo_entorno
    esperar_imagenes                                  # las descargas en segundo plano ya deberían haber acabado

    if command -v docker compose &>/dev/null && docker compose version &>/dev/null; then
        docker compose down ldap lam -v 2>/dev/null || true
    else
        docker-compose down ldap lam -v 2>/dev/null || true
    fi
    docker rm -f mi-apache mi-postgres forgejo 2>/dev/null || true

    if command -v docker compose &>/dev/null && docker compose version &>/dev/null; then
        docker compose up -d --build --force-recreate web ldap lam panel
    else
        docker-compose up -d --build --force-recreate web ldap lam panel
    fi
}


# ---------------------------------------------------------------- Verificación

esperar_contenedores() {     # espera hasta 30 s a que estén todos en marcha (antes: sleep 5 fijo)
    local c ok
    for _ in $(seq 1 30); do
        ok=1
        for c in "$@"; do
            [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] || ok=0
        done
        [ "$ok" = 1 ] && return 0
        sleep 1
    done
    return 0
}

verificar() {
    titulo "Verificando la sede"
    local r c estado huella pid

    # Red
    if [ -n "${BRIDGE_INTERNA:-}" ] && ip link show "$BRIDGE_INTERNA" &>/dev/null; then
        ip -br addr show "$BRIDGE_INTERNA" | grep -q "$IP_INTERNA_SOLO" && bien "puente" || mal "puente"
        [ "$(sysctl -n net.ipv4.ip_forward)" = 1 ] && bien "forwarding" || mal "forwarding"
        iptables -t nat -C POSTROUTING -s "$RED_INTERNA" -o "$INTERFAZ_AULA" -j MASQUERADE 2>/dev/null \
            && bien "NAT" || mal "NAT"
    else
        echo "AVISO: no existe ${BRIDGE_INTERNA:-bridge} (fase red no aplicada): salto las pruebas de red."
    fi

    # Contenedores
    esperar_contenedores mi-bind9 mi-apache mi-postgres forgejo panel
    sleep 2        # margen para detectar reinicios en bucle
    for c in mi-bind9 mi-apache mi-postgres forgejo panel; do
        estado=$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' "$c" 2>/dev/null || echo "no-existe")
        if [ "$estado" = "true 0" ]; then bien "contenedor $c"
        else mal "contenedor $c ($estado)"; docker logs --tail 15 "$c" 2>&1 || true; fi
    done

    # Base de datos: el usuario de la web puede leer pero NO borrar
    r=$(docker exec mi-postgres psql -U "${DB_USER:-web}" -d "${DB_NAME:-huesca}" -c "DELETE FROM inventario WHERE false" 2>&1 || true)
    if echo "$r" | grep -q "permission denied"; then bien "usuario ${DB_USER:-web} sin permiso de borrado"
    else mal "usuario ${DB_USER:-web}: no tiene el permiso esperado (¿existe el rol? $r)"; fi

    # SSH de Forgejo (2222): debe enseñar su clave y, si hay claves de origen, ser la misma
    if command -v ssh-keyscan &>/dev/null; then
        huella=$(ssh-keyscan -T 3 -p 2222 127.0.0.1 2>/dev/null | grep -m1 ssh-ed25519 | awk '{print $3}' || true)
        if [ -z "$huella" ]; then mal "SSH de Forgejo: no responde en el 2222"
        elif [ -f "$FORGEJO_SSH_ORIGEN/ssh_host_ed25519_key.pub" ] \
             && [ "$huella" != "$(awk '{print $2}' "$FORGEJO_SSH_ORIGEN/ssh_host_ed25519_key.pub")" ]; then
            mal "SSH de Forgejo: la clave del servidor no es la del Forgejo de origen"
        else bien "SSH de Forgejo (2222)"; fi
    fi

    # DNS
    if command -v dig &>/dev/null; then
        r=$(dig +short +time=2 +tries=1 @127.0.0.1 "www.${DOMINIO:-huesca.local}" || true)
        [ -n "$r" ] && bien "DNS www -> $r" || mal "DNS: www.${DOMINIO:-huesca.local} no resuelve"

        # Vista del aula: preguntamos desde la IP del aula del propio servidor (BIND nos ve como "aula")
        if [ -n "${INTERFAZ_AULA:-}" ] && ip -4 -br addr show "$INTERFAZ_AULA" 2>/dev/null | grep -q "$IP_AULA_SOLO"; then
            r=$(dig +short +time=2 +tries=1 -b "$IP_AULA_SOLO" "@$IP_AULA_SOLO" "www.${DOMINIO:-huesca.local}" A | tail -1 || true)
            [ "$r" = "$IP_AULA_SOLO" ] && bien "DNS vista aula www -> $r" \
                || mal "DNS vista aula: esperaba $IP_AULA_SOLO y salió '$r'"
        fi
    fi

    # GNS3: servidor, proxy de Apache (gns3.$DOMINIO) y nodos del proyecto
    if command -v gns3server &>/dev/null; then
        r=$(curl -fs "$GNS3_API/version" 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || true)
        [ -n "$r" ] && bien "servidor GNS3 $r (puerto $GNS3_PUERTO)" || mal "servidor GNS3: no responde en el puerto $GNS3_PUERTO"
        r=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: gns3.${DOMINIO:-huesca.local}" http://localhost/v2/version || true)
        [ "$r" = 200 ] && bien "gns3.${DOMINIO:-huesca.local} (Apache -> GNS3)" || mal "gns3.${DOMINIO:-huesca.local}: recibido $r"
        if [ -n "${BRIDGE_INTERNA:-}" ] && ip link show "$BRIDGE_INTERNA" &>/dev/null; then
            pid=$(gns3_id_proyecto)
            r=$(gns3_nodos_parados "$pid")
            [ "$r" = 0 ] && bien "proyecto GNS3: todos los nodos arrancados" || mal "proyecto GNS3: $r nodo(s) sin arrancar"
        fi
    else
        echo "AVISO: GNS3 no está instalado (ejecuta: sudo ./instalar.sh gns3)"
    fi

    if [ -f web/probar.sh ]; then
        bash web/probar.sh || FALLOS=1
    fi

    titulo "Estado de los contenedores:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    if [ "$FALLOS" -eq 0 ]; then echo "=== TODO BIEN TODO CORRECTO Y YO QUE ME ALEGRO ==="
    else echo "=== HAY COMPROBACIONES FALLIDAS ==="; exit 1; fi
}


# ================================================================== QUÉ FASES SE EJECUTAN

case "${1:-}" in
    "")        comprobar; precargar_imagenes; red_automatica; sistema; dns; gns3; forgejo; web; verificar ;;
    comprobar) comprobar ;;
    red)       comprobar; red ;;
    sistema)   comprobar; sistema ;;
    dns)       comprobar; dns ;;
    gns3)      comprobar; gns3 ;;
    forgejo)   comprobar; forgejo ;;
    web)       comprobar; web ;;
    verificar) comprobar; verificar ;;
    *)
        echo "ERROR: no existe la fase '$1'"
        echo "Fases: comprobar red sistema dns gns3 forgejo web verificar"
        exit 1 ;;
esac

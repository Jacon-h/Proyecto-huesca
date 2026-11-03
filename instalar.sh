#!/bin/bash
#
# instalar.sh · Despliegue de la sede Huesca
#
#   sudo ./instalar.sh             todas las fases, una detrás de otra
#   sudo ./instalar.sh <fase>      solo una fase (comprobar va siempre delante)
#
# Se puede repetir sin romper nada: cada fase mira primero qué hay hecho.

set -eo pipefail
cd "$(dirname "$0")"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con sudo:  sudo ./instalar.sh"; exit 1; }

FALLOS=0

# ---------------------------------------------------------------- Docker
if ! command -v docker &>/dev/null; then
    echo "== Docker no está instalado. Instalándolo... =="
    apt-get update && apt-get install -y docker.io docker-compose-v2
    usermod -aG docker "${SUDO_USER:-root}" || true
fi
command -v openssl &>/dev/null || apt-get install -y openssl

source sede.env          # SEDE, DOMINIO, IP_AULA, BRIDGE_INTERNA…


# ================================================================== FASES

comprobar() {
    echo "== Comprobando que se puede instalar"
    if [ ! -f .env ]; then
        cp .env.example .env
        echo "ERROR: no había .env; lo he creado desde .env.example. Rellénalo (nano .env) y vuelve a ejecutar."
        exit 1
    fi
    set -a; source .env; set +a
    for v in DB_NAME DB_PASSWORD INTRANET_USUARIO INTRANET_CLAVE LDAP_ADMIN_PASSWORD LDAP_CONFIG_PASSWORD LAM_PASSWORD; do
        [ -n "${!v:-}" ] || { echo "ERROR: falta $v en .env"; exit 1; }
    done
    docker compose version >/dev/null || { echo "ERROR: falta el plugin docker compose"; exit 1; }
    echo "    Todo listo para instalar la sede $SEDE"
}


red() {
    echo "== Red"
    apt-get install -y iptables gettext-base >/dev/null

    export INTERFAZ_AULA IP_AULA PUERTA_AULA RESOLUTOR_CENTRO IP_INTERNA BRIDGE_INTERNA
    envsubst < red/60-sede.yaml.tpl > /tmp/60-sede.yaml
    if ! cmp -s /tmp/60-sede.yaml /etc/netplan/60-sede.yaml; then
        mkdir -p /etc/netplan/original
        for f in /etc/netplan/*.yaml; do
            [ "$f" = /etc/netplan/60-sede.yaml ] || [ ! -e "$f" ] || mv "$f" /etc/netplan/original/
        done
        install -m 600 /tmp/60-sede.yaml /etc/netplan/60-sede.yaml     # el fichero generado, no la plantilla
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

red_automatica() {
    if ip -4 -br addr show "$INTERFAZ_AULA" 2>/dev/null | grep -q "${IP_AULA%/*}"; then
        red
    else
        echo "AVISO: $INTERFAZ_AULA no existe o no tiene ${IP_AULA%/*}: salto la fase red."
        echo "       Si es el servidor real, ejecuta:  sudo ./instalar.sh red"
    fi
}


sistema() {
    echo "== Sistema, usuarios y cortafuegos"
    apt-get install -y openssh-server >/dev/null
    mkdir -p /etc/ssh/sshd_config.d
    bash sistema/config_red_ufw.sh
    bash sistema/usuarios/crear_usuario.sh

    if [ -f sistema/usuarios/sshd_seguridad.conf ] && ls /home/*/.ssh/authorized_keys &>/dev/null; then
        install -m 644 sistema/usuarios/sshd_seguridad.conf /etc/ssh/sshd_config.d/seguridad.conf
        if sshd -t; then systemctl restart ssh
        else rm -f /etc/ssh/sshd_config.d/seguridad.conf; echo "AVISO: sshd_config inválido, revertido"; fi
    else
        echo "AVISO: no hay claves SSH instaladas; no aplico el hardening de sshd."
    fi
}


liberar_puerto_53() {
    if ss -lntup 2>/dev/null | grep -qE '127\.0\.0\.53(%lo)?:53 '; then
        echo "    Liberando el puerto 53 (systemd-resolved)"
        mkdir -p /etc/systemd/resolved.conf.d
        printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/sede-nostub.conf
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        systemctl restart systemd-resolved
    fi
}

dns() {
    echo "== Servidor DNS (BIND9)"
    liberar_puerto_53

    IP_INTERNA_SOLO="${IP_INTERNA%/*}"
    IP_AULA_SOLO="${IP_AULA%/*}"
    IFS=. read -r o1 o2 o3 _ <<< "${RED_INTERNA%/*}"
    ZONA_INVERSA="${o2}.${o1}.in-addr.arpa"
    PTR_SERVIDOR="${IP_INTERNA_SOLO##*.}.${o3}"
    ACL_AULA=""; for r in $REDES_AULA; do ACL_AULA+="$r; "; done

    mkdir -p generado/dns/interna generado/dns/aula generado/dns-secundario
    SERIAL=$(date +%Y%m%d%H)
    if [ -f generado/serial ] && [ "$SERIAL" -le "$(cat generado/serial)" ]; then SERIAL=$(( $(cat generado/serial) + 1 )); fi
    echo "$SERIAL" > generado/serial

    export DOMINIO RED_INTERNA IP_INTERNA_SOLO IP_AULA_SOLO IP_DNS_SECUNDARIO ZONA_INVERSA PTR_SERVIDOR ACL_AULA SERIAL
    VARS='${DOMINIO} ${RED_INTERNA} ${IP_INTERNA_SOLO} ${IP_AULA_SOLO} ${IP_DNS_SECUNDARIO} ${ZONA_INVERSA} ${PTR_SERVIDOR} ${ACL_AULA} ${SERIAL}'

    cp dns/named.conf dns/named.conf.options generado/dns/
    envsubst "$VARS" < dns/named.conf.local.tpl     > generado/dns/named.conf.local
    envsubst "$VARS" < dns/interna/db.directa.tpl   > "generado/dns/interna/db.$DOMINIO"
    envsubst "$VARS" < dns/interna/db.inversa.tpl   > generado/dns/interna/db.inversa
    envsubst "$VARS" < dns/aula/db.directa.tpl      > "generado/dns/aula/db.$DOMINIO"
    chmod -R a+rX generado/dns

    envsubst "$VARS" < dns/secundario/named.conf.local.tpl > generado/dns-secundario/named.conf.local
    echo "    Config del secundario generada en generado/dns-secundario/named.conf.local (ver dns/README.md)"

    docker pull -q internetsystemsconsortium/bind9:9.18 >/dev/null
    rc=0
    docker run --rm -v "$PWD/generado/dns:/etc/bind:ro" --entrypoint named-checkconf \
        internetsystemsconsortium/bind9:9.18 -z /etc/bind/named.conf || rc=$?
    if [ "$rc" -ge 125 ]; then
        echo "AVISO: no he podido validar la configuración con named-checkconf; sigo adelante."
    elif [ "$rc" -ne 0 ]; then
        echo "ERROR: la configuración de BIND no es válida (arriba está el motivo). No toco el DNS actual."
        exit 1
    fi

    docker rm -f mi-bind9 2>/dev/null || true
    docker compose up -d --force-recreate dns
}


# ---------------------------------------------------------------- GNS3
GNS3_VERSION_PIP="2.2.61"
GNS3_PUERTO=3080
GNS3_LOG=/var/log/instalar-gns3.log
GNS3_API="http://127.0.0.1:$GNS3_PUERTO/v2"
GNS3_PROYECTO="gns3/red_huesca.gns3project"

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
    [ -f generado/dns-secundario/named.conf.local ] || dns
    local ctx=generado/dns-secundario/imagen
    rm -rf "$ctx"; mkdir -p "$ctx"
    cp gns3/dns-secundario/Dockerfile gns3/dns-secundario/named.conf.options "$ctx/"
    cp generado/dns-secundario/named.conf.local "$ctx/"
    export IP_DNS_SECUNDARIO IP_INTERNA_SOLO="${IP_INTERNA%/*}" PREFIJO_INTERNA="${IP_INTERNA#*/}"
    envsubst '${IP_DNS_SECUNDARIO} ${PREFIJO_INTERNA} ${IP_INTERNA_SOLO}' \
        < gns3/dns-secundario/entrypoint.sh.tpl > "$ctx/entrypoint.sh"
    docker build -q -t dns-secundario:1.0 "$ctx" >/dev/null
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


# ---------------------------------------------------------------- Forgejo
FORGEJO_DATOS=forgejo-docker
FORGEJO_DUMP=restauracion/forgejo-dump.zip
FORGEJO_SSH_ORIGEN=restauracion/forgejo-ssh
FORGEJO_UID=1000

forgejo_entorno() {
    export DOMINIO
    if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then 
        FORGEJO_INSTALL_LOCK=true
    else 
        FORGEJO_INSTALL_LOCK=false
    fi
    export FORGEJO_INSTALL_LOCK
}

forgejo_restaurar() {
    if [ -f "$FORGEJO_DUMP" ]; then
        local num_usuarios=0
        if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then
            num_usuarios=$(sqlite3 "$FORGEJO_DATOS/gitea/gitea.db" "SELECT COUNT(*) FROM user;" 2>/dev/null || echo 0)
        fi

        if [ "$num_usuarios" -eq 0 ]; then
            echo "     Base de datos vacía o no existente. Restaurando desde $FORGEJO_DUMP..."
            apt-get install -y unzip sqlite3 >/dev/null 2>&1 || true
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

            if [ -f "$FORGEJO_DATOS/gitea/conf/app.ini" ]; then
                if grep -q "INSTALL_LOCK" "$FORGEJO_DATOS/gitea/conf/app.ini"; then
                    sed -i 's/INSTALL_LOCK.*/INSTALL_LOCK = true/' "$FORGEJO_DATOS/gitea/conf/app.ini"
                else
                    echo -e "\n[security]\nINSTALL_LOCK = true" >> "$FORGEJO_DATOS/gitea/conf/app.ini"
                fi
            fi

            chown -R "$FORGEJO_UID:$FORGEJO_UID" "$FORGEJO_DATOS"
            echo "     Datos de Forgejo restaurados correctamente."
        else
            echo "     Forgejo ya cuenta con usuarios en la BBDD: omitiendo restauración."
        fi
    fi
}

forgejo_ssh_preparar() {
    mkdir -p "$FORGEJO_DATOS/ssh" "$FORGEJO_DATOS/git/.ssh"
    if [ -d "$FORGEJO_SSH_ORIGEN" ] && ! ls "$FORGEJO_DATOS"/ssh/ssh_host_*_key &>/dev/null; then
        cp -a "$FORGEJO_SSH_ORIGEN"/ssh_host_* "$FORGEJO_DATOS/ssh/"
    fi
    chown -R "$FORGEJO_UID:$FORGEJO_UID" "$FORGEJO_DATOS"
    chmod 755 "$FORGEJO_DATOS/git"
    chmod 700 "$FORGEJO_DATOS/git/.ssh"
    [ ! -f "$FORGEJO_DATOS/git/.ssh/authorized_keys" ] || chmod 600 "$FORGEJO_DATOS/git/.ssh/authorized_keys"
    chmod 600 "$FORGEJO_DATOS"/ssh/ssh_host_*_key 2>/dev/null || true
    chmod 644 "$FORGEJO_DATOS"/ssh/ssh_host_*_key.pub 2>/dev/null || true
}

forgejo_ssh_activar() {
    docker compose up -d git
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
    echo "== Forgejo (datos de otro Forgejo y SSH)"
    forgejo_restaurar
    forgejo_ssh_preparar
    forgejo_entorno
    if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then forgejo_ssh_activar; fi
}

web() {
    echo "== Servidor Web, Base de Datos, Forgejo y OpenLDAP/LAM"

    mkdir -p secretos
    [ -d secretos/intranet.htpasswd ] && rm -rf secretos/intranet.htpasswd
    printf '%s:%s\n' "$INTRANET_USUARIO" "$(openssl passwd -apr1 "$INTRANET_CLAVE")" > secretos/intranet.htpasswd
    chmod 755 secretos
    chmod 644 secretos/intranet.htpasswd

    forgejo_entorno

    docker compose down ldap lam -v 2>/dev/null || true
    docker rm -f mi-apache mi-postgres forgejo 2>/dev/null || true

    docker compose up -d --build --force-recreate web ldap lam
}


# ---------------------------------------------------------------- SSSD Cliente
sssd_cliente() {
    echo "== Cliente SSSD para OpenLDAP"
    
    # 1. Instalar paquetes requeridos
    if ! command -v sssd &>/dev/null; then
        echo "    Instalando sssd, sssd-ldap, libpam-sss y herramientas..."
        apt-get update >/dev/null 2>&1
        apt-get install -y sssd sssd-ldap libpam-sss libnss-sss ldap-utils ca-certificates >/dev/null
    fi

    # 2. Copiar plantilla del repositorio o estructurar el fichero por defecto
    mkdir -p /etc/sssd
    if [ -f clientes/sssd.conf ]; then
        echo "    Copiando plantilla clientes/sssd.conf -> /etc/sssd/sssd.conf"
        cp clientes/sssd.conf /etc/sssd/sssd.conf
    else
        echo "    Generando /etc/sssd/sssd.conf..."
        cat <<'EOF' > /etc/sssd/sssd.conf
[sssd]
services = nss, pam
domains = huesca.empresa.lan

[domain/huesca.empresa.lan]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
access_provider = simple
simple_allow_groups = investigadores
ldap_uri = ldap://127.0.0.1:389
ldap_search_base = dc=huesca,dc=empresa,dc=lan
ldap_default_bind_dn = cn=svc-lectura,ou=servicios,dc=huesca,dc=empresa,dc=lan
ldap_default_authtok = CONTRASENA_SVC_LECTURA
ldap_tls_reqcert = allow
cache_credentials = true
EOF
    fi

    # 3. Aplicar permisos y reiniciar servicio
    chmod 600 /etc/sssd/sssd.conf
    pam-auth-update --enable mkhomedir 2>/dev/null || true
    systemctl restart sssd 2>/dev/null || true
    echo "    SSSD configurado y activo."
}


verificar() {
    echo "== Verificando la sede"

    if ip link show "$BRIDGE_INTERNA" &>/dev/null; then
        ip -br addr show "$BRIDGE_INTERNA" | grep -q "${IP_INTERNA%/*}" && echo "OK    puente" || { echo "FALLO puente"; FALLOS=1; }
        [ "$(sysctl -n net.ipv4.ip_forward)" = 1 ] && echo "OK    forwarding" || { echo "FALLO forwarding"; FALLOS=1; }
        iptables -t nat -C POSTROUTING -s "$RED_INTERNA" -o "$INTERFAZ_AULA" -j MASQUERADE 2>/dev/null \
            && echo "OK    NAT" || { echo "FALLO NAT"; FALLOS=1; }
    else
        echo "AVISO: no existe $BRIDGE_INTERNA (fase red no aplicada): salto las pruebas de red."
    fi

    sleep 5
    for c in mi-bind9 mi-apache mi-postgres forgejo ldap lam; do
        estado=$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' "$c" 2>/dev/null || echo "no-existe")
        if [ "$estado" = "true 0" ]; then echo "OK    contenedor $c"
        else echo "FALLO contenedor $c ($estado)"; docker logs --tail 15 "$c" 2>&1 || true; FALLOS=1; fi
    done

    if command -v ssh-keyscan &>/dev/null; then
        huella=$(ssh-keyscan -T 3 -p 2222 127.0.0.1 2>/dev/null | grep -m1 ssh-ed25519 | awk '{print $3}' || true)
        if [ -z "$huella" ]; then echo "FALLO SSH de Forgejo: no responde en el 2222"; FALLOS=1
        elif [ -f "$FORGEJO_SSH_ORIGEN/ssh_host_ed25519_key.pub" ] \
             && [ "$huella" != "$(awk '{print $2}' "$FORGEJO_SSH_ORIGEN/ssh_host_ed25519_key.pub")" ]; then
            echo "FALLO SSH de Forgejo: la clave del servidor no es la del Forgejo de origen"; FALLOS=1
        else echo "OK    SSH de Forgejo (2222)"; fi
    fi

    if command -v dig &>/dev/null; then
        r=$(dig +short +time=2 +tries=1 @127.0.0.1 www.huesca.empresa.lan || true)
        [ -n "$r" ] && echo "OK    DNS www -> $r" || { echo "FALLO DNS: www.huesca.empresa.lan no resuelve"; FALLOS=1; }
    fi

    if command -v dig &>/dev/null && ip -4 -br addr show "$INTERFAZ_AULA" 2>/dev/null | grep -q "${IP_AULA%/*}"; then
        r=$(dig +short +time=2 +tries=1 -b "${IP_AULA%/*}" "@${IP_AULA%/*}" www.$DOMINIO A | tail -1 || true)
        [ "$r" = "${IP_AULA%/*}" ] && echo "OK    DNS vista aula www -> $r" \
            || { echo "FALLO DNS vista aula: esperaba ${IP_AULA%/*} y salió '$r'"; FALLOS=1; }
    fi

    if command -v gns3server &>/dev/null; then
        v=$(curl -fs "$GNS3_API/version" 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || true)
        [ -n "$v" ] && echo "OK    servidor GNS3 $v (puerto $GNS3_PUERTO)" || { echo "FALLO servidor GNS3: no responde en el puerto $GNS3_PUERTO"; FALLOS=1; }
        c=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: gns3.$DOMINIO" http://localhost/v2/version || true)
        [ "$c" = 200 ] && echo "OK    gns3.$DOMINIO (Apache -> GNS3)" || { echo "FALLO gns3.$DOMINIO: recibido $c"; FALLOS=1; }
        if ip link show "$BRIDGE_INTERNA" &>/dev/null; then
            pid=$(python3 -c 'import sys,json,zipfile; print(json.loads(zipfile.ZipFile(sys.argv[1]).read("project.gns3"))["project_id"])' "$GNS3_PROYECTO")
            p=$(gns3_nodos_parados "$pid")
            [ "$p" = 0 ] && echo "OK    proyecto GNS3: todos los nodos arrancados" || { echo "FALLO proyecto GNS3: $p nodo(s) sin arrancar"; FALLOS=1; }
        fi
    else
        echo "AVISO: GNS3 no está instalado (ejecuta: sudo ./instalar.sh gns3)"
    fi

    bash web/probar.sh || FALLOS=1

    echo "== Estado de los contenedores:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    if [ "$FALLOS" -eq 0 ]; then echo "=== TODO BIEN TODO CORRECTO Y YO QUE ME ALEGRO ==="
    else echo "=== HAY COMPROBACIONES FALLIDAS ==="; exit 1; fi
}


# ================================================================== QUÉ FASES SE EJECUTAN

case "${1:-}" in
    "")        comprobar; red_automatica; sistema; dns; gns3; forgejo; web; sssd_cliente; verificar ;;
    comprobar) comprobar ;;
    red)       comprobar; red ;;
    sistema)   comprobar; sistema ;;
    dns)       comprobar; dns ;;
    gns3)      comprobar; gns3 ;;
    forgejo)   comprobar; forgejo ;;
    web)       comprobar; web ;;
    sssd)      comprobar; sssd_cliente ;;
    verificar) comprobar; verificar ;;
    *)
        echo "ERROR: no existe la fase '$1'"
        echo "Fases: comprobar red sistema dns gns3 forgejo web sssd verificar"
        exit 1 ;;
esac

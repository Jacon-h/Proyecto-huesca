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
        echo "AVISO: no había .env; lo creo desde .env.example (claves de ejemplo, cámbialas)."
        cp .env.example .env
    fi
    set -a; source .env; set +a
    for v in DB_NAME DB_PASSWORD INTRANET_USUARIO INTRANET_CLAVE; do
        [ -n "${!v:-}" ] || { echo "ERROR: falta $v en .env"; exit 1; }
    done
    docker compose version >/dev/null || { echo "ERROR: falta el plugin docker compose"; exit 1; }
    echo "   Todo listo para instalar la sede $SEDE"
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

# La fase red cambia la IP del servidor: solo se aplica sola si NO puede cortarte el acceso,
# es decir, si la interfaz del aula existe y ya tiene la IP que dice sede.env.
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

    # Solo se prohíbe la contraseña si alguien puede entrar con clave: si no, nos quedaríamos fuera.
    if [ -f sistema/usuarios/sshd_seguridad.conf ] && ls /home/*/.ssh/authorized_keys &>/dev/null; then
        install -m 644 sistema/usuarios/sshd_seguridad.conf /etc/ssh/sshd_config.d/seguridad.conf
        if sshd -t; then systemctl restart ssh
        else rm -f /etc/ssh/sshd_config.d/seguridad.conf; echo "AVISO: sshd_config inválido, revertido"; fi
    else
        echo "AVISO: no hay claves SSH instaladas; no aplico el hardening de sshd."
    fi
}


liberar_puerto_53() {
    # Ubuntu arranca systemd-resolved escuchando en 127.0.0.53:53 y BIND no puede usar el 53.
    if ss -lntup 2>/dev/null | grep -qE '127\.0\.0\.53(%lo)?:53 '; then
        echo "   Liberando el puerto 53 (systemd-resolved)"
        mkdir -p /etc/systemd/resolved.conf.d
        printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/sede-nostub.conf
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf   # si no, el servidor se queda sin resolver
        systemctl restart systemd-resolved
    fi
}

dns() {
    echo "== Servidor DNS (BIND9)"
    liberar_puerto_53
    chmod 644 dns/named.conf* dns/db.*
    docker rm -f mi-bind9 2>/dev/null || true          # restos de intentos anteriores
    docker compose up -d --force-recreate dns
}


web() {
    echo "== Servidor Web, Base de Datos y Forgejo"

    # .htpasswd generado desde .env. Se escribe SIEMPRE con la clave actual.
    mkdir -p secretos
    [ -d secretos/intranet.htpasswd ] && rm -rf secretos/intranet.htpasswd   # carpeta fantasma que crea Docker
    printf '%s:%s\n' "$INTRANET_USUARIO" "$(openssl passwd -apr1 "$INTRANET_CLAVE")" > secretos/intranet.htpasswd
    chmod 755 secretos
    chmod 644 secretos/intranet.htpasswd

    docker rm -f mi-apache mi-postgres forgejo 2>/dev/null || true
    docker compose up -d --build --force-recreate web      # arrastra db y git por depends_on
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
    for c in mi-bind9 mi-apache mi-postgres forgejo; do
        estado=$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' "$c" 2>/dev/null || echo "no-existe")
        if [ "$estado" = "true 0" ]; then echo "OK    contenedor $c"
        else echo "FALLO contenedor $c ($estado)"; docker logs --tail 15 "$c" 2>&1 || true; FALLOS=1; fi
    done

    if command -v dig &>/dev/null; then
        r=$(dig +short +time=2 +tries=1 @127.0.0.1 www.huesca.empresa.lan || true)
        [ -n "$r" ] && echo "OK    DNS www -> $r" || { echo "FALLO DNS: www.huesca.empresa.lan no resuelve"; FALLOS=1; }
    fi

    bash web/probar.sh || FALLOS=1

    echo "== Estado de los contenedores:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    if [ "$FALLOS" -eq 0 ]; then echo "=== TODO CORRECTO ==="
    else echo "=== HAY COMPROBACIONES FALLIDAS ==="; exit 1; fi
}


# ================================================================== QUÉ FASES SE EJECUTAN

case "${1:-}" in
    "")        comprobar; red_automatica; sistema; dns; web; verificar ;;
    comprobar) comprobar ;;
    red)       comprobar; red ;;
    sistema)   comprobar; sistema ;;
    dns)       comprobar; dns ;;
    web)       comprobar; web ;;
    verificar) comprobar; verificar ;;
    *)
        echo "ERROR: no existe la fase '$1'"
        echo "Fases: comprobar red sistema dns web verificar"
        exit 1 ;;
esac

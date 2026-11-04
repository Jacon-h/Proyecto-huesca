#!/bin/bash
#
# instalar.sh · Despliegue de la sede
#
#   sudo ./instalar.sh                      todas las fases, una detrás de otra
#   sudo ./instalar.sh <fase>               solo una fase
#   sudo ./instalar.sh reiniciar ldap --si  BORRA los datos de LDAP y los crea de nuevo
#   sudo ./instalar.sh reiniciar bd   --si  BORRA la base de datos y la crea de nuevo
#
# Fases (en este orden):
#   comprobar  mira que .env esté completo y que Docker funcione (va siempre delante)
#   red        netplan, reenvío de paquetes y NAT
#   sistema    usuarios, SSH y cortafuegos
#   dns        genera la configuración de BIND, la valida y lo arranca
#   gns3       servidor GNS3 y proyecto de la red interna      (scripts/gns3.sh)
#   forgejo    restaura los datos de Forgejo y activa su SSH   (scripts/forgejo.sh)
#   web        web, base de datos, Forgejo, OpenLDAP y LAM
#   sssd       este servidor autentica con OpenLDAP            (scripts/sssd.sh)
#   verificar  prueba que todo funciona
#
# ES SEGURO REPETIRLO: cada fase mira primero qué hay hecho y solo cambia lo que
# falta o ha cambiado. Nunca borra datos (base de datos, LDAP, Forgejo) por su
# cuenta: para eso existe "reiniciar", que exige escribir --si.

set -eo pipefail
cd "$(dirname "$0")"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con sudo:  sudo ./instalar.sh"; exit 1; }

# Solo puede haber un instalar.sh a la vez (dos a la vez se pisarían)
exec 9>/var/lock/instalar-sede.lock
flock -n 9 || { echo "ERROR: ya hay otro instalar.sh en marcha"; exit 1; }

# ---------------------------------------------------------------- Mensajes
FALLOS=0
titulo() { echo "== $*"; }
bien()   { echo "OK    $*"; }
mal()    { echo "FALLO $*"; FALLOS=1; }

# ---------------------------------------------------------------- Docker
if ! command -v docker &>/dev/null; then
    titulo "Docker no está instalado. Instalándolo..."
    apt-get update && apt-get install -y docker.io docker-compose-v2
    usermod -aG docker "${SUDO_USER:-root}" || true
fi
command -v openssl &>/dev/null || apt-get install -y openssl

source sede.env                  # SEDE, DOMINIO, IP_AULA, BRIDGE_INTERNA...
source scripts/gns3.sh
source scripts/forgejo.sh
source scripts/sssd.sh


# ================================================================== FASES

comprobar() {
    titulo "Comprobando que se puede instalar"
    if [ ! -f .env ]; then
        cp .env.example .env
        echo "ERROR: no había .env; lo he creado desde .env.example. Rellénalo (nano .env) y vuelve a ejecutar."
        exit 1
    fi
    set -a; source .env; set +a

    for v in DB_NAME DB_USER DB_PASSWORD POSTGRES_PASSWORD INTRANET_USUARIO INTRANET_CLAVE \
             LDAP_ADMIN_PASSWORD LDAP_CONFIG_PASSWORD LAM_PASSWORD; do
        [ -n "${!v:-}" ] || { echo "ERROR: falta $v en .env"; exit 1; }
    done
    [ "$DB_USER" != postgres ] || { echo "ERROR: DB_USER no puede ser 'postgres' (es el administrador)"; exit 1; }
    docker compose version >/dev/null || { echo "ERROR: falta el plugin docker compose"; exit 1; }
    echo "    Todo listo para instalar la sede $SEDE"
}


red() {
    titulo "Red"
    apt-get install -y iptables gettext-base >/dev/null

    # Netplan: solo se aplica si el fichero generado es distinto del que ya hay
    export INTERFAZ_AULA IP_AULA PUERTA_AULA RESOLUTOR_CENTRO IP_INTERNA BRIDGE_INTERNA
    envsubst < red/60-sede.yaml.tpl > /tmp/60-sede.yaml
    if ! cmp -s /tmp/60-sede.yaml /etc/netplan/60-sede.yaml; then
        mkdir -p /etc/netplan/original               # los ficheros anteriores se guardan, no se borran
        for f in /etc/netplan/*.yaml; do
            [ "$f" = /etc/netplan/60-sede.yaml ] || [ ! -e "$f" ] || mv "$f" /etc/netplan/original/
        done
        install -m 600 /tmp/60-sede.yaml /etc/netplan/60-sede.yaml
        netplan generate
        netplan apply
    fi

    # Reenvío de paquetes y NAT (servicio que se arranca solo en cada inicio)
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

red_automatica() {      # en el instalador completo: solo toca la red si estamos en el servidor real
    if ip -4 -br addr show "$INTERFAZ_AULA" 2>/dev/null | grep -q "${IP_AULA%/*}"; then
        red
    else
        echo "AVISO: $INTERFAZ_AULA no existe o no tiene ${IP_AULA%/*}: salto la fase red."
        echo "       Si es el servidor real, ejecuta:  sudo ./instalar.sh red"
    fi
}


sistema() {
    titulo "Sistema, usuarios y cortafuegos"
    apt-get install -y openssh-server >/dev/null
    mkdir -p /etc/ssh/sshd_config.d
    bash sistema/config_red_ufw.sh
    bash sistema/usuarios/crear_usuario.sh

    # El endurecimiento de SSH solo se aplica si alguien tiene clave (si no, nos quedaríamos fuera)
    if [ -f sistema/usuarios/sshd_seguridad.conf ] && ls /home/*/.ssh/authorized_keys &>/dev/null; then
        install -m 644 sistema/usuarios/sshd_seguridad.conf /etc/ssh/sshd_config.d/seguridad.conf
        if sshd -t; then systemctl restart ssh
        else rm -f /etc/ssh/sshd_config.d/seguridad.conf; echo "AVISO: sshd_config inválido, revertido"; fi
    else
        echo "AVISO: no hay claves SSH instaladas; no aplico el hardening de sshd."
    fi
}


# ---------------------------------------------------------------- DNS

liberar_puerto_53() {   # systemd-resolved ocupa el 53 en 127.0.0.53; BIND lo necesita
    if ss -lntup 2>/dev/null | grep -qE '127\.0\.0\.53(%lo)?:53 '; then
        echo "    Liberando el puerto 53 (systemd-resolved)"
        mkdir -p /etc/systemd/resolved.conf.d
        printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/sede-nostub.conf
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        systemctl restart systemd-resolved
    fi
}

clave_tsig() {          # clave que firma las transferencias de zona entre primario y secundario
    mkdir -p generado
    chmod 700 generado                      # la clave solo la lee root
    if [ ! -f generado/tsig.conf ]; then    # se crea UNA vez: si cambiara, el secundario dejaría de recibir zonas
        ( umask 077
          printf 'key "clave-transferencia" {\n    algorithm hmac-sha256;\n    secret "%s";\n};\n' \
                 "$(openssl rand -base64 32)" > generado/tsig.conf )
        echo "    Clave TSIG creada en generado/tsig.conf"
    fi
    install -m 644 generado/tsig.conf generado/dns/tsig.conf    # la que lee BIND dentro del contenedor
}

dns() {
    titulo "Servidor DNS (BIND9)"
    liberar_puerto_53

    # Valores que las plantillas necesitan y que se calculan a partir de sede.env
    IP_INTERNA_SOLO="${IP_INTERNA%/*}"
    IP_AULA_SOLO="${IP_AULA%/*}"
    IFS=. read -r o1 o2 o3 _ <<< "${RED_INTERNA%/*}"
    ZONA_INVERSA="${o2}.${o1}.in-addr.arpa"
    PTR_SERVIDOR="${IP_INTERNA_SOLO##*.}.${o3}"
    ACL_AULA=""; for r in $REDES_AULA; do ACL_AULA+="$r; "; done

    # El serial de las zonas sube en cada ejecución: así el secundario se entera de los cambios
    mkdir -p generado/dns/interna generado/dns/aula generado/dns-secundario
    SERIAL=$(date +%Y%m%d%H)
    if [ -f generado/serial ] && [ "$SERIAL" -le "$(cat generado/serial)" ]; then SERIAL=$(( $(cat generado/serial) + 1 )); fi
    echo "$SERIAL" > generado/serial

    # Plantillas (*.tpl) -> ficheros definitivos en generado/
    export DOMINIO RED_INTERNA IP_INTERNA_SOLO IP_AULA_SOLO IP_DNS_SECUNDARIO ZONA_INVERSA PTR_SERVIDOR ACL_AULA SERIAL
    VARS='${DOMINIO} ${RED_INTERNA} ${IP_INTERNA_SOLO} ${IP_AULA_SOLO} ${IP_DNS_SECUNDARIO} ${ZONA_INVERSA} ${PTR_SERVIDOR} ${ACL_AULA} ${SERIAL}'
    cp dns/named.conf dns/named.conf.options generado/dns/
    envsubst "$VARS" < dns/named.conf.local.tpl   > generado/dns/named.conf.local
    envsubst "$VARS" < dns/interna/db.directa.tpl > "generado/dns/interna/db.$DOMINIO"
    envsubst "$VARS" < dns/interna/db.inversa.tpl > generado/dns/interna/db.inversa
    envsubst "$VARS" < dns/aula/db.directa.tpl    > "generado/dns/aula/db.$DOMINIO"
    envsubst "$VARS" < dns/secundario/named.conf.local.tpl > generado/dns-secundario/named.conf.local
    chmod -R a+rX generado/dns
    clave_tsig

    # Se valida ANTES de tocar el DNS que funciona: si hay un error, no se cambia nada
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


# ---------------------------------------------------------------- Web, BD, LDAP

web() {
    titulo "Servidor Web, Base de Datos, Forgejo y OpenLDAP/LAM"

    # Contraseña de la intranet (se genera desde .env; el fichero no va a Git)
    mkdir -p secretos
    [ -d secretos/intranet.htpasswd ] && rm -rf secretos/intranet.htpasswd   # Docker lo crea como carpeta si no existe
    printf '%s:%s\n' "$INTRANET_USUARIO" "$(openssl passwd -apr1 "$INTRANET_CLAVE")" > secretos/intranet.htpasswd
    chmod 755 secretos
    chmod 644 secretos/intranet.htpasswd

    forgejo_entorno

    # "up -d" solo recrea lo que ha cambiado; los volúmenes (BD, LDAP) NO se tocan.
    # db y git arrancan solos porque web depende de ellos.
    docker compose up -d --build web ldap lam
}

reiniciar() {           # BORRA datos a propósito: por eso hay que escribir --si
    local que="${1:-}" servicios contenedor volumenes
    case "$que" in
        ldap) servicios="lam ldap"; contenedor=ldap ;;
        bd)   servicios="web db";   contenedor=mi-postgres ;;
        *)    echo "Uso: sudo ./instalar.sh reiniciar ldap|bd --si"; exit 1 ;;
    esac
    if [ "${2:-}" != "--si" ]; then
        echo "Esto BORRA todos los datos de '$que' y los crea de nuevo desde cero."
        echo "Si estás seguro:  sudo ./instalar.sh reiniciar $que --si"
        exit 1
    fi
    volumenes=$(docker inspect -f '{{range .Mounts}}{{.Name}} {{end}}' "$contenedor" 2>/dev/null || true)
    docker compose rm -sf $servicios
    # shellcheck disable=SC2086
    [ -z "${volumenes// /}" ] || docker volume rm $volumenes
    web
}


# ---------------------------------------------------------------- Verificación

verificar() {
    titulo "Verificando la sede"
    local aula="${IP_AULA%/*}" r

    # Red
    if ip link show "$BRIDGE_INTERNA" &>/dev/null; then
        ip -br addr show "$BRIDGE_INTERNA" | grep -q "${IP_INTERNA%/*}" && bien "puente" || mal "puente"
        [ "$(sysctl -n net.ipv4.ip_forward)" = 1 ] && bien "forwarding" || mal "forwarding"
        iptables -t nat -C POSTROUTING -s "$RED_INTERNA" -o "$INTERFAZ_AULA" -j MASQUERADE 2>/dev/null \
            && bien "NAT" || mal "NAT"
    else
        echo "AVISO: no existe $BRIDGE_INTERNA (fase red no aplicada): salto las pruebas de red."
    fi

    # Contenedores
    sleep 5
    for c in mi-bind9 mi-apache mi-postgres forgejo ldap lam; do
        estado=$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' "$c" 2>/dev/null || echo "no-existe")
        if [ "$estado" = "true 0" ]; then bien "contenedor $c"
        else mal "contenedor $c ($estado)"; docker logs --tail 15 "$c" 2>&1 || true; fi
    done

    # Base de datos: la web no debe poder borrar
    r=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM inventario WHERE false" 2>&1 || true)
    if echo "$r" | grep -q "permission denied"; then bien "usuario $DB_USER sin permiso de borrado"
    else mal "usuario $DB_USER PUEDE borrar (¿base creada antes del cambio? sudo ./instalar.sh reiniciar bd --si)"; fi

    # SSH de Forgejo
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
        r=$(dig +short +time=2 +tries=1 @127.0.0.1 "www.$DOMINIO" || true)
        [ -n "$r" ] && bien "DNS www -> $r" || mal "DNS: www.$DOMINIO no resuelve"

        r=$(dig +time=3 +tries=1 @127.0.0.1 AXFR "$DOMINIO" 2>&1 || true)
        echo "$r" | grep -q "XFR size" && mal "DNS: la transferencia SIN clave se ha permitido" \
            || bien "DNS: transferencia sin clave rechazada"
        r=$(dig +time=3 +tries=1 @127.0.0.1 AXFR "$DOMINIO" -k generado/dns/tsig.conf 2>&1 || true)
        echo "$r" | grep -q "XFR size" && bien "DNS: transferencia firmada con TSIG" \
            || mal "DNS: la transferencia con la clave TSIG falla"

        if ip -4 -br addr show "$INTERFAZ_AULA" 2>/dev/null | grep -q "$aula"; then
            r=$(dig +short +time=2 +tries=1 -b "$aula" "@$aula" "www.$DOMINIO" A | tail -1 || true)
            [ "$r" = "$aula" ] && bien "DNS vista aula www -> $r" || mal "DNS vista aula: esperaba $aula y salió '$r'"
            r=$(dig +short +time=4 +tries=1 -b "$aula" "@$aula" example.com A | tail -1 || true)
            [ -n "$r" ] && bien "DNS aula resuelve nombres externos (example.com -> $r)" \
                || mal "DNS aula no resuelve nombres externos (¿hay salida a Internet?)"
        fi
    fi

    # GNS3
    if command -v gns3server &>/dev/null; then
        r=$(curl -fs "$GNS3_API/version" 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || true)
        [ -n "$r" ] && bien "servidor GNS3 $r (puerto $GNS3_PUERTO)" || mal "servidor GNS3: no responde en el puerto $GNS3_PUERTO"
        r=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: gns3.$DOMINIO" http://localhost/v2/version || true)
        [ "$r" = 200 ] && bien "gns3.$DOMINIO (Apache -> GNS3)" || mal "gns3.$DOMINIO: recibido $r"
        if ip link show "$BRIDGE_INTERNA" &>/dev/null; then
            pid=$(python3 -c 'import sys,json,zipfile; print(json.loads(zipfile.ZipFile(sys.argv[1]).read("project.gns3"))["project_id"])' "$GNS3_PROYECTO")
            r=$(gns3_nodos_parados "$pid")
            [ "$r" = 0 ] && bien "proyecto GNS3: todos los nodos arrancados" || mal "proyecto GNS3: $r nodo(s) sin arrancar"
        fi
    else
        echo "AVISO: GNS3 no está instalado (ejecuta: sudo ./instalar.sh gns3)"
    fi

    # Web (200, estado, intranet 401/200...)
    bash web/probar.sh || FALLOS=1

    titulo "Estado de los contenedores:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    if [ "$FALLOS" -eq 0 ]; then echo "=== TODO CORRECTO ==="
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
    reiniciar) comprobar; reiniciar "${2:-}" "${3:-}" ;;
    *)
        echo "ERROR: no existe la fase '$1'"
        echo "Fases: comprobar red sistema dns gns3 forgejo web sssd verificar reiniciar"
        exit 1 ;;
esac

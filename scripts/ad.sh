# shellcheck shell=bash
# scripts/ad.sh · Fase "ad": deja el servidor listo para sincronizar OpenLDAP -> Active Directory.
# No se ejecuta solo: lo carga instalar.sh (usa titulo, bien, mal y las variables de sede.env y .env).
#   sudo ./instalar.sh ad      (modo estricto: lo que falle se marca como FALLO)
# Dentro de la ejecución completa (sudo ./instalar.sh) solo avisa si Windows aún no está listo.
#
# LO QUE HACE ESTA FASE (todo en el servidor Linux):
#   1. confía en la CA de AD (sincronizacion/huesca-ad-ca.cer)
#   2. instala los scripts, el temporizador y /etc/huesca/ (configuración y contraseñas, permisos 600)
#   3. comprueba LDAPS con dc1 y la cuenta svc-sync
#   4. ejecuta la primera sincronización y activa el temporizador (cada 10 minutos)
#   5. si hay AD_CLAVE_INICIAL en .env, fija esa contraseña a los investigadores recién creados
#
# LO QUE NO HACE (se hace a mano en dc1, ver docs/ad-windows.md):
#   crear svc-sync, delegarle las OU y los grupos, instalar la CA y exportar el certificado.

# Rutas (se pueden cambiar con variables de entorno, para pruebas)
AD_ETC="${AD_ETC:-/etc/huesca}"
AD_BIN="${AD_BIN:-/usr/local/sbin}"
AD_UNIDADES="${AD_UNIDADES:-/etc/systemd/system}"
AD_CA_DIR="${AD_CA_DIR:-/usr/local/share/ca-certificates}"
AD_HOSTS="${AD_HOSTS:-/etc/hosts}"
AD_ORIGEN="${AD_ORIGEN:-sincronizacion}"

# Un problema de AD es FALLO en modo estricto y solo AVISO en la ejecución completa
ad_problema() {
    if [ "${AD_ESTRICTO:-0}" = 1 ]; then mal "AD: $*"; else echo "AVISO AD: $*"; fi
}

ad_fase() {
    titulo "Sincronización OpenLDAP -> Active Directory"

    # ---- 0. Datos necesarios (sede.env y .env)
    local falta="" v
    for v in AD_DOMINIO AD_DC1 AD_SYNC_USUARIO AD_SYNC_PASSWORD LDAP_ADMIN_PASSWORD DOMINIO; do
        [ -n "${!v:-}" ] || falta="$falta $v"
    done
    if [ -n "$falta" ]; then
        ad_problema "falta en sede.env o .env:$falta (la fase no se aplica)"; return 0
    fi
    if [ ! -f "$AD_ORIGEN/huesca-ad-ca.cer" ]; then
        ad_problema "falta $AD_ORIGEN/huesca-ad-ca.cer: se exporta de la CA de dc1 (docs/ad-windows.md) y se sube al repositorio"
        return 0
    fi
    if grep -q 'PRIVATE KEY' "$AD_ORIGEN/huesca-ad-ca.cer"; then
        mal "AD: $AD_ORIGEN/huesca-ad-ca.cer contiene una CLAVE PRIVADA. Debe ser solo el certificado público; bórralo del repositorio"
        return 0
    fi

    local nombre="${AD_DC1_NOMBRE:-dc1.$AD_DOMINIO}"
    local base="DC=${AD_DOMINIO//./,DC=}"
    local ou_sync="${AD_SYNC_OU:-OU=Servicios,OU=Huesca}"
    local bind_ad="CN=${AD_SYNC_USUARIO},${ou_sync},${base}"
    local base_ldap="dc=${DOMINIO//./,dc=}"
    local admin_ldap="cn=admin,${base_ldap}"
    local lectura_ldap="cn=svc-lectura,ou=servicios,${base_ldap}"

    # ---- 1. Paquetes
    if ! command -v ldapsearch &>/dev/null; then
        echo "    Instalando ldap-utils..."
        apt-get install -y ldap-utils >/dev/null
    fi

    # ---- 2. El servidor tiene que encontrar a dc1 por su nombre (el certificado está emitido a ese nombre)
    if [ "$(getent hosts "$nombre" 2>/dev/null | awk '{print $1; exit}')" != "$AD_DC1" ]; then
        sed -i '/# instalar.sh:ad$/d' "$AD_HOSTS"
        echo "$AD_DC1 $nombre # instalar.sh:ad" >> "$AD_HOSTS"
        echo "    $nombre no resolvía a $AD_DC1: añadido a $AD_HOSTS"
    fi

    # ---- 3. Confianza en la CA de AD (acepta PEM o DER)
    local tmp; tmp="$(mktemp)"
    if grep -q 'BEGIN CERTIFICATE' "$AD_ORIGEN/huesca-ad-ca.cer"; then
        cp "$AD_ORIGEN/huesca-ad-ca.cer" "$tmp"
    elif ! openssl x509 -inform DER -in "$AD_ORIGEN/huesca-ad-ca.cer" -out "$tmp" 2>/dev/null; then
        rm -f "$tmp"; ad_problema "huesca-ad-ca.cer no es un certificado válido (exporta X.509 base 64)"; return 0
    fi
    mkdir -p "$AD_CA_DIR"
    if ! cmp -s "$tmp" "$AD_CA_DIR/huesca-ad-ca.crt"; then
        install -m 644 "$tmp" "$AD_CA_DIR/huesca-ad-ca.crt"
        update-ca-certificates >/dev/null 2>&1 || true
        bien "CA de Active Directory instalada"
    else
        bien "CA de Active Directory ya instalada"
    fi
    rm -f "$tmp"

    # ---- 4. Scripts, unidades y configuración (se instalan siempre; así se pueden repetir sin Windows listo)
    install -m 755 "$AD_ORIGEN/sincronizar-ad.sh" "$AD_ORIGEN/cambiar-clave.sh" "$AD_BIN/"
    install -m 644 "$AD_ORIGEN/sincronizar-ad.service" "$AD_ORIGEN/sincronizar-ad.timer" "$AD_UNIDADES/"
    systemctl daemon-reload 2>/dev/null || true
    install -d -m 700 "$AD_ETC"
    ( umask 077
      printf '%s' "$AD_SYNC_PASSWORD"    > "$AD_ETC/ad-sync.pw"
      printf '%s' "$LDAP_ADMIN_PASSWORD" > "$AD_ETC/ldap-admin.pw"
    )
    bien "scripts instalados en $AD_BIN y contraseñas en $AD_ETC (permisos 600)"

    # ---- 5. OpenLDAP tiene que responder (lo levanta la fase web)
    local i ok=0
    for i in $(seq 1 30); do
        if ldapwhoami -x -H ldap://127.0.0.1:389 -D "$admin_ldap" -y "$AD_ETC/ldap-admin.pw" >/dev/null 2>&1; then ok=1; break; fi
        sleep 2
    done
    if [ "$ok" != 1 ]; then ad_problema "OpenLDAP no responde en 127.0.0.1:389 (¿se ha ejecutado la fase web?)"; return 0; fi

    # Cuenta de lectura: svc-lectura si su contraseña es la del .env; si no, el administrador
    ( umask 077; printf '%s' "$LDAP_ADMIN_PASSWORD" > "$AD_ETC/ldap-lectura.pw" )
    local bind_lectura="$lectura_ldap"
    if ! ldapwhoami -x -H ldap://127.0.0.1:389 -D "$lectura_ldap" -y "$AD_ETC/ldap-lectura.pw" >/dev/null 2>&1; then
        echo "AVISO AD: svc-lectura no entra con LDAP_ADMIN_PASSWORD; la sincronización leerá con cn=admin"
        bind_lectura="$admin_ldap"
    fi

    # ---- 6. Configuración generada desde sede.env y .env (no es una copia de la plantilla)
    ( umask 077
      cat > "$AD_ETC/sync-ad.env" <<CONF
# Generado por instalar.sh (fase ad). No editar a mano: se rehace en cada ejecución.
LDAP_URI="ldap://127.0.0.1:389"
LDAP_BASE="$base_ldap"
LDAP_BIND_DN="$bind_lectura"
LDAP_PWFILE="$AD_ETC/ldap-lectura.pw"
LDAP_ADMIN_DN="$admin_ldap"
LDAP_ADMIN_PWFILE="$AD_ETC/ldap-admin.pw"
AD_URI="ldaps://$nombre:636"
AD_BASE="$base"
AD_UPN="$AD_DOMINIO"
AD_BIND_DN="$bind_ad"
AD_PWFILE="$AD_ETC/ad-sync.pw"
MAX_BAJAS=5
CONF
    )
    bien "configuración generada en $AD_ETC/sync-ad.env"

    # ---- 7. ¿Está Windows listo? LDAPS con nombre correcto y svc-sync
    local salida
    salida="$(timeout 10 openssl s_client -connect "$nombre:636" -verify_hostname "$nombre" </dev/null 2>/dev/null || true)"
    if ! grep -q 'Verify return code: 0 (ok)' <<< "$salida"; then
        ad_problema "LDAPS con $nombre:636 no es válido (¿dc1 sin certificado? ¿CA de otro dominio? ¿puerto bloqueado?). Termina la parte de Windows (docs/ad-windows.md) y repite: sudo ./instalar.sh ad"
        return 0
    fi
    bien "LDAPS con $nombre: certificado de confianza"
    if ! ldapwhoami -x -H "ldaps://$nombre:636" -D "$bind_ad" -y "$AD_ETC/ad-sync.pw" >/dev/null 2>&1; then
        ad_problema "no puedo entrar en AD como $bind_ad (¿existe svc-sync en esa OU? ¿contraseña igual que AD_SYNC_PASSWORD?)"
        return 0
    fi
    bien "AD: $AD_SYNC_USUARIO autentica correctamente"

    # ---- 8. Primera sincronización y temporizador
    if "$AD_BIN/sincronizar-ad.sh"; then
        bien "primera sincronización completada"
    else
        ad_problema "la sincronización terminó con errores (revísala con: sudo sincronizar-ad.sh; suele ser un permiso de delegación que falta en AD)"
        return 0
    fi
    systemctl enable --now sincronizar-ad.timer >/dev/null 2>&1 && bien "temporizador activo (cada 10 minutos)" \
        || ad_problema "no he podido activar sincronizar-ad.timer"

    # ---- 9. Contraseña inicial de los investigadores nuevos (opcional)
    local pendientes uid
    pendientes="$(ldapsearch -LLL -x -H "ldaps://$nombre:636" -D "$bind_ad" -y "$AD_ETC/ad-sync.pw" \
        -b "OU=Investigadores,OU=Huesca,$base" -s one \
        "(&(objectClass=user)(info=sync:openldap)(userAccountControl:1.2.840.113556.1.4.803:=2))" sAMAccountName 2>/dev/null \
        | sed -n 's/^sAMAccountName: //p')" || true
    if [ -z "$pendientes" ]; then
        bien "no hay cuentas de investigador pendientes de contraseña"
    elif [ -n "${AD_CLAVE_INICIAL:-}" ]; then
        for uid in $pendientes; do
            if NUEVA_CLAVE="$AD_CLAVE_INICIAL" CAMBIAR=1 "$AD_BIN/cambiar-clave.sh" "$uid" >/dev/null 2>&1; then
                bien "contraseña inicial fijada a $uid (la cambiará en su primer inicio de sesión en Windows)"
            else
                ad_problema "no he podido fijar la contraseña de $uid (¿cumple la política de AD? mínimo 12 caracteres y complejidad)"
            fi
        done
    else
        echo "AVISO AD: cuentas creadas pero deshabilitadas hasta fijar su contraseña: $(echo $pendientes)"
        echo "          fíjala con: sudo cambiar-clave.sh <usuario>   (o pon AD_CLAVE_INICIAL en .env y repite la fase)"
    fi
}

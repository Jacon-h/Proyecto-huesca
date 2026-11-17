#!/usr/bin/env bash
# alta-investigador.sh · Da de alta un investigador de principio a fin:
#   1. valida la contraseña ANTES de tocar nada (política de AD: 12+ caracteres y complejidad)
#   2. crea la cuenta en OpenLDAP (ou=investigadores) con uidNumber libre
#   3. la sincroniza a Active Directory (sincronizar-ad.sh)
#   4. fija la misma contraseña en OpenLDAP y AD y habilita la cuenta (cambiar-clave.sh)
#
#   sudo alta-investigador.sh UID "Nombre" "Apellidos" [correo]
#   sudo CAMBIAR=1 alta-investigador.sh jperez "Juan" "Pérez Gil"   (obliga a cambiar la clave en el primer inicio en Windows)
#   sudo NUEVA_CLAVE='...' alta-investigador.sh ...                 (sin preguntar la contraseña)
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/huesca/sync-ad.env}"
# shellcheck source=/dev/null
source "$ENV_FILE"
: "${LDAP_URI:?}" "${LDAP_BASE:?}" "${LDAP_ADMIN_DN:?}" "${LDAP_ADMIN_PWFILE:?}"
BIN="${BIN:-/usr/local/sbin}"

uid="${1:?uso: alta-investigador.sh UID \"Nombre\" \"Apellidos\" [correo]}"
nombre="${2:?falta el nombre}"
apellidos="${3:?falta los apellidos}"
correo="${4:-}"

adm() { "$1" -x -H "$LDAP_URI" -D "$LDAP_ADMIN_DN" -y "$LDAP_ADMIN_PWFILE" "${@:2}"; }

# --- 1. Validaciones previas -------------------------------------------------
[[ "$uid" =~ ^[a-z][a-z0-9._-]{2,19}$ ]] \
    || { echo "UID no válido: usa minúsculas, números, . _ - (3 a 20 caracteres, empieza por letra)." >&2; exit 1; }

clave_valida() {   # $1 = clave; imprime el motivo y devuelve 1 si AD la rechazaría
    local c="$1" clases=0 minus t i
    [ "${#c}" -ge 12 ] || { echo "Mínimo 12 caracteres."; return 1; }
    [[ "$c" =~ [a-z] ]] && clases=$((clases + 1))
    [[ "$c" =~ [A-Z] ]] && clases=$((clases + 1))
    [[ "$c" =~ [0-9] ]] && clases=$((clases + 1))
    [[ "$c" =~ [^a-zA-Z0-9] ]] && clases=$((clases + 1))
    [ "$clases" -ge 3 ] || { echo "Necesita 3 de 4: mayúscula, minúscula, número y símbolo."; return 1; }
    minus="${c,,}"
    # AD rechaza claves con 3+ letras seguidas del usuario o de las palabras del nombre
    for t in "$uid" $nombre $apellidos; do
        t="${t,,}"
        [ "${#t}" -ge 3 ] || continue
        for ((i = 0; i + 3 <= ${#t}; i++)); do
            if [[ "$minus" == *"${t:i:3}"* ]]; then
                echo "No puede contener partes del nombre o usuario (aparece '${t:i:3}')."; return 1
            fi
        done
    done
    return 0
}

if [ -z "${NUEVA_CLAVE:-}" ]; then
    while true; do
        read -r -s -p "Contraseña para $uid: " NUEVA_CLAVE; echo
        if motivo="$(clave_valida "$NUEVA_CLAVE")"; then
            read -r -s -p "Repite la contraseña: " REPITE; echo
            [ "$NUEVA_CLAVE" = "$REPITE" ] && break
            echo "No coinciden."
        else
            echo "  $motivo"
        fi
    done
else
    motivo="$(clave_valida "$NUEVA_CLAVE")" || { echo "Contraseña no válida: $motivo" >&2; exit 1; }
fi
export NUEVA_CLAVE

if [ -n "$(adm ldapsearch -LLL -b "$LDAP_BASE" "(uid=$uid)" dn)" ]; then
    echo "Ya existe $uid en OpenLDAP." >&2; exit 1
fi

# --- 2. Alta en OpenLDAP -----------------------------------------------------
OU="ou=investigadores,$LDAP_BASE"
# uidNumber libre: el mayor existente + 1 (mínimo 10000)
mayor="$(adm ldapsearch -LLL -b "$LDAP_BASE" '(uidNumber=*)' uidNumber | sed -n 's/^uidNumber: //p' | sort -n | tail -1)"
uidn=$(( ${mayor:-9999} + 1 )); [ "$uidn" -ge 10000 ] || uidn=10000
# gidNumber: el de los investigadores que ya existen (o GIDNUMBER=... si lo fijas tú)
gidn="${GIDNUMBER:-$(adm ldapsearch -LLL -b "$OU" -s one '(objectClass=posixAccount)' gidNumber | sed -n 's/^gidNumber: //p' | head -1)}"
[ -n "$gidn" ] || { echo "No encuentro un gidNumber de referencia; ejecuta con GIDNUMBER=<número>." >&2; exit 1; }

b64() { if printf '%s' "$2" | LC_ALL=C grep -q '[^ -~]'; then printf '%s:: %s\n' "$1" "$(printf '%s' "$2" | base64 -w0)"; else printf '%s: %s\n' "$1" "$2"; fi; }
{
    echo "dn: uid=$uid,$OU"
    echo "objectClass: inetOrgPerson"; echo "objectClass: posixAccount"
    echo "uid: $uid"
    b64 cn "$nombre $apellidos"; b64 givenName "$nombre"; b64 sn "$apellidos"
    [ -z "$correo" ] || echo "mail: $correo"
    echo "uidNumber: $uidn"; echo "gidNumber: $gidn"
    echo "homeDirectory: /home/$uid"; echo "loginShell: /bin/bash"
} | adm ldapadd >/dev/null
echo "OpenLDAP: creado uid=$uid (uidNumber $uidn)."

# --- 3. Sincronización a AD y 4. contraseña ----------------------------------
"$BIN/sincronizar-ad.sh"
"$BIN/cambiar-clave.sh" "$uid"
echo "Listo: $uid creado en OpenLDAP y AD, con la misma contraseña y la cuenta habilitada."

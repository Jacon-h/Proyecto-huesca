#!/usr/bin/env bash
# cambiar-clave.sh UID · fija la MISMA contraseña en OpenLDAP y en AD y habilita la cuenta de AD.
#   sudo cambiar-clave.sh jperez                  pide la contraseña dos veces
#   sudo CAMBIAR=1 cambiar-clave.sh jperez        además obliga a cambiarla en el primer inicio de sesión (AD)
#   SOLO_AD=1 NUEVA_CLAVE=... cambiar-clave.sh visita-20261112-01   (pases: la clave ya está en OpenLDAP)
# Antes hay que haber ejecutado sincronizar-ad.sh para que la cuenta exista en AD.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/huesca/sync-ad.env}"
# shellcheck source=/dev/null
source "$ENV_FILE"
: "${LDAP_URI:?}" "${LDAP_BASE:?}" "${LDAP_ADMIN_DN:?}" "${LDAP_ADMIN_PWFILE:?}"
: "${AD_URI:?}" "${AD_BASE:?}" "${AD_BIND_DN:?}" "${AD_PWFILE:?}"
MARCA="sync:openldap"
uid="${1:?uso: cambiar-clave.sh UID}"

if [ -z "${NUEVA_CLAVE:-}" ]; then
    read -r -s -p "Nueva contraseña para $uid: " NUEVA_CLAVE; echo
    read -r -s -p "Repite la contraseña: " REPITE; echo
    [ "$NUEVA_CLAVE" = "$REPITE" ] || { echo "No coinciden." >&2; exit 1; }
fi
if [ "${#NUEVA_CLAVE}" -lt 10 ]; then echo "Mínimo 10 caracteres (política de AD)." >&2; exit 1; fi

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT; chmod 600 "$TMP"

# 1. OpenLDAP (el hash lo calcula el servidor; ppolicy se aplica allí)
if [ "${SOLO_AD:-0}" != 1 ]; then
    dn_ol="$(ldapsearch -LLL -x -H "$LDAP_URI" -D "$LDAP_ADMIN_DN" -y "$LDAP_ADMIN_PWFILE" \
             -b "$LDAP_BASE" "(&(objectClass=posixAccount)(uid=$uid))" dn | sed -n 's/^dn: //p' | head -1)"
    [ -n "$dn_ol" ] || { echo "No existe $uid en OpenLDAP." >&2; exit 1; }
    printf '%s' "$NUEVA_CLAVE" > "$TMP"
    ldappasswd -x -H "$LDAP_URI" -D "$LDAP_ADMIN_DN" -y "$LDAP_ADMIN_PWFILE" -T "$TMP" "$dn_ol"
    echo "OpenLDAP: contraseña cambiada."
fi

# 2. Active Directory (unicodePwd = contraseña entre comillas, UTF-16LE, en base64; exige LDAPS)
dn_ad="$(ldapsearch -LLL -x -H "$AD_URI" -D "$AD_BIND_DN" -y "$AD_PWFILE" -b "$AD_BASE" \
         "(&(sAMAccountName=$uid)(info=$MARCA))" dn | sed -n 's/^dn: //p' | head -1)"
[ -n "$dn_ad" ] || { echo "No hay cuenta sincronizada de $uid en AD: ejecuta antes sincronizar-ad.sh." >&2; exit 1; }
pwd_b64="$(printf '"%s"' "$NUEVA_CLAVE" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)"
{
    echo "dn: $dn_ad"; echo "changetype: modify"
    echo "replace: unicodePwd";          echo "unicodePwd:: $pwd_b64"; echo "-"
    echo "replace: userAccountControl";  echo "userAccountControl: 512"; echo "-"
    if [ "${CAMBIAR:-0}" = 1 ]; then echo "replace: pwdLastSet"; echo "pwdLastSet: 0"; echo "-"; fi
} | ldapmodify -x -H "$AD_URI" -D "$AD_BIND_DN" -y "$AD_PWFILE" >/dev/null
echo "Active Directory: contraseña fijada y cuenta habilitada."

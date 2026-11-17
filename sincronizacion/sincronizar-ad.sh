#!/usr/bin/env bash
# sincronizar-ad.sh · Sincroniza OpenLDAP (fuente de verdad) -> Active Directory, en un solo sentido.
#   sudo sincronizar-ad.sh              aplica los cambios
#   sudo DRY_RUN=1 sincronizar-ad.sh    solo muestra lo que haría
#   sudo FORZAR=1 sincronizar-ad.sh     permite más bajas que MAX_BAJAS en esta pasada
# Solo toca en AD las cuentas que lleva la marca "info: sync:openldap" (las creó este script).
# No sincroniza contraseñas: eso lo hace cambiar-clave.sh.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/huesca/sync-ad.env}"
# shellcheck source=/dev/null
source "$ENV_FILE"
: "${LDAP_URI:?}" "${LDAP_BIND_DN:?}" "${LDAP_PWFILE:?}" "${LDAP_BASE:?}"
: "${AD_URI:?}" "${AD_BIND_DN:?}" "${AD_PWFILE:?}" "${AD_BASE:?}" "${AD_UPN:?}"
DRY_RUN="${DRY_RUN:-0}"
FORZAR="${FORZAR:-0}"
MAX_BAJAS="${MAX_BAJAS:-5}"
LOCK_FILE="${LOCK_FILE:-/run/lock/sincronizar-ad.lock}"
MARCA="sync:openldap"
OU_INV="OU=Investigadores,OU=Huesca,${AD_BASE}"
OU_VIS="OU=Visitas,OU=Huesca,${AD_BASE}"
GRP_INV="CN=GG-Investigadores,OU=Grupos,OU=Huesca,${AD_BASE}"
GRP_VIS="CN=GG-Visitas,OU=Grupos,OU=Huesca,${AD_BASE}"

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Ya hay otra sincronización en marcha"; exit 0; }

ERRORES=0
LDIF=""
CAMBIOS=0
declare -A ORIGEN   # uid -> investigadores | visitas (todo lo que existe en OpenLDAP)

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
src() { ldapsearch -LLL -o ldif-wrap=no -x -H "$LDAP_URI" -D "$LDAP_BIND_DN" -y "$LDAP_PWFILE" "$@"; }
ad()  { ldapsearch -LLL -o ldif-wrap=no -x -H "$AD_URI" -D "$AD_BIND_DN" -y "$AD_PWFILE" "$@"; }

ad_aplicar() {   # aplica en AD el LDIF que llega por stdin
    if [ "$DRY_RUN" = 1 ]; then sed 's/^/    [dry-run] /'; return 0; fi
    if ! ldapmodify -x -H "$AD_URI" -D "$AD_BIND_DN" -y "$AD_PWFILE" >/dev/null; then
        log "ERROR: ldapmodify falló"; ERRORES=$((ERRORES + 1))
    fi
}

valor_ldif() {   # línea LDIF "atributo: valor" (en base64 si el valor tiene caracteres no ASCII)
    if printf '%s' "$2" | LC_ALL=C grep -q '[^ -~]'; then
        printf '%s:: %s\n' "$1" "$(printf '%s' "$2" | base64 -w0)"
    else
        printf '%s: %s\n' "$1" "$2"
    fi
}
linea() { LDIF+="$1"$'\n'; }
opt()   { if [ -n "$2" ]; then LDIF+="$(valor_ldif "$1" "$2")"$'\n'; fi; }

caduca_ad() {    # shadowExpire (días desde 1970) -> accountExpires de AD (0 = no caduca)
    if [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]; then
        echo $(( ($1 * 86400 + 11644473600) * 10000000 ))
    else
        echo 0
    fi
}

leer_origen() {  # $1 = ou de OpenLDAP; imprime uid|givenName|sn|cn|mail|shadowExpire
    local out uid="" gn="" sn="" cn="" mail="" exp="" line k v
    out="$(src -b "ou=$1,${LDAP_BASE}" -s one '(objectClass=posixAccount)' uid givenName sn cn mail shadowExpire)" || return 1
    emitir() {
        if [ -n "$uid" ]; then printf '%s|%s|%s|%s|%s|%s\n' "$uid" "$gn" "$sn" "$cn" "$mail" "$exp"; fi
        uid=""; gn=""; sn=""; cn=""; mail=""; exp=""
    }
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then emitir; continue; fi
        if [[ "$line" =~ ^([A-Za-z0-9\;-]+)::\ (.*)$ ]]; then
            k="${BASH_REMATCH[1]}"; v="$(printf '%s' "${BASH_REMATCH[2]}" | base64 -d)"
        else
            k="${line%%:*}"; v="${line#*: }"
        fi
        case "$k" in
            uid) uid="$v" ;; givenName) gn="$v" ;; sn) sn="$v" ;;
            cn) cn="$v" ;; mail) mail="$v" ;; shadowExpire) exp="$v" ;;
        esac
    done <<< "$out"
    emitir
}

campo() {        # valor de un atributo dentro de $ACTUAL (resultado de ldapsearch en AD)
    local l
    l="$(printf '%s\n' "$ACTUAL" | grep -m1 -i "^$1::\? " || true)"
    if [ -z "$l" ]; then return 0; fi
    if [[ "$l" =~ ^[^:]+::\ (.*)$ ]]; then printf '%s' "${BASH_REMATCH[1]}" | base64 -d; else printf '%s' "${l#*: }"; fi
}

cmp_attr() {     # $1 atributo, $2 valor nuevo (OpenLDAP), $3 valor actual (AD)
    if [ "$2" = "$3" ]; then return 0; fi
    if [ -n "$2" ]; then
        LDIF+="replace: $1"$'\n'"$(valor_ldif "$1" "$2")"$'\n-\n'
    elif [ -n "$3" ]; then
        LDIF+="delete: $1"$'\n-\n'
    fi
    CAMBIOS=1
}

asegurar_grupo() {   # $1 = DN del grupo, $2 = DN de la cuenta
    local r
    r="$(ad -b "$1" -s base "(member=$2)" dn)" || { log "ERROR leyendo $1"; ERRORES=$((ERRORES + 1)); return 0; }
    if [ -z "$r" ]; then
        log "GRUPO  $2 -> $1"
        LDIF=""; linea "dn: $1"; linea "changetype: modify"; linea "add: member"; linea "member: $2"
        ad_aplicar <<< "$LDIF"
    fi
}

sincronizar_usuario() {  # tipo ou_ad grupo uid gn sn cn mail exp
    local tipo="$1" ou="$2" grp="$3" uid="$4" gn="$5" sn="$6" cn="$7" mail="$8" exp="$9"
    local nombre="${cn:-$uid}" caduca dn marca viejo_exp
    caduca="$(caduca_ad "$exp")"
    ACTUAL="$(ad -b "$AD_BASE" -s sub "(sAMAccountName=${uid})" dn info givenName sn displayName mail accountExpires)" \
        || { log "ERROR leyendo AD ($uid)"; ERRORES=$((ERRORES + 1)); return 0; }

    if [ -z "$ACTUAL" ]; then
        dn="CN=${uid},${ou}"
        log "ALTA   $uid ($tipo), caduca=$caduca"
        LDIF=""
        linea "dn: $dn"; linea "changetype: add"
        linea "objectClass: top"; linea "objectClass: person"
        linea "objectClass: organizationalPerson"; linea "objectClass: user"
        linea "sAMAccountName: $uid"; linea "userPrincipalName: ${uid}@${AD_UPN}"
        opt displayName "$nombre"; opt givenName "$gn"; opt sn "$sn"; opt mail "$mail"
        linea "info: $MARCA"
        linea "accountExpires: $caduca"
        linea "userAccountControl: 514"    # nace deshabilitada: se habilita al fijar la clave (cambiar-clave.sh)
        ad_aplicar <<< "$LDIF"
        if [ "$DRY_RUN" != 1 ]; then asegurar_grupo "$grp" "$dn"; fi
        return 0
    fi

    marca="$(campo info)"
    if [ "$marca" != "$MARCA" ]; then
        log "OMITE  $uid: ya existe en AD y no lo gestiona la sincronización"
        return 0
    fi
    dn="$(printf '%s\n' "$ACTUAL" | sed -n 's/^dn: //p' | head -1)"
    viejo_exp="$(campo accountExpires)"
    if [ "$viejo_exp" = "9223372036854775807" ]; then viejo_exp=0; fi

    LDIF=""; CAMBIOS=0
    linea "dn: $dn"; linea "changetype: modify"
    cmp_attr givenName "$gn" "$(campo givenName)"
    cmp_attr sn "$sn" "$(campo sn)"
    cmp_attr displayName "$nombre" "$(campo displayName)"
    cmp_attr mail "$mail" "$(campo mail)"
    cmp_attr accountExpires "$caduca" "$viejo_exp"
    if [ "$CAMBIOS" = 1 ]; then
        log "CAMBIO $uid"
        ad_aplicar <<< "$LDIF"
    fi
    asegurar_grupo "$grp" "$dn"
}

procesar() {     # tipo, lista (uid|gn|sn|cn|mail|exp), ou_ad, grupo
    local tipo="$1" lista="$2" ou="$3" grp="$4" uid gn sn cn mail exp
    while IFS='|' read -r uid gn sn cn mail exp; do
        if [ -z "$uid" ]; then continue; fi
        ORIGEN[$uid]="$tipo"
        sincronizar_usuario "$tipo" "$ou" "$grp" "$uid" "$gn" "$sn" "$cn" "$mail" "$exp"
    done <<< "$lista"
}

bajas() {        # tipo, ou_ad: cuentas marcadas que ya no existen en OpenLDAP
    local tipo="$1" ou="$2" r uid uac candidatos=()
    r="$(ad -b "$ou" -s one "(&(objectClass=user)(info=${MARCA}))" sAMAccountName userAccountControl)" \
        || { log "ERROR leyendo $ou"; ERRORES=$((ERRORES + 1)); return 0; }
    while IFS='|' read -r uid uac; do
        if [ -z "$uid" ]; then continue; fi
        if [ -n "${ORIGEN[$uid]:-}" ]; then continue; fi
        if [ "$tipo" = investigadores ] && [ $((uac & 2)) -ne 0 ]; then continue; fi   # ya deshabilitada
        candidatos+=("${uid}|${uac}")
    done < <(printf '%s\n' "$r" | awk -F': ' '/^sAMAccountName: /{u=$2} /^userAccountControl: /{c=$2} /^$/{if(u!="")print u"|"c; u="";c=""} END{if(u!="")print u"|"c}')

    if [ "${#candidatos[@]}" -gt "$MAX_BAJAS" ] && [ "$FORZAR" != 1 ]; then
        log "ERROR: ${#candidatos[@]} bajas en $tipo (máximo $MAX_BAJAS). No se hace ninguna; revisa OpenLDAP o usa FORZAR=1"
        ERRORES=$((ERRORES + 1)); return 0
    fi
    local c
    for c in "${candidatos[@]}"; do
        IFS='|' read -r uid uac <<< "$c"
        LDIF=""; linea "dn: CN=${uid},${ou}"
        if [ "$tipo" = visitas ]; then
            log "BAJA   $uid (visita eliminada)"
            linea "changetype: delete"
        else
            log "BAJA   $uid (investigador deshabilitado)"
            linea "changetype: modify"; linea "replace: userAccountControl"; linea "userAccountControl: $((uac | 2))"
        fi
        ad_aplicar <<< "$LDIF"
    done
}

log "Inicio (DRY_RUN=$DRY_RUN)"
INV="$(leer_origen investigadores)" || { log "ERROR: no se pudo leer ou=investigadores en OpenLDAP; no se toca AD"; exit 1; }
VIS="$(leer_origen visitas)"        || { log "ERROR: no se pudo leer ou=visitas en OpenLDAP; no se toca AD"; exit 1; }
if [ -z "$INV" ]; then log "ERROR: origen vacío (0 investigadores); no se toca AD"; exit 1; fi

procesar investigadores "$INV" "$OU_INV" "$GRP_INV"
procesar visitas        "$VIS" "$OU_VIS" "$GRP_VIS"
bajas investigadores "$OU_INV"
bajas visitas        "$OU_VIS"

log "Fin: ${#ORIGEN[@]} cuentas en OpenLDAP, $ERRORES errores"
if [ "$ERRORES" -gt 0 ]; then exit 1; fi

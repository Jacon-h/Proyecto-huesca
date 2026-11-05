# shellcheck shell=bash
# scripts/sssd.sh · Fase "sssd": hace que este servidor autentique con OpenLDAP.
# No se ejecuta solo: lo carga instalar.sh.
#   sudo ./instalar.sh sssd
sssd_cliente() {
    echo "== Cliente SSSD para OpenLDAP"
    
    # 1. Instalar paquetes requeridos
    if ! command -v sssd &>/dev/null; then
        echo "    Instalando sssd, sssd-ldap, libpam-sss y herramientas..."
        apt-get update >/dev/null 2>&1
        apt-get install -y sssd sssd-ldap libpam-sss libnss-sss ldap-utils ca-certificates gettext-base >/dev/null
    fi

    # 2. Copiar/procesar plantilla o generar configuración por defecto
    mkdir -p /etc/sssd
    if [ -f clientes/sssd.conf.tpl ]; then
        echo "    Procesando plantilla clientes/sssd.conf.tpl -> /etc/sssd/sssd.conf"
        envsubst < clientes/sssd.conf.tpl > /etc/sssd/sssd.conf
    elif [ -f clientes/sssd.conf ]; then
        echo "    Copiando plantilla clientes/sssd.conf -> /etc/sssd/sssd.conf"
        cp clientes/sssd.conf /etc/sssd/sssd.conf
    else
        echo "    Generando /etc/sssd/sssd.conf..."
        cat <<EOF > /etc/sssd/sssd.conf
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
ldap_default_authtok = ${LDAP_ADMIN_PASSWORD}
ldap_tls_reqcert = allow
ldap_account_expire_policy = shadow
cache_credentials = true
EOF
    fi

    # 3. Aplicar permisos y reiniciar servicio
    chmod 600 /etc/sssd/sssd.conf
    pam-auth-update --enable mkhomedir 2>/dev/null || true
    systemctl restart sssd 2>/dev/null || true
    echo "    SSSD configurado y activo."
}

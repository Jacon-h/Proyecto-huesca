$TTL 604800
@       IN  SOA ns1.${DOMINIO}. admin.${DOMINIO}. (
                ${SERIAL}   ; Serial
                604800      ; Refresh
                86400       ; Retry
                2419200     ; Expire (corregido: antes 19200)
                604800 )    ; Negative TTL

@       IN  NS  ns1.${DOMINIO}.
@       IN  MX  10 correo.${DOMINIO}.

; Desde el aula todo se ve por la IP del aula del servidor
servidor IN A   ${IP_AULA_SOLO}
ns1      IN A   ${IP_AULA_SOLO}
correo   IN A   ${IP_AULA_SOLO}

srv      IN CNAME servidor
www      IN CNAME servidor
intranet IN CNAME servidor
git      IN CNAME servidor
db       IN CNAME servidor
gns3     IN CNAME servidor

ldap     IN CNAME servidor
lam      IN CNAME servidor

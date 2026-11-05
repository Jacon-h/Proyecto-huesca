$TTL 604800
@       IN  SOA ns1.${DOMINIO}. admin.${DOMINIO}. (
                ${SERIAL}   ; Serial
                604800      ; Refresh
                86400       ; Retry
                2419200     ; Expire
                604800 )    ; Negative TTL

@       IN  NS  ns1.${DOMINIO}.
@       IN  NS  ns2.${DOMINIO}.
@       IN  MX  10 correo.${DOMINIO}.

servidor IN A   ${IP_INTERNA_SOLO}
ns1      IN A   ${IP_INTERNA_SOLO}
ns2      IN A   ${IP_DNS_SECUNDARIO}
correo   IN A   ${IP_INTERNA_SOLO}

srv      IN CNAME servidor
www      IN CNAME servidor
intranet IN CNAME servidor
git      IN CNAME servidor
db       IN CNAME servidor
gns3     IN CNAME servidor

ldap     IN CNAME servidor
lam      IN CNAME servidor

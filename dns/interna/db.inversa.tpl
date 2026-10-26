$TTL 604800
@       IN  SOA ns1.${DOMINIO}. admin.${DOMINIO}. (
                ${SERIAL}   ; Serial
                604800      ; Refresh
                86400       ; Retry
                2419200     ; Expire
                604800 )    ; Negative TTL

@       IN  NS  ns1.${DOMINIO}.
@       IN  NS  ns2.${DOMINIO}.

${PTR_SERVIDOR}  IN PTR servidor.${DOMINIO}.

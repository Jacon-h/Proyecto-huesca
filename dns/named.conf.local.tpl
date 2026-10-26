acl internos { ${RED_INTERNA}; 127.0.0.1; };
acl aula_ip  { ${ACL_AULA} };

view "interna" {
    match-clients { internos; };
    recursion yes;
    allow-query { internos; };
    forwarders {
        8.8.8.8;
        1.1.1.1;
    };

    zone "${DOMINIO}" {
        type master;
        file "/etc/bind/interna/db.${DOMINIO}";
        allow-transfer { ${IP_DNS_SECUNDARIO}; };
        also-notify { ${IP_DNS_SECUNDARIO}; };
    };

    zone "${ZONA_INVERSA}" {
        type master;
        file "/etc/bind/interna/db.inversa";
        allow-transfer { ${IP_DNS_SECUNDARIO}; };
        also-notify { ${IP_DNS_SECUNDARIO}; };
    };
};

view "aula" {
    match-clients { aula_ip; };
    allow-transfer { none; };
    recursion no;
    allow-query { any; };

    zone "${DOMINIO}" {
        type master;
        file "/etc/bind/aula/db.${DOMINIO}";
    };
};

// Configuración del DNS secundario (dns-secundario-1 en GNS3).
// Copia del primario ${IP_INTERNA_SOLO}: recibe las zonas de la vista "interna",
// y las pide firmadas con la clave TSIG (tsig.conf, que genera instalar.sh dns).
include "/etc/bind/tsig.conf";

zone "${DOMINIO}" {
    type slave;
    masters { ${IP_INTERNA_SOLO} key clave-transferencia; };
    file "/var/cache/bind/db.${DOMINIO}";
};

zone "${ZONA_INVERSA}" {
    type slave;
    masters { ${IP_INTERNA_SOLO} key clave-transferencia; };
    file "/var/cache/bind/db.inversa";
};

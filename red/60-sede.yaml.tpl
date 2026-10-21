network:
  version: 2
  renderer: networkd
  ethernets:
    ${INTERFAZ_AULA}:
      dhcp4: false
      addresses: [${IP_AULA}]
      routes:
        - to: default
          via: ${PUERTA_AULA}
      nameservers:
        addresses: [${RESOLUTOR_CENTRO}]
  bridges:
    ${BRIDGE_INTERNA}:
      addresses: [${IP_INTERNA}]
      parameters:
        stp: false
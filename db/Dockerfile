# db/Dockerfile · PostgreSQL 16 oficial + locale español (ASGBD RA2, P7)
#
# La imagen oficial solo trae el locale en_US.UTF-8. Sin es_ES.UTF-8 no se puede crear la base
# bifi con colación española. Esta línea es la que indica la propia documentación de la imagen
# oficial (apartado "Locale Customization"): genera el locale y no cambia nada más.
FROM postgres:16

RUN localedef -i es_ES -c -f UTF-8 -A /usr/share/locale/locale.alias es_ES.UTF-8

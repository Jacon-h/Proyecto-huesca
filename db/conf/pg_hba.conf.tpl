# db/conf/pg_hba.conf.tpl · PLANTILLA de pg_hba.conf. Se edita ESTA, no el fichero generado.
# instalar.sh la rellena con BIFI_DB, BIFI_PANEL_USER y BIFI_RESP_USER (.env) y REDES_AULA (sede.env)
# y escribe db/conf/pg_hba.conf (que no va a Git). Quién entra, a qué base, desde dónde y cómo (ASGBD RA2)
#
# PostgreSQL lee las líneas de arriba abajo y aplica la PRIMERA que coincide; no sigue mirando.
# Por eso las prohibiciones concretas van antes que los permisos generales, y el "reject" final
# recoge todo lo que no ha coincidido con nada. Cada línea está explicada en db/README.md.
#
# samenet = cualquier dirección de las redes a las que está conectado el contenedor, es decir,
#           las dos redes de Compose (frontal y trasera). Su rango real: docker network inspect.
# all (en DIRECCIÓN) = cualquier IP, tanto IPv4 como IPv6.

# TIPO  BASE    USUARIO     DIRECCIÓN          MÉTODO

# 1 · Administrador por socket, dentro del contenedor y siendo el usuario postgres del sistema
#     (docker exec -u postgres mi-postgres psql). Así arrancan también los scripts de db/.
local   all     postgres                       peer

# 2 · Cualquier otro usuario por socket: siempre con contraseña.
local   all     all                            scram-sha-256

# 3 · P2 · El administrador NO entra por red, venga de donde venga (Compose, aula o el propio servidor).
host    all     postgres    all                reject

# 4 · P1 · El panel entra en bifi desde las redes de Compose.
host    ${BIFI_DB}    ${BIFI_PANEL_USER}    samenet    scram-sha-256

# 5 · La web (usuario DB_USER de .env) y el resto de servicios de Compose, con contraseña.
#     Qué base puede abrir cada uno lo deciden los permisos CONNECT (db/04_bifi.sh).
host    all     all         samenet            scram-sha-256

# 6 · P3 · El responsable entra en bifi desde los equipos del aula (las redes de REDES_AULA de sede.env).
${LINEAS_AULA}

# 7 · P4 · Nadie más entra. Tiene que ser la última línea.
host    all     all         all                reject

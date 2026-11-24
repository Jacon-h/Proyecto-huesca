# db/ · PostgreSQL de la sede (ASGBD RA2 · «La base abre a clientes de fuera»)

Todo lo que necesita la base para nacer configurada, sin tocar nada a mano: la imagen, la configuración,
las bases, los usuarios y sus permisos. Ni las contraseñas ni los nombres de la base del panel y de sus
usuarios están escritos aquí: llegan de `.env` por variables de entorno (`compose.yaml`).

## Variables de `.env` que usa la base

| Variable | Valor en `.env.example` | Para qué |
|---|---|---|
| `DB_NAME`, `DB_USER`, `DB_PASSWORD` | (vacío) | Base de la web, su usuario y su contraseña |
| `POSTGRES_PASSWORD` | (vacío) | Contraseña del administrador `postgres` |
| `BIFI_DB` | `bifi` | Base del panel del BIFI (la práctica pide que se llame `bifi`) |
| `BIFI_PANEL_USER`, `BIFI_PANEL_PASSWORD` | `panel`, (vacío) | Usuario con el que entra la aplicación del panel desde Compose |
| `BIFI_RESP_USER`, `BIFI_RESP_PASSWORD` | `resp_demo`, (vacío) | Usuario con el que entra un responsable desde el aula |

En el resto de este documento se usan los valores de `.env.example` (`bifi`, `panel`, `resp_demo`). Si
cambias los nombres en `.env`, `sudo ./instalar.sh bd` vuelve a generar `pg_hba.conf` y crea lo que falte.
`instalar.sh` comprueba que los nombres solo tienen minúsculas, números y `_`, que `BIFI_DB` es distinta
de `DB_NAME` y que ningún usuario se repite ni se llama `postgres`.

Lo que **no** sale de `.env`, a propósito:
- `postgres` (el administrador): es también el usuario del sistema dentro de la imagen, y la línea `peer`
  de `pg_hba.conf` se basa en que se llamen igual.
- `db` (el host al que se conectan la web y el panel): es el nombre del servicio en el propio `compose.yaml`.
- Las redes del aula: salen de `REDES_AULA` en `sede.env`, que es donde el proyecto guarda los datos de red.

## Qué hay

| Fichero | Qué hace |
|---|---|
| `Dockerfile` | Imagen `postgres:16` oficial + el locale `es_ES.UTF-8` (sin él no se puede crear `bifi` con colación española). |
| `conf/postgresql.conf` | Parámetros del gestor. Se monta en `/etc/postgresql/postgresql.conf` y se arranca con `-c config_file=…`. |
| `conf/pg_hba.conf.tpl` | Plantilla de las reglas de acceso: quién entra, a qué base, desde dónde y cómo. |
| `conf/pg_hba.conf` | **Lo genera `instalar.sh`** desde la plantilla con los nombres de `.env` y las redes de `sede.env` (no va a Git). Es el que se monta; `postgresql.conf` apunta a él (`hba_file`). |
| `01_esquema.sql` | Tabla `inventario` de la web (base `DB_NAME`). |
| `02_datos.sql` | Sus 20 filas. |
| `03_usuario_web.sh` | Usuario de la web (`DB_USER`): leer, insertar y editar `inventario`, pero no borrar. |
| `04_bifi.sh` | Base `bifi` (UTF-8, `es_ES.UTF-8`), usuarios `panel` y `resp_demo`, sus límites y permisos. Idempotente. |
| `pruebas/probar.sh` | Pruebas P1, P2, P4–P8 y qué IP ve el gestor. `sudo ./db/pruebas/probar.sh parada` añade la de `stop_grace_period`. |
| `cliente/configurar-cliente.sh` | Crea `~/.pg_service.conf` y `~/.pgpass` (600) para `psql service=bifi` en el equipo de quien lo lanza. Admite la base y el usuario como argumentos. |

## Bases y usuarios

| Usuario | Para qué | Desde dónde entra (pg_hba.conf) | A qué base (CONNECT) | Límites |
|---|---|---|---|---|
| `postgres` | Administrador. Dueño de todo. | **Solo** por socket dentro del contenedor, como usuario `postgres` del sistema (`peer`). Por red, nunca (P2). | todas | — |
| `DB_USER` (de `.env`) | La web (`mi-apache`) | Redes de Compose, con contraseña | solo `DB_NAME` | `SELECT`, `INSERT`, `UPDATE` en `inventario`; sin `DELETE` |
| `BIFI_PANEL_USER` (`panel`) | El panel del BIFI (P1) | Redes de Compose, con contraseña | solo `BIFI_DB` (`bifi`) | 10 conexiones, consultas de 5 s como máximo |
| `BIFI_RESP_USER` (`resp_demo`) | Un responsable de proyecto (P3) | Equipos del aula, con contraseña | solo `BIFI_DB` (`bifi`) | 2 conexiones, consultas de 5 s como máximo |

Ninguno de los tres es superusuario ni puede crear bases ni usuarios (`04_bifi.sh`: `NOSUPERUSER NOCREATEDB
NOCREATEROLE`). Por defecto PostgreSQL deja conectar a cualquier usuario a cualquier base (`PUBLIC` tiene
`CONNECT`); `04_bifi.sh` lo quita y lo da solo a quien le toca. Por eso `pg_hba.conf` y los permisos se
complementan: aunque una línea de `pg_hba.conf` deje pasar a alguien, si no tiene `CONNECT` sobre la base,
no entra (`User does not have CONNECT privilege`).

## Cuándo se ejecuta cada cosa

1. **Primer arranque (volumen vacío).** La imagen crea el clúster, el administrador y la base `DB_NAME`, y
   ejecuta por orden alfabético los `.sql` y `.sh` de esta carpeta: `01` → `02` → `03` → `04`. Las
   subcarpetas (`conf/`, `cliente/`, `pruebas/`) y el resto de ficheros los ignora.
   **Cuidado:** cualquier `.sh` que se deje suelto en la raíz de `db/` también se ejecuta al crear la base.
   Por eso las pruebas están en `db/pruebas/` y no aquí.
2. **Arranques siguientes.** Ya hay datos: no se ejecuta nada de lo anterior.
3. **Cada `sudo ./instalar.sh`** (fase `web`, o sola con `sudo ./instalar.sh bd`) repite `04_bifi.sh`:

       docker exec -u postgres mi-postgres bash /docker-entrypoint-initdb.d/04_bifi.sh

   Crea lo que falte y vuelve a fijar contraseñas, límites y permisos. Si cambias una contraseña de `bifi`
   en `.env`, se aplica así. Después instala `psql` en el servidor y prepara `psql service=bifi` (ver P8).

## postgresql.conf, parámetro a parámetro

Lo que no está en el fichero toma el valor por defecto de PostgreSQL 16.

| Parámetro | Valor | Por qué |
|---|---|---|
| `listen_addresses` | `'*'` | Escucha en todas las interfaces **del contenedor**: red frontal, red trasera y loopback. Con `localhost` solo atendería dentro del contenedor y ni la web podría entrar. Quién entra lo decide `pg_hba.conf`, no esto. |
| `port` | `5432` | El puerto estándar. `compose.yaml` publica `5432:5432` en el servidor. |
| `hba_file` | `/etc/postgresql/pg_hba.conf` | Así el `pg_hba.conf` que se usa es el de `db/conf/` y no el que `initdb` deja dentro del volumen de datos. |
| `max_connections` | `50` | (P5) Conexiones simultáneas de todo el servidor. El valor por defecto es 100; con dos aplicaciones y un responsable sobran 50, y cada conexión reserva memoria. |
| `superuser_reserved_connections` | `3` | De esas 50, 3 quedan siempre para el administrador: si una aplicación agota las conexiones, `postgres` aún puede entrar a ver qué pasa. |
| `password_encryption` | `'scram-sha-256'` | Cómo se guardan las contraseñas. Es el valor por defecto en la 16; se deja escrito porque las líneas de `pg_hba.conf` piden `scram-sha-256`, y una contraseña guardada en `md5` no valdría. |
| `log_connections` | `on` | Cada conexión deja en el registro **desde qué IP** llega y qué línea de `pg_hba.conf` la autorizó. Es lo que demuestra qué IP ve el gestor. |
| `log_disconnections` | `on` | Cada desconexión, con la duración de la sesión. |
| `log_line_prefix` | `'%m [%p] %q%u@%d '` | Delante de cada línea: fecha con milisegundos, número de proceso y `usuario@base`. |
| `log_timezone`, `timezone` | `'Europe/Madrid'` | Sin esto la imagen usa UTC y las horas del registro y de `now()` no cuadran con las del aula. |

Los otros límites van **por usuario**, en `04_bifi.sh`:

| Orden | Para qué |
|---|---|
| `ALTER ROLE … CONNECTION LIMIT 10` / `2` | (P5) Conexiones simultáneas de `panel` y `resp_demo`. La siguiente da `too many connections for role`. |
| `ALTER ROLE … SET statement_timeout = '5s'` | (P6) Una consulta de esos usuarios que pase de 5 s se cancela (`canceling statement due to statement timeout`). No va en `postgresql.conf` porque afectaría también al administrador (copias de seguridad, mantenimiento); la documentación de PostgreSQL desaconseja ponerlo para todos. |

Para ver los valores en marcha:

    docker exec -u postgres mi-postgres psql -c "SELECT name, setting FROM pg_settings WHERE source = 'configuration file'"
    docker exec -u postgres mi-postgres psql -c "SELECT rolname, rolconnlimit, rolconfig FROM pg_roles WHERE rolname IN ('panel','resp_demo')"

## pg_hba.conf, línea a línea

PostgreSQL lee de arriba abajo y aplica **la primera línea que coincide** (tipo de conexión, base, usuario y
dirección); no sigue mirando. Si la primera que coincide es `reject`, la conexión se corta aunque la
contraseña sea buena. Si no coincide ninguna, también se rechaza; la última línea lo deja escrito.

El fichero que usa PostgreSQL (`db/conf/pg_hba.conf`) lo genera `instalar.sh` desde `db/conf/pg_hba.conf.tpl`:
pone los nombres de `.env` en las líneas 4 y 6, y escribe la línea 6 una vez por cada red de `REDES_AULA`.
Para verlo tal como queda: `cat db/conf/pg_hba.conf` en el servidor, o
`docker exec -u postgres mi-postgres psql -c "SELECT line_number, database, user_name, address, auth_method FROM pg_hba_file_rules"`.

Dos palabras que aparecen en la columna de dirección:
- `samenet`: cualquier dirección de las redes a las que está conectado el contenedor, es decir, las dos
  redes de Compose (`frontal` y `trasera`). No hace falta escribir sus rangos (Docker los elige al crear
  las redes); se ven con `docker network inspect`.
- `all`: cualquier IP, IPv4 o IPv6.

| # | Línea | Quién y desde dónde | Qué pasa |
|---|---|---|---|
| 1 | `local all postgres peer` | El administrador por el socket, dentro del contenedor | Entra si el usuario del sistema también es `postgres` (`docker exec -u postgres`). Así entran los scripts de `db/` al iniciar. Como `root` dentro del contenedor: `Peer authentication failed`. |
| 2 | `local all all scram-sha-256` | Cualquier otro usuario por el socket | Con contraseña. Es lo que usa `instalar.sh verificar` para probar que la web no puede borrar. |
| 3 | `host all postgres all reject` | **P2.** El administrador por red, desde cualquier IP | Rechazado siempre, venga de Compose, del aula o del propio servidor. Va antes que las líneas 4 y 5 para que no le sirvan. |
| 4 | `host bifi panel samenet scram-sha-256` | **P1.** El usuario `panel` a la base `bifi`, desde Compose | Entra con contraseña. |
| 5 | `host all all samenet scram-sha-256` | Cualquier usuario desde Compose (la web con `DB_USER`, cuyo nombre sale de `.env`) | Entra con contraseña, pero solo en las bases donde tiene `CONNECT`. |
| 6 | `host bifi resp_demo 192.168.6.0/24 scram-sha-256` (y `192.168.8.0/24`, `192.168.2.0/24`) | **P3.** El responsable a `bifi`, desde los equipos del aula | Entra con contraseña. Una línea por cada red de `REDES_AULA` en `sede.env`: si cambian las redes, se cambian allí y `sudo ./instalar.sh bd` regenera el fichero. |
| 7 | `host all all all reject` | **P4.** Todo lo demás | Rechazado: `panel` o la web desde el aula, `resp_demo` a otra base o desde fuera del aula, cualquier usuario inventado… |

Para cambiar las reglas se edita la **plantilla** (`pg_hba.conf.tpl`), no el fichero generado, y se lanza
`sudo ./instalar.sh bd`: lo regenera y hace que PostgreSQL lo vuelva a leer (`pg_reload_conf()`, sin
reiniciar). Para `postgresql.conf`, después de editarlo:

    docker exec -u postgres mi-postgres psql -c "SELECT pg_reload_conf()"

Los dos ficheros se montan uno a uno. `instalar.sh` escribe encima del mismo fichero, así que el contenedor
ve el cambio. Algunos editores, en cambio, guardan creando un fichero nuevo y el contenedor sigue viendo el
antiguo. Si tras recargar no cambia nada: `docker exec mi-postgres cat /etc/postgresql/pg_hba.conf` para
comprobarlo, y `docker compose up -d --force-recreate db` para que lo vuelva a montar.

El registro dice qué línea autorizó cada conexión, por ejemplo
`connection authenticated: identity="resp_demo" method=scram-sha-256 (/etc/postgresql/pg_hba.conf:35)`.

## Qué IP ve el gestor

PostgreSQL decide con la IP **de origen** que le llega. Esa IP depende de por dónde viaja la conexión. Se
ve en el propio gestor con `SELECT inet_client_addr()` y en el registro (`connection received: host=…`).
`db/pruebas/probar.sh` la mide en las tres situaciones.

| Desde dónde | IP que ve el gestor | Por qué | Línea de pg_hba.conf |
|---|---|---|---|
| **Compose** (el panel, la web) | La IP del contenedor en la red compartida, p. ej. `172.19.0.4` | Los contenedores hablan directamente por la red de Docker: no hay NAT. Como `db` está en `frontal` y en `trasera`, el DNS de Docker puede devolver la IP de cualquiera de las dos; las dos son `samenet`. | 4 o 5 |
| **Otro equipo del aula** | La IP real de ese equipo, p. ej. `192.168.6.50` | El puerto publicado (`5432:5432`) funciona con una regla DNAT de iptables: cambia el **destino** (de `192.168.6.105:5432` a la IP del contenedor) pero no el **origen**. | 6 o 7 |
| **El propio servidor, a su IP del aula** (`psql -h 192.168.6.105`) | `192.168.6.105`, la IP del servidor en el aula | Es una conexión que sale del servidor hacia su propia IP: Docker le aplica el mismo DNAT y el origen sigue siendo `192.168.6.105`. Para el gestor es un equipo más del aula. | 6 o 7 |
| **El propio servidor, a `127.0.0.1`** (`psql -h localhost`) | La puerta de enlace de la red `frontal`, p. ej. `172.18.0.1` | Docker no aplica DNAT al loopback: la atiende el proceso `docker-proxy`, que abre otra conexión hacia el contenedor desde el lado del servidor. | 5 (es `samenet`) |
| **Dentro del propio contenedor** (`docker exec … psql`) | Socket: ninguna IP (`inet_client_addr()` da vacío). Con `-h 127.0.0.1`: `127.0.0.1` | No sale del contenedor. | 1 o 2 (socket) |

Consecuencia que hay que saber explicar: conectando a `localhost` desde el servidor, el gestor cree que
viene de Compose (línea 5). Aun así **el administrador no entra** (la línea 3 va antes) y cada usuario solo
abre las bases donde tiene `CONNECT`. Las IPs de ejemplo (`172.18…`, `172.19…`) son las que Docker suele dar
en una VM limpia; las reales de vuestra VM las imprime `db/pruebas/probar.sh`. El comportamiento de las filas 3 y 4
es el de Docker con su configuración por defecto (iptables y `userland-proxy` activados).

## P8 · `psql service=bifi` con `.pgpass`

En vez de escribir servidor, puerto, base, usuario y contraseña cada vez:

- `~/.pg_service.conf` define el servicio `bifi` (sin contraseña):

      [bifi]
      host=192.168.6.105
      port=5432
      dbname=bifi
      user=resp_demo

- `~/.pgpass` guarda la contraseña, una línea por conexión: `servidor:puerto:base:usuario:contraseña`
  (en la contraseña, `:` y `\` se escriben `\:` y `\\`). **psql lo ignora si los permisos no son `600`**
  (`WARNING: password file … has group or world access`).

Los dos ficheros están en la carpeta personal de cada usuario, **fuera del repositorio** (`.gitignore`
además los excluye por si alguien los copia dentro). Los crea `db/cliente/configurar-cliente.sh`:

- En el servidor, `instalar.sh` lo ejecuta para quien lanzó `sudo`, con `BIFI_DB`, `BIFI_RESP_USER` y la
  contraseña de `.env`.
- En el equipo del responsable (Linux): `bash configurar-cliente.sh 192.168.6.105` (o
  `bash configurar-cliente.sh 192.168.6.105 <BIFI_DB> <BIFI_RESP_USER>` si en `.env` hay otros nombres) y
  escribe la contraseña. El servicio se llama igual que la base.
- En Windows los ficheros son `%APPDATA%\postgresql\pgpass.conf` y `%APPDATA%\postgresql\.pg_service.conf`,
  con el mismo contenido.

Luego: `psql service=bifi` entra sin preguntar nada.

## `stop_grace_period`: decidido y probado

Al parar un contenedor (`docker compose stop`, `down`, reinicio de la VM), Docker manda la señal de parada
y espera `stop_grace_period`; si el proceso no ha terminado, lo mata con `SIGKILL`.

- La imagen de PostgreSQL usa `SIGINT` como señal de parada: **parada rápida**. PostgreSQL corta las
  sesiones, deshace las transacciones a medias, escribe a disco lo pendiente (checkpoint) y termina limpio.
- Si le llega `SIGKILL` a mitad, no pierde lo confirmado (está en el WAL), pero el siguiente arranque tiene
  que hacer **recuperación**: tarda más y en el registro aparece `database system was not properly shut
  down; automatic recovery in progress`.
- El valor por defecto de Docker son **10 s**. Con una VM lenta y el checkpoint pendiente de hasta 128 MB
  (`shared_buffers` por defecto) puede no bastar.

**Decisión: `stop_grace_period: 60s`** en el servicio `db`. En condiciones normales la parada tarda menos de
un segundo, así que no retrasa nada; los 60 s solo se esperan si de verdad hacen falta. Los demás servicios
no guardan datos a medio escribir y se quedan con los 10 s por defecto.

Para que sirva, nadie debe parar la base con `docker rm -f` o `docker kill` (mandan `SIGKILL` sin esperar).
Por eso `instalar.sh` hace `docker stop` (que respeta los 60 s) antes de borrar contenedores antiguos.

**Prueba** (`sudo ./db/pruebas/probar.sh parada`, o a mano):

```bash
docker inspect -f '{{.Config.StopTimeout}} {{.Config.StopSignal}}' mi-postgres   # 60 SIGINT
time docker compose stop db
docker logs --tail 8 mi-postgres          # received fast shutdown request … database system is shut down
docker compose start db
docker logs --tail 8 mi-postgres          # database system was shut down at …   (arranque limpio)
```

Contraprueba (lo que se evita): `docker kill mi-postgres && docker compose start db` → en el registro
`database system was interrupted` y `database system was not properly shut down; automatic recovery in
progress`.

## Pruebas

`sudo ./db/pruebas/probar.sh` hace todo lo de esta tabla menos P3 (que necesita otro equipo). `sudo ./instalar.sh
verificar` también lo lanza.

| Prueba | Orden | Resultado esperado |
|---|---|---|
| Config. de `db/conf/` | `docker exec -u postgres mi-postgres psql -c "SHOW config_file" -c "SHOW hba_file"` | `/etc/postgresql/postgresql.conf` y `/etc/postgresql/pg_hba.conf` |
| La web sigue | `curl -s -H "Host: www.huesca.empresa.lan" http://localhost/estado.php` | `ESTADO: OK` y `Filas en inventario: 20` |
| P1 | `docker exec panel php /var/www/panel/pruebas/estado-bifi.php` (o «Estado de la base» en el panel, como `cesar`) | `usuario: panel`, `base: bifi` |
| P2 | `docker exec -e PGPASSWORD=… mi-postgres psql -h db -U postgres` | `pg_hba.conf rejects connection for host …, user "postgres"` |
| P3 | Desde **otro equipo del aula**: `psql -h 192.168.6.105 -U resp_demo -d bifi -c "SELECT current_user, inet_client_addr()"` | `resp_demo` y la IP de ese equipo |
| P4 | Desde ese mismo equipo: `psql -h 192.168.6.105 -U panel -d bifi` y `-U resp_demo -d <DB_NAME>` | `pg_hba.conf rejects connection` |
| P5 | Tres `psql service=bifi` a la vez (dos con `SELECT pg_sleep(4)`) | La tercera: `too many connections for role "resp_demo"` |
| P6 | `psql service=bifi -c "SELECT pg_sleep(6)"` | `canceling statement due to statement timeout` |
| P7 | `docker exec -u postgres mi-postgres psql -l` | `bifi \| postgres \| UTF8 \| libc \| es_ES.UTF-8 \| es_ES.UTF-8` |
| P7 (orden) | `docker exec -u postgres mi-postgres psql -d bifi -c "SELECT x FROM (VALUES ('oso'),('ñu'),('nube'),('Ávila')) t(x) ORDER BY x"` | `Ávila, nube, ñu, oso` (con colación `C` saldría `nube, oso, Ávila, ñu`) |
| P8 | `ls -l ~/.pgpass` y `psql service=bifi -c "SELECT current_user"` | `-rw-------` y `resp_demo` sin pedir contraseña |

Comprobaciones de la web (siguen igual):

    docker exec -u postgres mi-postgres psql -d "$DB_NAME" -c "SELECT COUNT(*) FROM inventario"          # 20
    docker exec -e PGPASSWORD="$DB_PASSWORD" mi-postgres psql -U "$DB_USER" -d "$DB_NAME" \
        -c "DELETE FROM inventario WHERE id = 1"                                                     # permission denied

## Volver a empezar desde cero

`01`, `02` y `03` no se repiten si el volumen ya existe. Para recrear la base (borra los datos; vuelven
las 20 filas, `bifi` vacía y los usuarios):

    sudo ./instalar.sh reiniciar bd --si

No uses `docker compose down -v`: borraría también los datos de LDAP y del panel.

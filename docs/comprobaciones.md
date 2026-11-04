# Comprobaciones de la sede Huesca

Cada prueba tiene **la orden**, **la salida esperada** y **dónde mirar si falla**.
Se ejecutan desde la carpeta del proyecto, en el servidor, después de `sudo ./instalar.sh`.

## Preparación (una vez por terminal)

```bash
cd ~/sede                               # la carpeta donde clonaste el proyecto
set -a; source sede.env; source .env; set +a
IP_AULA_SOLO=${IP_AULA%/*}              # 192.168.6.105  (IP_AULA lleva la máscara /24)
```

Estas dos líneas dan los valores que usan las órdenes: `$DOMINIO`, `$IP_AULA_SOLO`, `$DB_NAME`, `$DB_USER`…
Para mirar un registro de un contenedor: `docker logs <contenedor>` (o `docker compose logs <servicio>`).

## Índice de pruebas y dónde mirar si fallan

| Nº | Prueba | Si falla |
|---|---|---|
| 1 | Instalación completa y repetible | La última línea `FALLO ...` de `instalar.sh` dice qué fase; `scripts/` y `instalar.sh` |
| 2 | `compose.yaml` válido y con versión fija | La línea que indica `docker compose config`; `compose.yaml`; `.env` incompleto |
| 3 | Los seis servicios en marcha | `docker logs <contenedor>` del que no esté `running` |
| 4 | La base no se ve desde el aula | `compose.yaml`, servicio `db`: no debe tener `ports:` |
| 5 | Base inicializada con sus filas | `docker compose logs db` y los ficheros de `db/` (`01_esquema.sql`, `02_datos.sql`) |
| 6 | El usuario de la web no puede borrar | `db/03_usuario_web.sh` y `docker compose logs db` |
| 7 | Registro de arranque, conexiones y errores | `compose.yaml` (línea `command:` del servicio `db`) |
| 8 | Copia de seguridad restaurada en otro PostgreSQL | La salida de `pg_dump`; `docker logs pg-temporal` |
| 9 | Los datos sobreviven a un reinicio | Volumen `datos` en `compose.yaml`; `docker volume ls` |
| 10 | La web responde por su nombre | `docker logs mi-apache`; `web/huesca.conf` |
| 11 | Página de estado con el número de filas | `web/www/estado.php`; `docker logs mi-apache` |
| 12 | La intranet exige contraseña | `secretos/intranet.htpasswd` (lo genera la fase `web` desde `.env`); `web/huesca.conf` |
| 13 | BIND responde con autoridad | `docker logs mi-bind9`; `generado/dns/named.conf.local` |
| 14 | El aula resuelve nombres externos | `dns/named.conf.local.tpl` (vista `aula`: `recursion yes`); salida a Internet del servidor |
| 15 | Registros `MX` y `CNAME` | `dns/aula/db.directa.tpl` y `dns/interna/db.directa.tpl` |
| 16 | Transferencia de zona firmada con TSIG | `generado/tsig.conf`; `dns/named.conf.local.tpl` (`allow-transfer`) |
| 17 | El DNS secundario recibe las zonas | `docker logs` del nodo en GNS3; `generado/dns-secundario/named.conf.local` |
| 18 | OpenLDAP responde y conserva los datos | `docker logs ldap`; `ldif/` |
| 19 | LAM responde | `docker logs lam` |
| 20 | Entrega en Git: etiqueta `despliegue` | `git tag -n1`; `git ls-remote --tags origin` |
| 21 | Sin contraseñas ni copias en el repositorio | `.gitignore`; `git ls-files` |

---

## A · Despliegue y contenedores

### 1. Instalación completa y repetible

```bash
sudo ./instalar.sh; echo "código: $?"
sudo ./instalar.sh; echo "código: $?"
```

Salida esperada (las dos veces; entre medias aparecen muchas líneas `OK ...`):

```
=== TODO CORRECTO ===
código: 0
```

Al repetirlo no se pierde ningún dato: ni filas de la base, ni usuarios de LDAP, ni repositorios de Forgejo.

### 2. `compose.yaml` válido y con versión fija

```bash
docker compose config -q && echo bien
grep -n 'image:' compose.yaml
grep -c latest compose.yaml
```

```
bien
26:    image: postgres:16        (el número de línea puede variar)
...    image: codeberg.org/forgejo/forgejo:1.21
...    image: internetsystemsconsortium/bind9:9.18
...    image: osixia/openldap:1.5.0
...    image: ldapaccountmanager/lam:9.0
0
```

Cinco imágenes, todas con etiqueta de versión, y `0` apariciones de `latest`. La imagen de la web
se construye con `web/Dockerfile` (`php:8.2-apache`).

### 3. Los seis servicios en marcha

```bash
docker compose ps --format 'table {{.Service}}\t{{.State}}'
docker inspect -f '{{.State.Health.Status}}' mi-postgres
```

```
SERVICE   STATE
db        running
dns       running
git       running
lam       running
ldap      running
web       running
healthy
```

### 4. La base no se ve desde el aula

```bash
docker port mi-postgres
ss -ltn | grep -c ':5432 '
```

`docker port` no escribe nada (ningún puerto publicado) y `grep -c` escribe:

```
0
```

---

## B · Base de datos

### 5. Base inicializada con sus filas

```bash
docker compose exec -T db psql -U postgres -d "$DB_NAME" -c 'SELECT count(*) FROM inventario'
```

```
 count
-------
    20
(1 row)
```

La inicialización la hace la carpeta `db/` al crear el volumen por primera vez, sin pasos manuales.

### 6. El usuario de la web no puede borrar

```bash
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c 'SELECT count(*) FROM inventario'
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c 'DELETE FROM inventario WHERE id = 1'
```

```
 count
-------
    20
(1 row)

ERROR:  permission denied for table inventario
```

Puede leer, insertar y editar (la web funciona), pero no borrar. El administrador `postgres` es el dueño de la tabla.

### 7. Registro de arranque, conexiones y errores

```bash
docker compose logs db | grep "ready to accept connections"
docker compose logs db | grep "connection authorized"
docker compose exec -T web php -r '@pg_connect("host=db dbname=".getenv("DB_NAME")." user=".getenv("DB_USER")." password=mala");'
docker compose logs db | grep "password authentication failed"
```

Salida esperada (varía la fecha y el número entre corchetes):

```
... LOG:  database system is ready to accept connections
... LOG:  connection authorized: user=<DB_USER> database=<DB_NAME> ...
... FATAL:  password authentication failed for user "<DB_USER>"
```

Con `log_connections=on` también aparece `connection received: host=... port=...` en cada conexión.

### 8. Copia de seguridad restaurada en otro PostgreSQL

```bash
docker compose exec -T db pg_dump -U postgres --no-owner --no-privileges "$DB_NAME" > /tmp/copia.sql
docker run -d --name pg-temporal -e POSTGRES_PASSWORD=temporal postgres:16
sleep 10                                              # el PostgreSQL temporal tarda unos segundos
docker exec pg-temporal createdb -U postgres "$DB_NAME"
docker exec -i pg-temporal psql -q -U postgres -d "$DB_NAME" < /tmp/copia.sql
docker exec pg-temporal psql -U postgres -d "$DB_NAME" -tc 'SELECT count(*) FROM inventario'
docker rm -f pg-temporal && rm /tmp/copia.sql
```

La penúltima orden escribe el mismo número de filas que la base original:

```
    20
```

### 9. Los datos sobreviven a un reinicio

```bash
docker compose exec -T db psql -U postgres -d "$DB_NAME" -c "INSERT INTO inventario (nombre) VALUES ('prueba-persistencia')"
docker compose rm -sf web db && docker compose up -d web
sleep 10
docker compose exec -T db psql -U postgres -d "$DB_NAME" -tc 'SELECT count(*) FROM inventario'
```

```
    21
```

La fila de prueba sigue ahí: el volumen `datos` no se borra al parar y recrear los contenedores.
Para volver a las filas iniciales (esto **sí** borra los datos de la base):

```bash
sudo ./instalar.sh reiniciar bd --si
docker compose exec -T db psql -U postgres -d "$DB_NAME" -tc 'SELECT count(*) FROM inventario'
```

```
    20
```

---

## C · Web

### 10. La web responde por su nombre

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: www.$DOMINIO" "http://$IP_AULA_SOLO/"
```

```
200
```

### 11. Página de estado con el número de filas

```bash
curl -s -H "Host: www.$DOMINIO" "http://$IP_AULA_SOLO/estado.php"
```

```
ESTADO: OK
Servidor web: Apache/2.4.xx (Debian) / PHP 8.2.xx
Base de datos: <DB_NAME> (usuario <DB_USER>)
Filas en inventario: 20
```

(`xx` cambia según la versión de la imagen.) Si la base no responde, la página da código `500` y `ESTADO: ERROR`.

### 12. La intranet exige contraseña

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: intranet.$DOMINIO" "http://$IP_AULA_SOLO/"
curl -s -o /dev/null -w '%{http_code}\n' -u "$INTRANET_USUARIO:$INTRANET_CLAVE" -H "Host: intranet.$DOMINIO" "http://$IP_AULA_SOLO/"
```

```
401
200
```

`401` sin usuario y `200` con las credenciales de `.env`. El fichero de contraseñas no está en el repositorio.

---

## D · DNS

### 13. BIND responde con autoridad

```bash
dig @"$IP_AULA_SOLO" "www.$DOMINIO"
```

Líneas que deben aparecer (el resto cambia):

```
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1
;; ANSWER SECTION:
www.huesca.empresa.lan.         604800  IN  CNAME   servidor.huesca.empresa.lan.
servidor.huesca.empresa.lan.    604800  IN  A       192.168.6.105
```

La bandera `aa` indica respuesta con autoridad. La configuración se valida con:

```bash
docker run --rm -v "$PWD/generado/dns:/etc/bind:ro" --entrypoint named-checkconf \
    internetsystemsconsortium/bind9:9.18 -z /etc/bind/named.conf
```

```
zone huesca.empresa.lan/IN: loaded serial 2026110407     (el serial es la fecha y hora)
zone 2.10.in-addr.arpa/IN: loaded serial 2026110407
zone huesca.empresa.lan/IN: loaded serial 2026110407
```

### 14. El aula resuelve nombres externos

```bash
dig +short @"$IP_AULA_SOLO" example.com
```

Escribe una o más direcciones IP (el servidor reenvía a 8.8.8.8 y 1.1.1.1). Si no escribe nada,
el servidor no tiene salida a Internet o la vista `aula` no tiene la recursión activa.

### 15. Registros `MX` y `CNAME`

```bash
dig +short @"$IP_AULA_SOLO" MX "$DOMINIO"
dig +short @"$IP_AULA_SOLO" CNAME "www.$DOMINIO"
```

```
10 correo.huesca.empresa.lan.
servidor.huesca.empresa.lan.
```

`www` es un alias (`CNAME`) de `servidor`, y el `MX` apunta a `correo`, que es un registro `A`, nunca a un alias.

### 16. Transferencia de zona firmada con TSIG

```bash
dig @127.0.0.1 AXFR "$DOMINIO"                                       # sin clave
dig @127.0.0.1 AXFR "$DOMINIO" -k generado/dns/tsig.conf             # con la clave
```

```
; Transfer failed.
```

```
;; XFR size: 17 records (messages 1, bytes 527)
```

Sin la clave, el servidor rechaza la transferencia. Con ella, entrega la zona completa (el número de registros crece si se añaden nombres).
La clave está en `generado/tsig.conf`, que no va a Git.

### 17. El DNS secundario recibe las zonas

```bash
dig +short @"$IP_DNS_SECUNDARIO" "www.$DOMINIO"
diff <(dig +short @127.0.0.1 SOA "$DOMINIO") <(dig +short @"$IP_DNS_SECUNDARIO" SOA "$DOMINIO") && echo "mismo serial"
```

```
servidor.huesca.empresa.lan.
10.2.0.1
mismo serial
```

Necesita el proyecto de GNS3 arrancado (`sudo ./instalar.sh gns3`) y el puente `br-virtual` activo.

---

## E · Directorio (OpenLDAP y LAM)

### 18. OpenLDAP responde y conserva los datos

```bash
docker exec ldap ldapsearch -x -H ldap://localhost -D "cn=admin,dc=huesca,dc=empresa,dc=lan" \
    -w "$LDAP_ADMIN_PASSWORD" -b "dc=huesca,dc=empresa,dc=lan" -LLL dn | grep -c '^dn:'
```

```
16
```

Son los 14 elementos de `ldif/` más la raíz del directorio y el administrador. Tras repetir `sudo ./instalar.sh`
debe salir el mismo número: la instalación no borra LDAP (solo lo hace `reiniciar ldap --si`).

### 19. LAM responde

```bash
curl -sL -o /dev/null -w '%{http_code}\n' http://localhost:8080/
```

```
200
```

---

## F · Entrega en Git

### 20. Etiqueta `despliegue`

```bash
git tag -n1 despliegue
git ls-remote --tags origin despliegue
```

```
despliegue      Entrega del despliegue
<hash>  refs/tags/despliegue
<hash>  refs/tags/despliegue^{}
```

Las dos líneas finales (la etiqueta y su versión «pelada» `^{}`) indican que es una etiqueta **anotada** y que está publicada en GitHub.

### 21. Sin contraseñas ni copias en el repositorio

```bash
git ls-files | grep -Ei '(^|/)\.env$|htpasswd|dump|tsig|\.zip$'
git ls-files sede.env
git check-ignore .env secretos generado restauracion
```

La primera orden no escribe nada. Las otras dos escriben:

```
sede.env
.env
secretos
generado
restauracion
```

`sede.env` sí está en Git (no tiene secretos y `instalar.sh` lo necesita al clonar); las contraseñas y la clave TSIG, no.

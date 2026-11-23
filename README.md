# Sede Huesca · `huesca.empresa.lan`

Servidor de la sede de Huesca: red, DNS (BIND9), web (Apache + PHP), base de datos (PostgreSQL),
Git (Forgejo), directorio OpenLDAP (con su panel LAM), el panel del BIFI (PHP, login y perfiles) y la red
interna simulada en GNS3. **Todo se despliega con tres órdenes** en una máquina limpia, sin tocar nada a mano.

## Qué necesitas antes

Una máquina **Ubuntu Server recién instalada**, con `sudo` y conexión a Internet. Si no tiene `git`: `sudo apt install -y git`. Docker no hace falta instalarlo: `instalar.sh` lo hace.

## Despliegue: las tres órdenes

```bash
git clone --branch despliegue <url> sede && cd sede   # 1. descarga el proyecto
cp .env.example .env && nano .env                     # 2. escribe las contraseñas
sudo ./instalar.sh                                    # 3. instala todo
docker compose ps                                     # y comprueba que está en marcha
```

| Orden | Qué hace |
|---|---|
| 1 · `git clone ...` | Descarga la rama `despliegue` en la carpeta `sede` y entra en ella. `<url>` es la del repositorio. |
| 2 · `cp .env.example .env && nano .env` | Copia la plantilla de contraseñas y la abre para rellenarla (`.env` no va a Git). |
| 3 · `sudo ./instalar.sh` | Instala y arranca todo, sin pedir nada. Es seguro repetirlo. |
| `docker compose ps` | Muestra los siete servicios; deben estar en `running`. |

### 1. Descargar el proyecto

```bash
git clone --branch despliegue <url> sede && cd sede
```

Descarga la rama `despliegue` (la que tiene todo listo para instalar). Sustituye `<url>` por la dirección del repositorio
(en Forgejo, el botón **Clonar**: HTTP `http://git.huesca.empresa.lan/...` o SSH por el puerto 2222).
Todas las órdenes siguientes se lanzan desde esta carpeta.

### 2. Escribir las contraseñas

```bash
cp .env.example .env && nano .env
```

Copia la plantilla y ábrela para rellenarla. `.env` **no va a Git**: las claves solo existen en el servidor.
**Son obligatorias todas menos las de Active Directory** (las de Active Directory solo hacen falta para la fase `ad`):
si falta alguna, el instalador se detiene y dice cuál.
Escribe cada valor justo después del `=`, sin espacios ni comentarios en la misma línea.

| Variable | Para qué sirve |
|---|---|
| `DB_NAME` | Nombre de la base de la web (tabla `inventario`). Tiene que ser distinto de `BIFI_DB`. |
| `DB_USER` | Usuario con el que entra la **web**: lee, inserta y edita, pero no puede borrar. No puede llamarse `postgres`. |
| `DB_PASSWORD` | Contraseña de ese usuario. |
| `POSTGRES_PASSWORD` | Contraseña del administrador `postgres` (es el dueño de todo; la web no lo usa y no entra por red). |
| `BIFI_DB` | Base del panel del BIFI. En `.env.example`: `bifi` (el nombre que pide la práctica). |
| `BIFI_PANEL_USER`, `BIFI_PANEL_PASSWORD` | Usuario (`panel`) y contraseña con los que el panel entra en `BIFI_DB` desde Compose. |
| `BIFI_RESP_USER`, `BIFI_RESP_PASSWORD` | Usuario (`resp_demo`) y contraseña con los que un responsable entra en `BIFI_DB` desde el aula. |
| `INTRANET_USUARIO` / `INTRANET_CLAVE` | Usuario y contraseña de la intranet. |
| `LDAP_ADMIN_PASSWORD` | Administrador del directorio OpenLDAP (`cn=admin,dc=huesca,dc=empresa,dc=lan`). |
| `LDAP_CONFIG_PASSWORD` | Administrador de la configuración de OpenLDAP. |
| `LAM_PASSWORD` | Contraseña del panel web LAM. |

Guarda con `Ctrl+O`, `Enter` y sal con `Ctrl+X`.

> **Las contraseñas de la base y de LDAP solo se aplican al crearlas.** Si cambias una en `.env` después de instalar,
> los datos existentes siguen con la antigua. Para empezar de cero: `sudo REINICIAR_LDAP=1 ./instalar.sh web` (borra y recrea los datos de LDAP).

> **Si es otra sede:** revisa también `sede.env` (interfaz y IP del aula, puerta de enlace, resolutor, red interna, dominio).
> Es el único sitio donde aparecen esos datos y **sí va a Git** (no tiene secretos); el resto de ficheros los toma de ahí.
> `ip -br addr` te dice el nombre de tu interfaz (`INTERFAZ_AULA`) y su IP (`IP_AULA`).

### 3. Instalar

```bash
sudo ./instalar.sh
```

Lanza todas las fases una detrás de otra. Tarda unos minutos y **no pide nada**.
**Es seguro repetirlo**: cada fase mira primero qué está hecho, solo cambia lo que falta y nunca borra datos
(base de datos, LDAP, Forgejo). Dos ejecuciones a la vez no se pisan: la segunda se niega a empezar.

| Fase | Qué hace |
|---|---|
| `comprobar` | Verifica que `.env` existe y no tiene variables vacías, y que `docker compose` funciona. Si no hay `.env`, lo crea desde la plantilla y se detiene. |
| `red` | IP fija en el aula, puente `br-virtual` de la red interna, reenvío de paquetes y NAT. Solo se aplica sola si la interfaz del aula ya tiene la IP de `sede.env` (así no te corta el acceso); si no, avisa y se lanza a mano con `sudo ./instalar.sh red`. |
| `sistema` | Cortafuegos UFW (22, 53, 80, 2222, 3000), usuarios del equipo con sus claves SSH (`sistema/usuarios/*.pub`) y endurecimiento de `sshd`. |
| `dns` | Genera las zonas desde `dns/*.tpl` y `sede.env`, crea la clave TSIG (una sola vez), valida todo y levanta `mi-bind9` con dos vistas (interna y aula). |
| `gns3` | Instala el servidor GNS3, construye la imagen del DNS secundario (con la clave TSIG) e importa y arranca el proyecto de la red interna. |
| `forgejo` | Prepara Forgejo y su SSH. Si existe `restauracion/forgejo-dump.zip`, restaura los datos de otro Forgejo. |
| `web` | Genera `secretos/intranet.htpasswd` desde `.env`, construye las imágenes (`web`, `db`, `panel`) y levanta `mi-apache`, `mi-postgres`, `forgejo`, `ldap`, `lam` y `panel`. Al final lanza la fase `bd`. No borra datos de LDAP salvo con `REINICIAR_LDAP=1`. |
| `bd` | Repite `db/04_bifi.sh` (base `bifi`, usuarios `panel` y `resp_demo`, límites y permisos; es repetible), instala `psql` en el servidor y deja `psql service=bifi` listo para quien lanzó `sudo` (`~/.pg_service.conf` y `~/.pgpass` en modo 600). |
| `ad` | Sincroniza OpenLDAP → Active Directory: confía en la CA de AD, instala los scripts de `sincronizacion/` y su temporizador, genera `/etc/huesca/`, comprueba LDAPS y `svc-sync`, y hace la primera sincronización. Antes hay que hacer a mano la parte de Windows (ver abajo). En la ejecución completa solo avisa si Windows no está listo; sola (`sudo ./instalar.sh ad`) marca FALLO. |
| `sssd` | Hace que este servidor autentique a los usuarios contra OpenLDAP. |
| `verificar` | Prueba red, contenedores, permisos de la base, SSH de Forgejo, DNS (incluido TSIG y recursión del aula), GNS3, las pruebas HTTP de `web/probar.sh` (también el panel) y las de la base de `db/pruebas/probar.sh` (ASGBD RA2). |
| `reiniciar ldap\|bd --si` | **Solo a mano.** Borra los datos de LDAP o de la base y los crea de nuevo. Sin `--si` no hace nada. |

Una fase suelta se puede lanzar sola: `sudo ./instalar.sh <fase>` (por ejemplo `sudo ./instalar.sh dns`).
El código de las fases largas está en `scripts/` (`gns3.sh`, `forgejo.sh`, `sssd.sh`, `ad.sh`).

**Active Directory (fase `ad`).** OpenLDAP es el directorio principal y Windows Server recibe sus cuentas. La fase `ad` hace todo lo del servidor Linux, pero antes hay que hacer en dc1 (docs/ad-windows.md): crear `svc-sync`, delegarle las OU Investigadores y Visitas y escribir pertenencia en GG-Investigadores y GG-Visitas, instalar la entidad de certificación, y exportar su certificado a `sincronizacion/huesca-ad-ca.cer`. Después se rellena `AD_SYNC_PASSWORD` en `.env` y se lanza `sudo ./instalar.sh ad`. Las cuentas nuevas nacen deshabilitadas en AD hasta fijar su contraseña (`AD_CLAVE_INICIAL` o `sudo cambiar-clave.sh <usuario>`).

**Acceso a PostgreSQL desde fuera (ASGBD RA2).** El puerto 5432 está publicado. Toda la configuración sale de `db/conf/` (`pg_hba.conf` se genera desde su plantilla con los nombres de `.env` y las redes de `sede.env`): el panel entra en `bifi` desde Compose (usuario `panel`), un responsable entra en `bifi` desde un equipo del aula (usuario `resp_demo`), el administrador no entra por red y la última línea de `pg_hba.conf` rechaza todo lo demás. Detalle, IPs que ve el gestor y pruebas: [`db/README.md`](db/README.md). Desde otro equipo del aula: `psql -h <IP_AULA> -U resp_demo -d bifi`.

**Qué se debe ver al terminar:** líneas `OK ...` para cada comprobación y, al final, `=== TODO BIEN TODO CORRECTO Y YO QUE ME ALEGRO ===`.
Si algo falla aparece `FALLO ...` con el motivo y el script termina con `=== HAY COMPROBACIONES FALLIDAS ===`.

### 4. Comprobar que está en marcha

```bash
docker compose ps
```

Deben aparecer los siete servicios en estado `running` (`healthy` en la base de datos):

| Servicio | Contenedor | Puerto |
|---|---|---|
| `web` | `mi-apache` | 80 |
| `db` | `mi-postgres` | 5432 (desde el aula solo `resp_demo` a `bifi`; ver [`db/README.md`](db/README.md)) |
| `git` | `forgejo` | 3000 (web) y 2222 (SSH) |
| `dns` | `mi-bind9` | 53 (red del servidor) |
| `ldap` | `ldap` | 389 y 636 |
| `lam` | `lam` | 8080 |
| `panel` | `panel` | 8081 (y `panel.huesca.empresa.lan` por Apache) |

Si alguno no está en `running`: `docker logs <contenedor>` muestra el motivo y `sudo ./instalar.sh verificar` repite las pruebas.

## Qué se obtiene

Los nombres los resuelve el DNS de la sede (apunta tu equipo a la IP del servidor como DNS):

| Servicio | Dirección | Acceso |
|---|---|---|
| Web pública | `http://www.huesca.empresa.lan` | libre |
| Intranet | `http://intranet.huesca.empresa.lan` | usuario y clave de `INTRANET_USUARIO` / `INTRANET_CLAVE` |
| Git (Forgejo) | `http://git.huesca.empresa.lan` | registro cerrado; las cuentas las crea el administrador |
| GNS3 | `http://gns3.huesca.empresa.lan` | libre dentro de la sede |
| Estado de la web | `http://www.huesca.empresa.lan/estado.php` | libre; muestra si la base responde y cuántas filas tiene |
| LAM (gestión de usuarios LDAP) | `http://<IP_AULA>:8080` | contraseña `LAM_PASSWORD` |
| Panel del BIFI | `http://panel.huesca.empresa.lan` (o `http://<IP_AULA>:8081`) | login con perfiles (usuarios de ejemplo en [`panel/readme.md`](panel/readme.md)) |
| Base `bifi` (PostgreSQL) | `<IP_AULA>:5432` | `psql service=bifi` (usuario `resp_demo`, solo desde el aula) |

Sin DNS configurado se puede probar con `curl -H "Host: www.huesca.empresa.lan" http://localhost/`.

## Cómo viajan las peticiones

```text
 Equipo del aula (192.168.6.x)
   │  navegador: http://panel.huesca.empresa.lan        psql service=bifi (resp_demo)
   │  DNS de la sede (mi-bind9) → 192.168.6.105         │
   ▼                                                    ▼
 Servidor 192.168.6.105 ── :80 ──────────────┐        :5432 (DNAT de Docker: el origen no cambia)
                                              ▼          │
   red "frontal" de Compose            mi-apache          │
                                  (ServerName panel.*)   │
                                              │ proxy     │
                                              ▼          ▼
                                            panel ─────► mi-postgres
                                    (usuario "panel",   pg_hba.conf decide por usuario, base e IP
                                     red "frontal" o    ├─ panel / web desde Compose      → entran
                                     "trasera")         ├─ resp_demo desde el aula a bifi → entra
                                                        ├─ postgres por red              → reject
                                                        └─ todo lo demás                 → reject
```

- `frontal`: red normal de Compose; por ella se publican los puertos (`80`, `5432`, `8081`…).
- `trasera`: red `internal` (sin salida a Internet ni puertos publicados). La base, la web y el panel están
  en las dos.
- La web de la sede (`mi-apache`) usa `DB_USER` sobre `DB_NAME`; el panel usa `panel` sobre `bifi`.

## Comprobar las prácticas

| Práctica | Orden | Qué hace |
|---|---|---|
| ASGBD RA2 · La base abre a clientes de fuera | `sudo ./db/pruebas/probar.sh` (y `sudo ./db/pruebas/probar.sh parada`) | P1, P2, P4–P8, IPs que ve el gestor y `stop_grace_period`. P3 se hace desde otro equipo del aula: [`db/README.md`](db/README.md#pruebas). |
| IAW RA5 · El panel con formularios, login y perfiles | `bash panel/pruebas/probar-panel.sh http://panel.huesca.empresa.lan` | A1–A10 con curl. Cómo enseñar cada una a mano: [`panel/pruebas.md`](panel/pruebas.md). |

`sudo ./instalar.sh verificar` incluye las pruebas de la base y las del panel por Apache.

## Datos de la sede

Se leen de `sede.env`. Valores actuales:

| Dato | Valor |
|---|---|
| Sede / dominio | Huesca / `huesca.empresa.lan` |
| Servidor en el aula | `enp5s0`, `192.168.6.105/24`, puerta `192.168.6.1` |
| Red interna | `10.2.0.0/24` (puente `br-virtual`, servidor `10.2.0.1`, DNS secundario `10.2.0.2`) |
| Equipo de administración | Alvaro, Jaime, Andreas y Diego (claves en `sistema/usuarios/`) |

## Estructura del repositorio

| Carpeta / fichero | Contenido |
|---|---|
| `instalar.sh` | Instalador por fases (lo único que se ejecuta). Las fases largas están en `scripts/`. |
| `scripts/` | `gns3.sh`, `forgejo.sh`, `sssd.sh` y `ad.sh`: las fases que no caben en `instalar.sh`. Además, scripts para recoger evidencias de la base. |
| `compose.yaml` | Todos los contenedores de la sede. Es el único compose. |
| `.env.example` / `.env` | Plantilla de claves / claves reales (no van a Git). |
| `sede.env` | Datos de la sede (sin secretos; va a Git). |
| `db/` | PostgreSQL: imagen, `conf/` (`postgresql.conf` y la plantilla `pg_hba.conf.tpl`), scripts de creación, pruebas (`pruebas/probar.sh`) y cliente (`cliente/`). Ver [`db/README.md`](db/README.md). |
| `panel/` | Panel del BIFI en PHP (login, perfiles, formularios). Ver [`panel/readme.md`](panel/readme.md) y [`panel/pruebas.md`](panel/pruebas.md). |
| `red/`, `dns/`, `gns3/`, `sistema/`, `web/`, `ldif/` | Configuración de cada área, con su propio `README.md` si lo tiene. |
| `forgejo-docker/` | Datos y configuración del contenedor de Forgejo. |
| `docs/` | Bitácora, investigaciones y documentación final del proyecto. |

## Si algo falla

| Síntoma | Qué mirar |
|---|---|
| `ERROR: ejecútalo con sudo` | Lanza `sudo ./instalar.sh`, no `./instalar.sh`. |
| `ERROR: no había .env` / `falta <VARIABLE> en .env` | Rellena `.env` (paso 2) y repite la orden. |
| `AVISO: ... salto la fase red` | La interfaz de `sede.env` no existe o no tiene esa IP. Corrige `INTERFAZ_AULA` / `IP_AULA` y lanza `sudo ./instalar.sh red`. |
| `ERROR: la configuración de BIND no es válida` | Se muestra el motivo justo encima; revisa `sede.env`. El DNS anterior no se toca. |
| Puerto 53 ocupado | El instalador desactiva el *stub* de `systemd-resolved`; si persiste: `sudo ss -lntup \| grep :53`. |
| Un contenedor no arranca | `docker logs mi-apache`, `docker logs mi-postgres`, `docker logs forgejo`, `docker logs mi-bind9`, `docker logs ldap` o `docker logs lam`. |
| `FALLO usuario ... PUEDE borrar` | La base se creó antes de separar el usuario de la web. `sudo ./instalar.sh reiniciar bd --si` la crea de nuevo (borra los datos; vuelven las filas iniciales). |
| `ERROR: falló db/04_bifi.sh` | El motivo sale justo encima. Lo habitual: falta alguna variable `BIFI_*` en `.env`, o la imagen de `db` no se ha reconstruido (`docker compose build db`). |
| `FALLO` en `db/pruebas/probar.sh` | Cada línea dice qué esperaba y qué salió. `docker logs mi-postgres` muestra cada conexión con su IP y la línea de `pg_hba.conf` que se le aplicó. |
| Desde otro equipo `psql` no conecta | `Test-NetConnection <IP_AULA> -Port 5432` (Windows) o `nc -zv <IP_AULA> 5432`. Si conecta pero sale `pg_hba.conf rejects connection`, ese equipo no está en las redes del aula de `db/conf/pg_hba.conf` o el usuario no es `resp_demo`. |
| `FALLO DNS: la transferencia con la clave TSIG falla` | Revisa `generado/tsig.conf` y `docker logs mi-bind9`. Si cambió la clave, `sudo ./instalar.sh gns3` reconstruye el secundario. |
| GNS3 con nodos sin arrancar | `ip -br addr show br-virtual` (debe estar `UP`), `journalctl -u gns3server -n 30` y `/var/log/instalar-gns3.log`. Detalle en `gns3/README.md`. |
| La intranet devuelve 401 | Es lo correcto sin credenciales; con `INTRANET_USUARIO` / `INTRANET_CLAVE` de `.env` debe dar 200. |

Para cualquier duda de una fase concreta, mira el `README.md` de su carpeta.

# Sede Huesca · `huesca.empresa.lan`

Servidor de la sede de Huesca: red, DNS (BIND9), web (Apache + PHP), base de datos (PostgreSQL),
Git (Forgejo) y la red interna simulada en GNS3. **Todo se despliega con tres órdenes** en una máquina
limpia, sin tocar nada a mano.

## Qué necesitas antes

| Requisito | Detalle |
|---|---|
| Máquina | Ubuntu Server recién instalado, con `sudo` y conexión a Internet (descarga imágenes Docker y paquetes). |
| `git` | Viene en Ubuntu Server; si faltara: `sudo apt install -y git`. |
| Docker | No hace falta instalarlo: `instalar.sh` lo instala si no está. |
| Datos de la sede | Los valores de red están en `sede.env` (ver el paso 2). |

## Despliegue: las tres órdenes

```bash
git clone --branch despliegue <url> sede && cd sede
cp .env.example .env && nano .env
sudo ./instalar.sh
```

Después, para comprobar que todo está en marcha:

```bash
docker compose ps
```

### 1. Descargar el proyecto

```bash
git clone --branch despliegue <url> sede && cd sede
```

Descarga la rama `despliegue` (la que tiene todo listo para instalar) en la carpeta `sede` y entra en ella.
Sustituye `<url>` por la dirección del repositorio (en Forgejo, el botón **Clonar**: HTTP
`http://git.huesca.empresa.lan/...` o SSH por el puerto 2222). Todas las órdenes siguientes se lanzan desde esta carpeta.

### 2. Escribir las contraseñas

```bash
cp .env.example .env && nano .env
```

Copia la plantilla y ábrela para rellenarla. `.env` **no va a Git**: las claves solo existen en el servidor.
Rellénalas todas. Las cuatro obligatorias (`DB_NAME`, `DB_PASSWORD`, `INTRANET_USUARIO`, `INTRANET_CLAVE`) las exige el instalador: si falta alguna, se detiene y dice cuál.

| Variable | Para qué sirve |
|---|---|
| `DB_NAME` | Nombre de la base de datos de PostgreSQL. |
| `DB_USER` | Usuario de la aplicación (reservada; hoy `compose.yaml` usa `usuario_app`). |
| `DB_PASSWORD` | Contraseña de ese usuario. |
| `POSTGRES_PASSWORD` | Contraseña del administrador de PostgreSQL (reservada; hoy no se usa). |
| `INTRANET_USUARIO` | Usuario para entrar en la intranet. |
| `INTRANET_CLAVE` | Contraseña de la intranet. |

Guarda con `Ctrl+O`, `Enter` y sal con `Ctrl+X`.

> **Si es otra sede:** revisa también `sede.env` (interfaz y IP del aula, puerta de enlace, resolutor, red interna, dominio).
> Es el único sitio donde aparecen esos datos; el resto de ficheros los toma de ahí.
> `ip -br addr` te dice el nombre de tu interfaz (`INTERFAZ_AULA`) y su IP (`IP_AULA`).

### 3. Instalar

```bash
sudo ./instalar.sh
```

Lanza todas las fases una detrás de otra. Tarda unos minutos y **no pide nada**. Es seguro repetirlo: cada fase mira primero qué está hecho.

| Fase | Qué hace |
|---|---|
| `comprobar` | Verifica que `.env` existe y no tiene variables vacías, y que `docker compose` funciona. Si no hay `.env`, lo crea desde la plantilla y se detiene. |
| `red` | IP fija en el aula, puente `br-virtual` de la red interna, reenvío de paquetes y NAT. Solo se aplica sola si la interfaz del aula ya tiene la IP de `sede.env` (así no te corta el acceso); si no, avisa y se lanza a mano con `sudo ./instalar.sh red`. |
| `sistema` | Cortafuegos UFW (22, 53, 80, 2222, 3000), usuarios del equipo con sus claves SSH (`sistema/usuarios/*.pub`) y endurecimiento de `sshd`. |
| `dns` | Genera las zonas desde `dns/*.tpl` y `sede.env`, las valida y levanta el contenedor `mi-bind9` con dos vistas (interna y aula). |
| `gns3` | Instala el servidor GNS3, construye la imagen del DNS secundario e importa y arranca el proyecto de la red interna. |
| `forgejo` | Prepara Forgejo y su SSH. Si existe `restauracion/forgejo-dump.zip`, restaura los datos de otro Forgejo. |
| `web` | Genera `secretos/intranet.htpasswd` desde `.env` y levanta `mi-apache`, `mi-postgres` y `forgejo`. |
| `verificar` | Prueba red, contenedores, SSH de Forgejo, DNS, GNS3 y las cinco pruebas HTTP de `web/probar.sh`. |

Una fase suelta se puede lanzar sola: `sudo ./instalar.sh <fase>` (por ejemplo `sudo ./instalar.sh dns`).

**Qué se debe ver al terminar:** líneas `OK ...` para cada comprobación y, al final, `=== TODO BIEN TODO CORRECTO Y YO QUE ME ALEGRO ===`.
Si algo falla aparece `FALLO ...` con el motivo y el script termina con `=== HAY COMPROBACIONES FALLIDAS ===`.

### 4. Comprobar que está en marcha

```bash
docker compose ps
```

Deben aparecer los cuatro servicios en estado `running` (`healthy` en la base de datos):

| Servicio | Contenedor | Puerto |
|---|---|---|
| `web` | `mi-apache` | 80 |
| `db` | `mi-postgres` | solo red interna de Docker |
| `git` | `forgejo` | 3000 (web) y 2222 (SSH) |
| `dns` | `mi-bind9` | 53 (red del servidor) |

Si alguno no está en `running`: `docker logs <contenedor>` muestra el motivo y `sudo ./instalar.sh verificar` repite las pruebas.

## Qué se obtiene

Los nombres los resuelve el DNS de la sede (apunta tu equipo a la IP del servidor como DNS):

| Servicio | Dirección | Acceso |
|---|---|---|
| Web pública | `http://www.huesca.empresa.lan` | libre |
| Intranet | `http://intranet.huesca.empresa.lan` | usuario y clave de `INTRANET_USUARIO` / `INTRANET_CLAVE` |
| Git (Forgejo) | `http://git.huesca.empresa.lan` | registro cerrado; las cuentas las crea el administrador |
| GNS3 | `http://gns3.huesca.empresa.lan` | libre dentro de la sede |

Sin DNS configurado se puede probar con `curl -H "Host: www.huesca.empresa.lan" http://localhost/`.

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
| `instalar.sh` | Instalador por fases (lo único que se ejecuta). |
| `compose.yaml` | Todos los contenedores de la sede. Es el único compose. |
| `.env.example` / `.env` | Plantilla de claves / claves reales (no van a Git). |
| `sede.env` | Datos de la sede. |
| `red/`, `dns/`, `gns3/`, `sistema/`, `web/`, `db/` | Configuración de cada área, con su propio `README.md`. |
| `forgejo-docker/` | Datos y configuración del contenedor de Forgejo. |
| `docs/` | Bitácora, investigaciones y documentación final. |

## Si algo falla

| Síntoma | Qué mirar |
|---|---|
| `ERROR: ejecútalo con sudo` | Lanza `sudo ./instalar.sh`, no `./instalar.sh`. |
| `ERROR: no había .env` / `falta <VARIABLE> en .env` | Rellena `.env` (paso 2) y repite la orden. |
| `AVISO: ... salto la fase red` | La interfaz de `sede.env` no existe o no tiene esa IP. Corrige `INTERFAZ_AULA` / `IP_AULA` y lanza `sudo ./instalar.sh red`. |
| `ERROR: la configuración de BIND no es válida` | Se muestra el motivo justo encima; revisa `sede.env`. El DNS anterior no se toca. |
| Puerto 53 ocupado | El instalador desactiva el *stub* de `systemd-resolved`; si persiste: `sudo ss -lntup \| grep :53`. |
| Un contenedor no arranca | `docker logs mi-apache`, `docker logs mi-postgres`, `docker logs forgejo` o `docker logs mi-bind9`. |
| GNS3 con nodos sin arrancar | `ip -br addr show br-virtual` (debe estar `UP`), `journalctl -u gns3server -n 30` y `/var/log/instalar-gns3.log`. Detalle en `gns3/README.md`. |
| La intranet devuelve 401 | Es lo correcto sin credenciales; con `INTRANET_USUARIO` / `INTRANET_CLAVE` de `.env` debe dar 200. |

Para cualquier duda de una fase concreta, mira el `README.md` de su carpeta.

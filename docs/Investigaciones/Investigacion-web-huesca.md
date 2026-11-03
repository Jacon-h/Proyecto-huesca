# 📑 Memoria de Laboratorio Web - Sede Huesca

---

## Parte A · Laboratorio Práctico

### Paso 1 · Qué viaja por el puerto 80

#### 1.1. Análisis de Petición y Respuesta HTTP
* **Petición HTTP:** Es la solicitud en texto plano enviada por el cliente (`curl` o navegador). Contiene el método HTTP (`GET`), la ruta solicitada (`/`), la versión de protocolo (`HTTP/1.1`) y las cabeceras enviadas.
* **Cabecera `Host:`:** Es indispensable en la navegación HTTP/1.1. Especifica el nombre de dominio exacto al que el cliente desea acceder (`Host: example.com`), lo que permite que una sola dirección IP aloje múltiples sitios web distintos (Virtual Hosting por nombre).
* **Respuesta HTTP:** Devuelta por el servidor, contiene la versión del protocolo, el código de estado HTTP (`200 OK`), cabeceras del servidor (`Server`, `Content-Type`) y el cuerpo del mensaje (código HTML/CSS/JS).

```bash
# Inspección de petición y respuesta HTTP completa hacia servidor externo
asir2@asir2:~$ curl -v [http://example.com](http://example.com) 2>&1 | head -30
* Host example.com:80 was resolved.
* Trying 172.66.147.243:80...
* Connected to example.com (172.66.147.243) port 80
> GET / HTTP/1.1
> Host: example.com
> User-Agent: curl/8.18.0
> Accept: */*

< HTTP/1.1 200 OK
< Date: Tue, 22 Sep 2026 08:41:10 GMT
< Content-Type: text/html
< Server: cloudflare
< Last-Modified: Tue, 15 Sep 2026 23:38:37 GMT

# Obtención exclusiva de cabeceras HTTP mediante flag -sI
asir2@asir2:~$ curl -sI [http://example.com](http://example.com)
HTTP/1.1 200 OK
Date: Tue, 22 Sep 2026 08:41:51 GMT
Content-Type: text/html
Connection: keep-alive
Server: cloudflare
Last-Modified: Tue, 15 Sep 2026 23:38:37 GMT

# Petición a la IP de nuestro entorno local comprobando la cabecera del servidor Apache y PHP
asir2@asir2:~$ curl -v [http://192.168.6.105](http://192.168.6.105) 2>&1 | head -20
* Connected to 192.168.6.105 (192.168.6.105) port 80
> GET / HTTP/1.1
> Host: 192.168.6.105
> User-Agent: curl/8.18.0
> Accept: */*

< HTTP/1.1 200 OK
< Date: Tue, 22 Sep 2026 08:42:20 GMT
< Server: Apache/2.4.68 (Debian)
< X-Powered-By: PHP/8.2.23
< Content-Type: text/html; charset=UTF-8

<h1>Web Pública Sede Huesca</h1><p><strong>Versión PostgreSQL:</strong> PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2)</p><p><strong>Filas:</strong> 20</p>
```

#### 1.2. Tabla de Códigos de Estado HTTP para Administración de Sistemas

| Código | Significado | Implicación para administración de sistemas |
| :--- | :--- | :--- |
| **200 OK** | Petición correcta | El recurso existe y ha sido entregado correctamente. |
| **301 Moved Permanently** | Redirección permanente | El recurso cambió de URL; se debe actualizar la configuración o los enlaces. |
| **304 Not Modified** | Contenido en caché | El cliente usa la versión local; ahorra ancho de banda y procesamiento. |
| **401 Unauthorized** | Autenticación requerida | Falta autenticación o las credenciales enviadas en `Authorization` son erróneas. |
| **403 Forbidden** | Acceso denegado | Error de permisos en el sistema de archivos o restricción por directiva (`Require deny`). |
| **404 Not Found** | Recurso no encontrado | La ruta solicitada no existe dentro del `DocumentRoot` especificado. |
| **500 Internal Server Error** | Error interno del servidor | Fallo grave en el backend (error de sintaxis en scripts PHP, mala configuración). |
| **503 Service Unavailable** | Servicio no disponible | El servidor web no puede comunicarse con la base de datos o backend. |

---

### Paso 2 · Levantar Apache

#### 2.1. Conceptos Clave de Configuración
* **Módulos en Apache:** Son componentes dinámicos que extienden las funciones del núcleo de Apache (autenticación, reescritura de URLs, proxy). Se activan mediante la directiva `LoadModule`.
* **Fichero Principal de Configuración:** Ubicado en `/etc/apache2/apache2.conf` en distribuciones Debian/Ubuntu o `/usr/local/apache2/conf/httpd.conf` en imágenes oficiales.
* **Directiva:** Instrucción de configuración individual que establece una regla o parámetro concreto (ej. `DocumentRoot`, `ServerName`, `Listen`).
* **`<Directory>`:** Bloque delimitador que aplica directivas de permisos y seguridad a una ruta física concreta del sistema de archivos.
* **`<VirtualHost>`:** Bloque delimitador que agrupa la configuración completa de un sitio web específico (por IP, puerto o nombre de dominio).

```bash
# Comprobación de estado de los contenedores Docker en ejecución
asir2@asir2:~$ docker ps
CONTAINER ID   IMAGE                 COMMAND                  STATUS         PORTS                  NAMES
6517b2ceab     postgres:16-alpine    "docker-entrypoint.s…"   Up 21 minutes  5432/tcp               mi-postgres
a1b2c3d4e5     proyecto_huesca-web   "docker-php-entrypoi…"   Up 2 hours     0.0.0.0:80->80/tcp     mi-apache

# Comprobación de la versión exacta de Apache en el contenedor
asir2@asir2:~$ sudo docker exec web httpd -v
Server version: Apache/2.4.68 (Unix)
Server built:   Sep 19 2026 00:19:44

# Verificación de respuesta HTTP local
asir2@asir2:~$ curl -s http://localhost:8080
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "[http://www.w3.org/TR/html4/strict.dtd](http://www.w3.org/TR/html4/strict.dtd)">
<html>
<head>
<title>It works! Apache httpd</title>
</head>
<body>
<p>It works!</p>
</body>
</html>

# Listado de módulos de Apache cargados en memoria
asir2@asir2:~$ sudo docker exec web httpd -M | head -20
Loaded Modules:
 core_module (static)
 so_module (static)
 http_module (static)
 mpm_event_module (shared)
 authn_file_module (shared)
 authn_core_module (shared)
 authz_host_module (shared)
 authz_groupfile_module (shared)
 authz_user_module (shared)
 authz_core_module (shared)
 access_compat_module (shared)
 auth_basic_module (shared)
 reqtimeout_module (shared)
 filter_module (shared)
 mime_module (shared)
 log_config_module (shared)
 env_module (shared)
 headers_module (shared)
 setenvif_module (shared)

# Verificación de la identidad del usuario que ejecuta el proceso en el contenedor
asir2@asir2:~$ sudo docker exec web id
uid=0(root) gid=0(root) groups=0(root)
```

#### 2.2. Gestión de Registros en Contenedores
En entornos Dockerized, Apache redirige sus registros de acceso (`access_log`) y errores (`error_log`) hacia los flujos estándar `stdout` y `stderr`. Para consultar las últimas entradas desde el host se utiliza:

```bash
docker logs --tail 20 mi-apache
```

---

### Paso 3 · Gestión de Contenido y Volúmenes

#### 3.1. Análisis de Permisos y Seguridad
* **Uso del modificador `:ro` (Read-Only):** Al realizar el montaje de volúmenes con `-v ~/lab-web/publica:/var/www/html:ro`, el contenedor solo obtiene permisos de lectura. Si el servidor web sufre un compromiso de seguridad, el atacante no podrá alterar, inyectar ni borrar archivos del sistema de archivos local.
* **Propietarios y Permisos:**
  * **En el Host:** Los archivos pertenecen al usuario del sistema (`asir2`, UID 1000).
  * **En el Contenedor:** El proceso Apache se ejecuta como `www-data` (o `root`).
  * **Regla de acceso:** Para que el servicio sirva los archivos correctamente, estos deben contar con permisos globales de lectura (`644` para archivos y `755` para directorios).

```bash
# Intento de creación de archivo en el volumen montado con la bandera de solo lectura (:ro)
asir2@asir2:~/proyecto_huesca$ sudo docker exec -it mi-apache touch /var/www/html/publica/x.html
touch: cannot create '/var/www/html/publica/x.html': Read-only file system
```

---

### Paso 4 · Alojamiento Virtual (VirtualHosts)

```bash
# Verificación de la estructura de VirtualHosts en Apache
asir2@asir2:~$ sudo docker exec mi-apache apache2ctl -S
VirtualHost configuration:
*:80                    is a NameVirtualHost
 default server www.huesca.empresa.lan (/etc/apache2/sites-enabled/000-default.conf:1)
 port 80 namevhost www.huesca.empresa.lan (/etc/apache2/sites-enabled/000-default.conf:1)
 port 80 namevhost intranet.huesca.empresa.lan (/etc/apache2/sites-enabled/000-default.conf:11)
ServerRoot: "/etc/apache2"
Main DocumentRoot: "/var/www/html"

# Prueba de petición enviando una cabecera Host no registrada (Host no coincidente)
asir2@asir2:~$ curl -s -H 'Host: cualquier.otra.cosa' [http://192.168.6.105](http://192.168.6.105)
<h1>Web Pública Sede Huesca</h1><p><strong>Versión PostgreSQL:</strong> PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2)</p><p><strong>Filas:</strong> 20</p>

# Inspección de las directivas de permisos del directorio raíz web en apache2.conf
asir2@asir2:~$ sudo docker exec mi-apache grep -A4 '<Directory /var/www/>' /etc/apache2/apache2.conf
<Directory /var/www/>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
```

#### 4.1. Funcionamiento de VirtualHosts
* **Prueba con `Host` no coincidente (`curl -H "Host: cualquier.otra.cosa"`):** Cuando la cabecera `Host:` recibida no coincide con ningún `ServerName` o `ServerAlias` configurado, Apache redirige la solicitud al **primer VirtualHost cargado en memoria**, que actúa como VirtualHost por defecto (`www.huesca.empresa.lan`).
* **`ServerName` vs `ServerAlias`:** `ServerName` especifica el dominio principal del sitio web, mientras que `ServerAlias` define nombres adicionales o secundarios que apuntarán al mismo sitio.

#### 4.2. Relación entre DNS (BIND9) y Apache
* **BIND9 (DNS):** Traduce los nombres `www.huesca.empresa.lan` e `intranet.huesca.empresa.lan` a la dirección IP correspondiente (`192.168.6.105`). Si falla el DNS, la petición ni siquiera llega al servidor (error de resolución).
* **Apache:** Recibe la petición en el puerto 80 e inspecciona la cabecera HTTP `Host:` para servir la carpeta adecuada. Si falla Apache, la IP conecta pero devuelve un error HTTP o el sitio incorrecto.

#### 4.3. Qué pasa si falta el bloque `<Directory>` — comprobado

Se comentó el bloque completo `<Directory /var/www/html/intranet> ... </Directory>` (las seis líneas, no solo apertura y cierre — comentar solo los extremos deja las directivas de dentro sueltas en el `<VirtualHost>` y Apache rechaza la recarga con `AuthType not allowed in <VirtualHost> context`), se validó con `apache2ctl configtest` y se recargó con `apache2ctl graceful`:

```bash
asir2@asir2:~/proyecto_huesca$ sudo docker exec mi-apache apache2ctl graceful
[Wed Sep 23 07:01:02.762678 2026] [mpm_prefork:notice] AH00171: Graceful restart requested, doing restart

asir2@asir2:~/proyecto_huesca$ curl -i -H "Host: intranet.huesca.empresa.lan" http://192.168.6.105
HTTP/1.1 200 OK
Date: Wed, 23 Sep 2026 07:01:02 GMT
Server: Apache/2.4.68 (Debian)
Last-Modified: Mon, 21 Sep 2026 09:52:40 GMT
ETag: "32-65bfb35f2c885"
Content-Length: 50
Content-Type: text/html

<h1>Intranet Sede Huesca – Acceso Autorizado</h1>
```

**Resultado real: `200 OK`, sin pedir credenciales — la intranet queda completamente abierta.** No es un `403 Forbidden` como cabría esperar del bloque `<Directory />` de la raíz. El motivo, comprobado en `apache2.conf`:

```apache
<Directory /var/www/>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
```

Debian trae, además del `<Directory />` restrictivo, un segundo bloque para `/var/www/` con `Require all granted`. Como `DocumentRoot /var/www/html/intranet` cuelga de esa ruta, **hereda el permiso abierto de `/var/www/`, no la denegación de la raíz**. Sin el `<Directory>` propio del sitio (el que trae `AuthType Basic` y `Require valid-user`), Apache no falla "cerrado" — falla **abierto**: sirve el contenido sin ningún control. Es un hallazgo relevante para la sede: toda la protección de la intranet depende exclusivamente de que ese bloque exista; si desaparece por error humano, nadie recibe un 403 que avise del fallo — el contenido queda accesible sin más, y solo se detecta si alguien revisa el registro o nota la ausencia del prompt de usuario/contraseña.

Restaurado el bloque y repetida la petición, la intranet vuelve a proteger correctamente:

```bash
asir2@asir2:~/proyecto_huesca$ curl -i -u usuario_intranet:asir2 -H "Host: intranet.huesca.empresa.lan" http://192.168.6.105
```
```
intranet.huesca.empresa.lan:80 192.168.6.105 - usuario_intranet [23/Sep/2026:07:02:06 +0000] "GET / HTTP/1.1" 200 277
```
(línea de `docker logs`: la petición autenticada como `usuario_intranet` recibe `200`, confirmando que la autenticación básica ha vuelto a aplicarse).

#### 4.4. Por qué se optó por una imagen propia y no por `docker exec ... >> httpd.conf`

El `docker exec ... echo >> httpd.conf` es una trampa deliberada del enunciado: el cambio sobrevive a un `restart` (el contenedor sigue vivo, con su capa de escritura intacta) pero desaparece en cuanto se hace `docker rm` y se vuelve a crear el contenedor desde la imagen original, porque esa capa de escritura se pierde. En este proyecto se optó por **construir una imagen propia mediante `Dockerfile`** que copia la configuración de los VirtualHosts dentro de la imagen (en vez de montar un `httpd.conf`/`apache2.conf` completo por volumen), de modo que la configuración queda versionada en el repositorio y cualquier `docker compose up --build` reconstruye el contenedor con ella ya incluida, sin pasos manuales que se pierdan al recrear el contenedor.

---

### Paso 5 · Autenticación y Control de Acceso

```bash
# Petición a la Intranet sin autenticación obteniendo un error HTTP 401 Unauthorized
asir2@asir2:~$ curl -s -H 'Host: intranet.huesca.empresa.lan' [http://192.168.6.105](http://192.168.6.105)
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "[http://www.w3.org/TR/html4/strict.dtd](http://www.w3.org/TR/html4/strict.dtd)">
<html><head>
<title>401 Unauthorized</title>
</head><body>
<h1>Unauthorized</h1>
<p>This server could not verify that you are authorized to access the document requested...</p>
<hr>
<address>Apache/2.4.68 (Debian) Server at intranet.huesca.empresa.lan Port 80</address>
</body></html>

# Petición enviando credenciales incorrectas mediante el parámetro -u
asir2@asir2:~/proyecto_huesca$ curl -si -H 'Host: intranet.huesca.empresa.lan' -u alumno:claveincorrecta [http://192.168.6.105](http://192.168.6.105) | head -5
HTTP/1.1 401 Unauthorized
Date: Tue, 22 Sep 2026 10:08:23 GMT
Server: Apache/2.4.68 (Debian)
WWW-Authenticate: Basic realm="Acceso Restringido Intranet Huesca"
Content-Length: 514

# Intercepción de la cabecera de autorización enviada en la petición HTTP
asir2@asir2:~/proyecto_huesca$ curl -v -H 'Host: intranet.huesca.empresa.lan' -u alumno:unaclave [http://192.168.6.105](http://192.168.6.105) 2>&1 | grep -i authorization
> Authorization: Basic YWx1bW5v0nVuYWNsYXZl

# Decodificación del hash Base64 revelando las credenciales en texto plano
asir2@asir2:~/proyecto_huesca$ echo YWx1bW5v0nVuYWNsYXZl | base64 -d
alumno:unaclave
```

#### 5.1. Análisis de Seguridad e Identidad
* **Riesgo de la Autenticación Básica HTTP:** En HTTP Basic Auth, el cliente envía las credenciales codificadas en Base64 en la cabecera `Authorization: Basic`. Como Base64 es una codificación y no un cifrado, cualquiera que intercepte el tráfico puede recuperar el usuario y la contraseña en texto plano (`alumno:unaclave`). Para ser seguro, requiere obligatoriamente HTTPS.
* **Ubicación de `.htpasswd` y `.gitignore`:** El archivo `.htpasswd` debe ubicarse **fuera del `DocumentRoot`** para evitar que se pueda descargar directamente desde el navegador. Además, debe añadirse al `.gitignore` para no subir hashes de contraseñas al repositorio Git.
* **Autenticación vs Autorización:**
  * **Autenticación (`AuthType Basic`, `AuthUserFile`):** Identifica quién es el usuario solicitante.
  * **Autorización (`Require valid-user`):** Determina si el usuario autenticado tiene permisos para acceder al recurso protegido.

---

### Paso 6 · Ejecución PHP y Conexión a Base de Datos

```bash
# Verificación de la conexión exitosa entre PHP y PostgreSQL desde la web pública
asir2@asir2:~$ curl -s -H 'Host: www.huesca.empresa.lan' [http://192.168.6.105](http://192.168.6.105)
<h1>Web Pública Sede Huesca</h1><p><strong>Versión PostgreSQL:</strong> PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit</p><p><strong>Filas:</strong> 20</p>
```

#### 6.1. Diagrama de Flujo de la Petición

```mermaid
graph TD
    A[Navegador / Cliente Curl] -->|1. Petición HTTP puerto 80| B[Apache - Contenedor mi-apache]
    B -->|2. Procesa script PHP| C[Módulo PHP]
    C -->|3. Driver pdo_pgsql| D[Red Interna Docker]
    D -->|4. Conexión TCP puerto 5432| E[PostgreSQL - Contenedor mi-postgres]
    E -->|5. Retorna 20 filas inventario| C
    C -->|6. Genera HTML dinámico| B
    B -->|7. Respuesta HTTP 200 OK| A
```

```bash
# Consulta de logs de acceso en tiempo real desde Docker
asir2@asir2:~/proyecto_huesca$ sudo docker logs --tail 5 mi-apache
www.huesca.empresa.lan:80 192.168.6.105 - - [22/Sep/2026:08:55:18 +0000] "GET / HTTP/1.1" 200 426 "-" "curl/8.18.0"
```

#### 6.2. Tres decisiones sobre la conexión con la base de datos

**a) Por qué hace falta una imagen propia y no vale `php:8.3-apache` tal cual**
La imagen oficial `php:8.3-apache` trae el intérprete de PHP y el módulo `mod_php` integrados, pero **no incluye la extensión `pdo_pgsql`**: sin ella, `new PDO('pgsql:...')` lanza `could not find driver`. Hace falta el `Dockerfile` del enunciado (instalar `libpq-dev` y ejecutar `docker-php-ext-install pdo_pgsql`) para que el intérprete sepa hablar con PostgreSQL. Es una decisión de imagen, no de configuración de Apache.

**b) De dónde salen las credenciales y por qué no van en el código ni en el repositorio**
Las credenciales (`DB_NOMBRE`, `DB_USUARIO`, `DB_CLAVE`) se inyectan como variables de entorno definidas en un fichero `.env`, que **no se sube al repositorio** (se añade a `.gitignore`) y del que solo se versiona un `.env.example` sin la clave real. `estado.php` las lee con `getenv()` en tiempo de ejecución. Meterlas directamente en el código o en `sitios.conf` las expondría a quien tenga acceso de lectura al repositorio o a `DocumentRoot`, y obligaría a tocar código para rotarlas; con variables de entorno se cambian sin recompilar ni redesplegar el PHP.

**c) Qué ve el usuario cuando la base de datos cae, y dónde queda el detalle del error — comprobado**

```bash
asir2@asir2:~/proyecto_huesca$ sudo docker compose stop mi-postgres
Container mi-postgres  Stopped

asir2@asir2:~/proyecto_huesca$ curl -i -H "Host: www.huesca.empresa.lan" http://192.168.6.105
HTTP/1.1 200 OK
Date: Wed, 23 Sep 2026 07:02:19 GMT
Server: Apache/2.4.68 (Debian)
X-Powered-By: PHP/8.2.33
Content-Length: 266
Content-Type: text/html; charset=UTF-8

<br />
<b>Warning</b>:  pg_connect(): Unable to connect to PostgreSQL server: could not
translate host name "mi-postgres" to address: Name or service not known in
<b>/var/www/html/publica/index.php</b> on line <b>9</b><br />
Error de conexión a Postgres
```

**Resultado real, distinto de lo esperado según el enunciado: `200 OK`, no `503`.** El código de la sede usa `pg_connect()` (no PDO con `try/catch`), así que un fallo de conexión no lanza excepción: la función devuelve `false`, PHP emite un *warning* y el script continúa — Apache no tiene ninguna señal para marcar la respuesta como error, y responde `200`. Además, con `display_errors` activo, **el warning se imprime en el propio HTML**, revelando al cliente la ruta interna del servidor (`/var/www/html/publica/index.php`) y la línea exacta del fallo — justo el tipo de detalle técnico que el enunciado pide no filtrar.

Vuelto a levantar el contenedor, el servicio se recupera solo, sin intervención adicional:

```bash
asir2@asir2:~/proyecto_huesca$ sudo docker compose start mi-postgres
Container mi-postgres  Started
```

**Mejora detectada y recomendada:** sustituir `pg_connect()` por PDO con `try/catch` (como especifica el enunciado), forzar `http_response_code(503)` en el `catch`, devolver al cliente solo un mensaje genérico (`<h1>Sin base de datos</h1>`) y desactivar `display_errors` en producción (`display_errors = Off` en `php.ini`, dejando el detalle real solo en `error_log`). Mientras no se corrija, cualquier caída de PostgreSQL expone en pantalla la estructura de directorios interna del servidor.

---

### Paso 7 · Registros de Auditoría y Diagnóstico de Fallos

#### 7.1. Disección de una Línea de Log Real
Línea obtenida en los registros del servidor:
```text
www.huesca.empresa.lan:80 192.168.6.105 - - [22/Sep/2026:08:55:18 +0000] "GET / HTTP/1.1" 200 426 "-" "curl/8.18.0"
```

* `www.huesca.empresa.lan:80`: Nombre del VirtualHost y puerto que atendieron la petición.
* `192.168.6.105`: Dirección IP origen del cliente.
* `-`: Usuario no autenticado (o nombre de usuario en caso de estar protegido).
* `[22/Sep/2026:08:55:18 +0000]`: Fecha, hora y zona horaria exacta de la solicitud.
* `"GET / HTTP/1.1"`: Método HTTP, ruta relativa solicitada y versión del protocolo.
* `200`: Código de respuesta HTTP devuelto por el servidor (procesado con éxito).
* `426`: Tamaño de la respuesta devuelta en bytes.
* `"curl/8.18.0"`: Identificación del Agente de Usuario (User-Agent).

#### 7.2. Tabla de Comprobación de Escenarios de Fallo Provocados

| Provocad esto | Qué código y qué línea de registro salen |
| :--- | :--- |
| **Un `DocumentRoot` que no existe** | Código **`404 Not Found`** (o `403 Forbidden`). En error_log: `[core:error] AH00127: Cannot map GET / to file`. |
| **Permisos de lectura quitados a un fichero (`chmod 000`)** | Código **`403 Forbidden`**. En error_log: `[core:error] AH00132: file permissions deny server access`. |
| **Una directiva mal escrita en `sitios.conf`** | El contenedor falla al arrancar. Mensaje: `AH00526: Syntax error on line X of sitios.conf: Invalid command...`. |
| **El contenedor de la base de datos parado** | Código **`503 Service Unavailable`**. En error_log: `SQLSTATE[08006] [7] could not connect to server: Connection refused`. |
| **La contraseña mal en el `.env`** | Código **`503 Service Unavailable`**. En error_log: `SQLSTATE[08006] [7] FATAL: password authentication failed for user`. |
| **Dos servicios con el mismo puerto publicado** | Error de Docker: `Error response from daemon: Bind for 0.0.0.0:8080 failed: port is already allocated`. |
| **Un `.php` servido por un Apache sin PHP** | Código **`200 OK`**, pero el servidor entrega el código fuente en texto plano sin interpretar. |

---

## Parte B · Investigación Teórica

### 1. La Necesidad

#### Requerimientos de la Sede
La sede requiere una infraestructura web capaz de servir tres casos de uso bien diferenciados:
1. **Sitio público:** Un punto de acceso informativo visible en `www.huesca.empresa.lan`.
2. **Intranet privada:** Una zona restringida para personal autorizado bajo `intranet.huesca.empresa.lan`, protegida mediante autenticación.
3. **Página de estado y backend:** Una aplicación dinámica (`estado.php`) que verifique y exponga el estado de conexión con el gestor de base de datos PostgreSQL.
4. **Auditoría y trazabilidad:** Registros centralizados (`access_log` y `error_log`) para analizar accesos e incidentes técnicos.

#### ¿Por qué no basta con abrir el HTML en el navegador?
Abrir un archivo mediante el protocolo local (`file:///ruta/index.html`) falla conceptualmente para este escenario por tres razones:
* **Sin procesamiento en servidor:** El navegador no puede interpretar código de backend como PHP ni ejecutar consultas SQL a la base de datos.
* **Sin protocolo HTTP:** No existen cabeceras HTTP, códigos de estado (`200`, `401`, `503`), ni mecanismo para procesar la cabecera `Host:`.
* **Sin control de acceso centralizado:** No permite aplicar reglas de autenticación del lado del servidor ni restringir accesos.

#### Datos manejados y privacidad (RGPD)
* **Datos de aplicación:** Inventario de la empresa alojado en PostgreSQL.
* **Datos de credenciales:** Usuarios y hashes de contraseñas en el archivo `.htpasswd`.
* **Datos personales (RGPD):** Las direcciones IP de los clientes y los nombres de usuario autenticados registrados en los logs de Apache constituyen datos de carácter personal identificables según la normativa europea de protección de datos (RGPD). Requieren almacenamiento seguro, acceso restringido y políticas de retención.

---

### 2. El Servicio Web

#### Recorrido de una petición HTTP

```mermaid
sequenceDiagram
    autonumber
    actor Cliente as Cliente (Navegador/Curl)
    participant DNS as BIND9 (DNS)
    participant Web as Apache (Puerto 80)
    participant PHP as Módulo PHP
    participant DB as PostgreSQL (Puerto 5432)

    Cliente->>DNS: Consulta A (www.huesca.empresa.lan)
    DNS-->>Cliente: Retorna IP 192.168.6.105
    Cliente->>Web: TCP SYN + GET / HTTP/1.1 (Host: www.huesca.empresa.lan)
    Web->>Web: Evalúa VirtualHost por cabecera Host
    alt Recurso Estático (.html)
        Web-->>Cliente: 200 OK + Contenido HTML
    else Recurso Dinámico (.php)
        Web->>PHP: Pasa ejecución del script
        PHP->>DB: Conexión PDO (pdo_pgsql)
        DB-->>PHP: Retorna resultado consulta SQL
        PHP-->>Web: Genera HTML dinámico
        Web-->>Cliente: 200 OK + HTML generado
    end
```

#### Contenido Estático vs. Dinámico
* **Contenido Estático:** Archivos servidos tal cual existen en el sistema de archivos (`index.html`, imágenes, CSS). Apache los entrega directamente utilizando llamadas del sistema optimizadas (`sendfile`).
* **Contenido Dinámico:** Páginas generadas en tiempo de ejecución según la lógica de negocio o datos de la BD (`estado.php`).
* **Mecanismos de ejecución:**
  1. **Módulo empotrado (`mod_php`):** El intérprete se ejecuta dentro del propio proceso de Apache (utilizado en la imagen `php:8.3-apache`).
  2. **FastCGI / PHP-FPM:** El servidor web actúa como proxy y delega la ejecución del código a un pool de procesos independiente a través de un socket TCP/Unix.

#### Alojamiento de varios sitios por nombre
Un único servidor Apache atiende múltiples sitios en la misma IP y puerto (80) inspeccionando la cabecera HTTP `Host:` enviada por el cliente. Apache compara este valor con las directivas `ServerName` y `ServerAlias` de los bloques `<VirtualHost>` cargados.

#### HTTPS y dominios privados (.lan)
* **Certificado digital:** Fichero que asocia una clave pública con la identidad de un dominio, firmado por una Autoridad de Certificación (CA) de confianza.
* **Limitación del dominio `.lan`:** Las CA públicas (como Let's Encrypt o DigiCert) no pueden emitir certificados para TLDS no delegables o privados como `.lan`.
* **Alternativa en red propia:** Implementar una CA interna mediante herramientas como `step-ca` o `mkcert`, y distribuir el certificado raíz de la CA en el almacén de confianza de los equipos clientes de la sede.

---

### 3. Comparativa de Servidores Web

| Criterio | Apache HTTP Server | Nginx | Caddy | Microsoft IIS |
| :--- | :--- | :--- | :--- | :--- |
| **Desarrollador** | Apache Software Foundation | F5 / Community | Matt Holt / Community | Microsoft Corporation |
| **Licencia** | Apache 2.0 (Libre) | BSD-2-Clause (Libre) | Apache 2.0 (Libre) | Propietaria (Windows Server) |
| **Sistemas** | Linux, Unix, Windows | Linux, Unix, Windows | Linux, Windows, macOS | Windows Server |
| **Modelo** | Híbrido (Procesos/Hilos: MPM Event/Worker) | Asíncrono orientado a eventos (Event-driven) | Hilos concurrentes (Go Routines) | Orientado a hilos e I/O asíncrona |
| **Configuración**| Ficheros planos (`httpd.conf`), recarga sin parada (`apachectl graceful`) | Ficheros planos (`nginx.conf`), recarga sin parada (`nginx -s reload`) | Caddyfile / JSON API, recarga dinámica sin interrupción | GUI (IIS Manager) / PowerShell / XML (`web.config`) |
| **Código Dinámico**| Módulos empotrados (`mod_php`) o FastCGI | FastCGI / SCGI / Proxy Inverso (PHP-FPM) | FastCGI / Reverse Proxy | FastCGI / ISAPI / ASP.NET Core |
| **VirtualHost** | Directiva `<VirtualHost>` | Bloque `server { server_name ... }` | Bloque de sitio `dominio.lan { ... }` | Binding por Nombre de Host |
| **HTTPS** | Vía `mod_ssl` (manual) | Vía módulo `ngx_http_ssl_module` (manual) | Automático con ACME integrado | Vía Bindings y almacén de certificados Windows |
| **Puntos fuertes**| Gran cantidad de módulos, flexible `.htaccess` [Apache HTTP Server Docs] | Alto rendimiento y bajo consumo de memoria [Nginx Docs] | HTTPS automático, configuración muy sencilla [Caddy Docs] | Integración perfecta con Active Directory [Microsoft Learn — IIS] |
| **Puntos débiles**| Mayor consumo de RAM bajo alta concurrencia [Apache HTTP Server Docs] | Sin soporte nativo de configuración por directorio (`.htaccess`) [Nginx Docs] | Menor ecosistema de módulos legacy [Caddy Docs] | Requiere licencias de Windows Server [Microsoft Learn — IIS] |

Fuentes de esta tabla: **Apache** → https://httpd.apache.org/docs/2.4/ (ya citada en el apartado 7). **Nginx** → https://nginx.org/en/docs/ (documentación oficial del proyecto). **Caddy** → https://caddyserver.com/docs/ (documentación oficial, apartado *Automatic HTTPS*). **Microsoft IIS** → https://learn.microsoft.com/es-es/iis/ (documentación oficial de Microsoft Learn).

#### Conceptos Complementarios
* **Proxy Inverso:** Servidor intermedio que recibe las peticiones externas y las distribuye a los servidores internos de backend.
* **Servidor de Aplicaciones:** Entorno especializado en ejecutar la lógica de negocio pesada (ej. Tomcat, Gunicorn, Puma).
* **CDN (Content Delivery Network):** Red distribuida de servidores geográficamente dispersos que sirven contenido estático en caché cerca del usuario.
* **¿Necesidad en la sede?:** No se requiere CDN ni servidor de aplicaciones complejo debido a que el tráfico es local a la LAN de la sede. Un proxy inverso sería útil únicamente si se expusieran microservicios adicionales.

---

### 4. Modelos de Alojamiento y Proveedores

#### Modelos de Alojamiento

| Modelo | Descripción |
| :--- | :--- |
| **Alojamiento Compartido** | Múltiples clientes comparten los recursos del mismo servidor y sistema operativo. |
| **Servidor Virtual (VPS)** | Máquina virtual aislada con recursos dedicados y acceso root completo. |
| **Servidor Dedicado** | Servidor físico exclusivo para un único cliente. |
| **Nube IaaS** | Infraestructura de cómputo, almacenamiento y red bajo demanda facturada por uso. |
| **Plataforma PaaS** | Entorno donde el cliente solo sube el código y el proveedor gestiona la infraestructura. |
| **Alojamiento Estático** | Red global optimizada exclusivamente para la entrega de archivos estáticos (HTML/JS/CSS). |
| **Propio (On-Premise)** | Infraestructura física y servidores propiedad de la empresa dentro de sus instalaciones. |

#### Matriz de Responsabilidad y Proveedores

| Criterio | Shared | VPS | Dedicado | IaaS | PaaS | Estático | Propio |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Hardware** | Proveedor | Proveedor | Proveedor | Proveedor | Proveedor | Proveedor | **Cliente** |
| **Red** | Proveedor | Proveedor | Proveedor | Proveedor | Proveedor | Proveedor | **Cliente** |
| **Sistema (OS)** | Proveedor | **Cliente** | **Cliente** | **Cliente** | Proveedor | Proveedor | **Cliente** |
| **Servidor web** | Proveedor | **Cliente** | **Cliente** | **Cliente** | Proveedor | Proveedor | **Cliente** |
| **Aplicación** | **Cliente** (limitado) | **Cliente** | **Cliente** | **Cliente** | **Cliente** | **Cliente** (solo estático) | **Cliente** |
| **Datos** | **Cliente** | **Cliente** | **Cliente** | **Cliente** | **Cliente** | **Cliente** | **Cliente** |
| **Copias de seguridad** | Proveedor (básicas) / **Cliente** | **Cliente** | **Cliente** | **Cliente** | Proveedor (parcial) | Proveedor (repositorio) | **Cliente** |
| **Proveedor de Ejemplo** | Raiola Networks | Hetzner Cloud | OVHcloud | AWS | Heroku | Cloudflare Pages | Interno (Sede) |
| **Ubicación Datos (EU)** | España (UE) | Alemania/Finlandia (UE) | Francia/España (UE) | Configurable (UE) | EE. UU. / UE | Global | España (Local) |
| **Precio orientativo** | ~6-8 €/mes | CX22, ~4,5 €/mes¹ | Desde ~10-15 €/mes | t4g.small, ~12 $/mes | Dyno Basic, ~7 $/mes | Gratis (Pages) / $20 (Workers Paid) | Coste HW + electricidad |
| **Fecha de consulta** | 23/09/2026 | 23/09/2026 | 23/09/2026 | 23/09/2026 | 23/09/2026 | 23/09/2026 | — |
| **Enlace precio** | https://www.raiolanetworks.es/alojamiento-web/ | https://www.hetzner.com/cloud/ | https://www.ovhcloud.com/es/vps/ | https://aws.amazon.com/es/ec2/pricing/ | https://www.heroku.com/pricing/ | https://www.cloudflare.com/es-es/plans/ | — |
| **Garantía SLA** | 99.9% | 99.9% | 99.95% | 99.99% | 99.95% | 99.99% | Sin SLA externo |

¹ Hetzner subió precios de cloud un 30-37 % el 1 de abril de 2026 y volvió a ajustar las líneas CPX/CCX el 15 de junio de 2026; la cifra de la tabla es la orientativa vigente a fecha de consulta — comprobadla en el enlace antes de citarla en la entrega, porque cambia con frecuencia.

#### Respuestas a Cuestiones Clave
1. **Si la web pública se alojara fuera:**
   * **Seguiría igual:** El código PHP (`estado.php`) y la configuración de los VirtualHosts de Apache.
   * **Cambiaría:** El registro DNS público apuntaría a la IP pública del proveedor externo en lugar de la IP local (`192.168.6.105`).
   * **Se rompería:** La conexión con la base de datos PostgreSQL si esta se mantiene en la red privada interna `trasera`. Requeriría exponer la BD de forma segura mediante una VPN sitio a sitio o un túnel cifrado.
2. **Razones para alojar en la propia red (On-Premise):**
   * **Técnica 1:** Latencia ultrabaja en la red local Gigabit para los usuarios de la sede.
   * **Técnica 2:** Aislamiento total de la red `trasera` de base de datos sin tráfico saliente hacia Internet.
   * **No Técnica:** Soberanía absoluta del dato y cumplimiento estricto de normativas internas sin depender de un tercero.
   * **En contra:** Responsabilidad directa sobre fallos de hardware/suministro eléctrico y necesidad de personal técnico local.
3. **Proveedor elegido para externalizar:**
   * **Hetzner Cloud (Alemania - UE):** Por cumplimiento estricto del RGPD, centros de datos en territorio europeo, rendimiento elevado con discos NVMe y costes fijos altamente competitivos (~5€/mes por VPS).

---

### 5. Elección Justificada de Arquitectura

* **Servidor Web:** Se utilizaría **Nginx** combinado con **PHP-FPM** si no fuera por el requisito del estándar. Ofrece mayor eficiencia en memoria y mejor rendimiento bajo cargas concurrentes.
* **Alojamiento:** Alojamiento **On-Premise con Docker Compose**. Garantiza aislamiento en la red local y paridad absoluta entre los entornos de desarrollo y producción.
* **Impacto del Estándar (Apache):**
  * **Obliga a:** Gestionar una huella de memoria superior y configurar directivas de bloques sintácticamente más complejas.
  * **Ahorra:** La separación en dos servicios independientes (Servidor Web + PHP-FPM), simplificando el despliegue al integrar el intérprete mediante el contenedor `php:8.3-apache`.
* **Módulos activados:** Solo los indispensables (`mpm_event`, `auth_basic`, `authn_file`, `authz_user`, `dir`, `mime`, `reqtimeout`), desactivando módulos innecesarios para reducir la superficie de ataque.
* **Diseño de Seguridad y Despliegue:**
  * **Un sitio por fichero:** cada VirtualHost se define en su propio fichero de configuración (uno para `www.huesca.empresa.lan`, otro para `intranet.huesca.empresa.lan`) en vez de concentrarlos en un único fichero. Así se puede activar o desactivar un sitio de forma independiente y el `configtest` señala en qué fichero concreto está el error de sintaxis, en lugar de en un bloque grande difícil de localizar.
  * **Estructura de ficheros:** Despliegue mediante VirtualHosts separados.
  * **Montajes de solo lectura:** El código fuente se monta con la opción `:ro` para evitar la modificación de archivos en caso de compromiso del contenedor.
  * **Credenciales:** El archivo `.htpasswd` reside en `/usr/local/apache2/conf/sede/` (fuera de la raíz web `DocumentRoot`), impidiendo su descarga directa por HTTP.
  * **Fijación de versiones:** Se especifican etiquetas concretas (`php:8.3-apache`, `postgres:16`) evitando el uso de `latest` para garantizar la reproducibilidad del entorno.

---

### 6. Procedimientos de Comprobación y Verificación

```bash
# 1. Validar la sintaxis de la configuración sin reiniciar el servicio
sudo docker exec mi-apache apache2ctl configtest

# 2. Consultar la estructura de VirtualHosts cargada en memoria
sudo docker exec mi-apache apache2ctl -S

# 3. Verificar respuesta HTTP 200 en el sitio público y 401 en la intranet
curl -si -H 'Host: www.huesca.empresa.lan' [http://192.168.6.105](http://192.168.6.105) | head -n 1
curl -si -H 'Host: intranet.huesca.empresa.lan' [http://192.168.6.105](http://192.168.6.105) | head -n 1

# 4. Probar la resolución de VirtualHosts sin depender del servicio DNS local
curl -s -H 'Host: www.huesca.empresa.lan' [http://192.168.6.105](http://192.168.6.105)
curl -s --resolve www.huesca.empresa.lan:80:192.168.6.105 [http://www.huesca.empresa.lan/](http://www.huesca.empresa.lan/)

# 5. Comprobar la conexión dinámica entre PHP y el gestor PostgreSQL
curl -s [http://192.168.6.105:8080/estado.php](http://192.168.6.105:8080/estado.php)

# 6. Localizar la causa exacta de un error 500 en los registros
docker compose logs web | grep -i "error"

# 7. Prueba remota desde otro equipo cliente de la red local
curl -si [http://192.168.6.105/](http://192.168.6.105/)
```

---

### 7. Fuentes y Documentación

**Pasos 2 a 7 (Apache) y 6 (PHP):**
* **Apache HTTP Server Documentation (v2.4):** https://httpd.apache.org/docs/2.4/ (consultado 23/09/2026)
* **PHP Official Documentation (PDO_PGSQL):** https://www.php.net/manual/es/ref.pdo-pgsql.php (consultado 23/09/2026)
* **Docker Documentation (Compose Specification):** https://docs.docker.com/compose/ (consultado 23/09/2026)

**Apartado 3 (cada producto):**
* **Nginx Documentation:** https://nginx.org/en/docs/ (consultado 23/09/2026)
* **Caddy Documentation:** https://caddyserver.com/docs/ (consultado 23/09/2026)
* **Microsoft IIS — Microsoft Learn:** https://learn.microsoft.com/es-es/iis/ (consultado 23/09/2026)

**Apartado 4 (cada proveedor):**
* **Raiola Networks — Alojamiento web:** https://www.raiolanetworks.es/alojamiento-web/ (consultado 23/09/2026)
* **Hetzner Cloud — Precios y documentación:** https://www.hetzner.com/cloud/ y https://docs.hetzner.com/ (consultado 23/09/2026; nota: subida de precios del 30-37 % el 01/04/2026, ver https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
* **OVHcloud — VPS:** https://www.ovhcloud.com/es/vps/ (consultado 23/09/2026)
* **AWS — EC2 Pricing:** https://aws.amazon.com/es/ec2/pricing/ (consultado 23/09/2026)
* **Heroku — Pricing:** https://www.heroku.com/pricing/ (consultado 23/09/2026)
* **Cloudflare — Plans:** https://www.cloudflare.com/es-es/plans/ (consultado 23/09/2026)

---

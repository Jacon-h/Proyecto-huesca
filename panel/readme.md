# panel/ · Panel del BIFI (IAW RA5)

Aplicación en PHP 8.3 + Apache para gestionar los proyectos del BIFI: login con perfiles, alta de proyectos
validada en el servidor, gestión de miembros y consumo de cada proyecto.

**Todos sus datos están en PostgreSQL**, en la base `bifi` (`BIFI_DB`), y entra con su propio usuario `panel`
(`BIFI_PANEL_USER`), que solo tiene los permisos que usa. El contenedor no guarda nada: se puede borrar y
volver a crear sin perder datos.

## Índice

- [Cómo se arranca y dónde responde](#cómo-se-arranca-y-dónde-responde)
- [Dónde están los datos](#dónde-están-los-datos)
- [Estructura](#estructura)
- [Usuarios de ejemplo](#usuarios-de-ejemplo)
- [Seguridad](#seguridad)
- [Pruebas](#pruebas)
- [Mantenimiento](#mantenimiento)

## Cómo se arranca y dónde responde

Sale del `compose.yaml` de la raíz (servicio `panel`, contenedor `panel`) y lo levanta `sudo ./instalar.sh`.

| Dirección | Camino |
|---|---|
| `http://panel.huesca.empresa.lan` | DNS de la sede → Apache (`mi-apache`, `web/huesca.conf`) → proxy a `http://panel:80/` |
| `http://<IP_AULA>:8081` | Directo al contenedor (para probar sin el proxy) |

La conexión a la base la toma de las variables de entorno que pone `compose.yaml` (`BIFI_HOST`, `BIFI_DB`,
`BIFI_USER`, `BIFI_PASSWORD`, que salen de `.env`). En el código PHP no hay ninguna credencial.

## Dónde están los datos

### Tablas

Las crea `db/04_bifi.sh` (apartado 3) como administrador, que es su dueño. Se repite en cada instalación sin
romper nada (`CREATE TABLE IF NOT EXISTS`).

| Tabla | Qué guarda | Permisos del usuario `panel` | Por qué solo esos |
|---|---|---|---|
| `usuarios` | usuario, nombre, perfil y hash de la contraseña | `SELECT` | El login y los nombres. Las cuentas no se crean ni se cambian desde la web. |
| `proyectos` | código, título, responsable y tarifa | `SELECT`, `INSERT` | Listar y dar de alta. El panel no edita ni borra proyectos. |
| `miembros` | qué investigador está en qué proyecto | `SELECT`, `INSERT`, `DELETE` | Añadir y quitar miembros. |
| `usos` | consumo: proyecto, persona, máquina, núcleos, horas y fecha | `SELECT` | El consumo lo registra el CESAR; el panel solo lo enseña. |

El usuario `panel` no puede crear, cambiar ni borrar tablas: no es dueño de nada y en el esquema solo
tiene `USAGE`. Si alguien llegara a ejecutar SQL con sus credenciales, no podría cambiar contraseñas,
inventarse consumos ni vaciar tablas. El responsable que entra desde el aula (`resp_demo`) no ve ninguna
tabla. Las comprobaciones están en `db/pruebas/probar.sh` (apartado «Tablas del panel»).

La base tiene además sus propias reglas, por si algo se escapara de la validación de PHP: formato del
código (`CHECK ~ '^[A-Z]{3}-[0-9]{4}$'`), perfiles y tarifas válidos, claves ajenas entre tablas, y
núcleos y horas positivos.

### Primera carga: los JSON de `datos-ejemplo/`

`datos-ejemplo/usuarios.json`, `proyectos.json` y `usos.json` son **solo los datos de partida**. Los lee
`instalar.sh` (fase `bd`) y los mete en la base con `db/panel/datos-iniciales.sql`:

1. Solo carga si la tabla `usuarios` está vacía, es decir, la primera vez. Si cargara en cada instalación,
   volverían los miembros que alguien hubiera quitado desde el panel.
2. Todo va en una transacción. Antes de confirmar, comprueba que cada registro de los JSON está en la base;
   si falta alguno, deshace la carga y la instalación se para con un error.
3. Las contraseñas ya vienen como hash (`password_hash`, bcrypt) y se copian tal cual.

Después de eso los JSON no se usan para nada. El panel no tiene código para leerlos, y ni siquiera están
dentro de su imagen (`panel/.dockerignore`). Se quedan en el repositorio solo para poder rehacer la base
desde cero (ver [Mantenimiento](#mantenimiento)).

## Estructura

```text
Dockerfile           PHP 8.3 + Apache + pdo_pgsql, con php.ini de producción. Solo se sirve public/
.dockerignore        Deja fuera de la imagen datos-ejemplo/ y la documentación
public/              Lo único que ve el navegador
  login.php          Formulario de entrada
  logout.php         Cierra la sesión (solo por POST, desde el botón «Salir»)
  index.php          Proyectos que puede ver el usuario
  proyecto.php       Detalle, miembros (añadir/quitar) y consumo
  proyecto-nuevo.php Alta de proyecto (solo CESAR)
  estado-bd.php      Conexión del panel con bifi: usuario, IP que ve el gestor, colación… (solo CESAR)
  estilo.css
comun/               Funciones propias, fuera del alcance del navegador (P8)
  arranque.php       Lo primero de cada página: carga lo demás, abre la sesión y recoge los errores
  bd.php             conectar_bifi(), bd(), consultar() y estado_bifi()
  funciones.php      e() para escapar, redirigir(), perfiles y tarifas
  sesion.php         iniciar_sesion(), entrar(), salir(), exigir_login(), exigir_perfil(), CSRF
  proyectos.php      puede_ver(), puede_gestionar(), validar_proyecto(), crear_proyecto(), gestionar_miembros()…
  plantilla.php      cabecera(), menu() según el perfil, pie(), pagina_error()
pruebas/             Para la línea de órdenes (no se sirven)
  probar-panel.sh    Pruebas A1–A10 y CSRF con curl
  estado-bifi.php    P1: el contenedor entra en bifi (lo usa db/pruebas/probar.sh)
  demo-xss.php       A9: el mismo título con y sin escapar
datos-ejemplo/       JSON de partida: solo los usa instalar.sh para la primera carga
```

Todas las consultas pasan por `consultar($sql, $parametros)`, que hace `prepare()` con la consulta fija y
`execute()` con los datos aparte. Ningún dato del usuario se pega nunca al texto del SQL.

Qué funciones de `comun/` usa cada página:

| Función | La usan |
|---|---|
| `e()` | todas las páginas |
| `exigir_login()` | `index.php`, `proyecto.php` (y `exigir_perfil()` por dentro) |
| `exigir_perfil()` | `proyecto-nuevo.php`, `estado-bd.php` |
| `puede_ver()` | `index.php` (vía `proyectos_visibles()`), `proyecto.php` |
| `puede_gestionar()` | `proyecto.php` |
| `nombre_de()` | `index.php`, `proyecto.php` |
| `crear_proyecto()` | `proyecto-nuevo.php` |
| `campo_csrf()` / `exigir_csrf()` | `login.php`, `logout.php` (y el botón «Salir» del menú), `proyecto.php`, `proyecto-nuevo.php` |
| `cabecera()`, `pie()` | todas las páginas |

## Usuarios de ejemplo

Todos con la contraseña `bifi2026`. En la base (y en `datos-ejemplo/usuarios.json`) solo está el hash.

| Usuario | Perfil | Qué ve y qué hace |
|---|---|---|
| `ana` | Investigador | `BIO-0001` (es miembro). Solo su propio consumo. |
| `luis` | Investigador | `FIS-0002` (es miembro). Solo su propio consumo. |
| `marta` | Responsable | `BIO-0001` (es la responsable): añade y quita investigadores. |
| `jorge` | Responsable | `FIS-0002` (es el responsable): añade y quita investigadores. |
| `cesar` | Administración CESAR | Todos los proyectos, alta de proyectos y estado de la base. |

Estos usuarios son del panel y no tienen relación con los de OpenLDAP ni con los de Active Directory
(`ldif/`, `sincronizacion/`). Son dos listas independientes.

## Seguridad

| Qué | Dónde |
|---|---|
| Inyección SQL: todas las consultas son preparadas (`prepare` + `execute`), con preparación real en el servidor (`ATTR_EMULATE_PREPARES = false`) | `consultar()` en `bd.php` |
| Mínimo privilegio en la base: el usuario `panel` solo tiene los permisos de cada tabla que usa, sin DDL | `db/04_bifi.sh` |
| Credenciales de la base solo en variables de entorno (`.env` → `compose.yaml`) | `conectar_bifi()` |
| Contraseñas con `password_hash` / `password_verify`; mismo mensaje y mismo tiempo si el usuario no existe | `entrar()` |
| Id de sesión y código CSRF nuevos al entrar | `entrar()` |
| Cookie `HttpOnly` y `SameSite=Lax`; modo estricto de sesiones (no acepta ids que PHP no creó) | `iniciar_sesion()` |
| Salir: solo por POST con código CSRF; vacía `$_SESSION`, caduca la cookie y `session_destroy()` | `logout.php`, `salir()` |
| Perfil en la sesión; el menú cambia según el perfil | `entrar()`, `menu()` |
| Autorización en el servidor en cada página y en cada POST (no solo ocultando enlaces) | `exigir_perfil()`, `puede_ver()`, `puede_gestionar()` |
| Proyecto ajeno o inexistente: el mismo 404 (no se revela que existe) | `proyecto.php` |
| Validación de todo lo que llega del navegador (el formulario lleva `novalidate`); la base lo vuelve a comprobar con `CHECK` y claves | `validar_proyecto()`, `gestionar_miembros()`, `db/04_bifi.sh` |
| Código CSRF en todos los formularios, también en el login | `campo_csrf()`, `exigir_csrf()` |
| Salida escapada con `htmlspecialchars(…, ENT_QUOTES \| ENT_SUBSTITUTE, 'UTF-8')` | `e()` |
| Errores de la base al registro (`docker logs panel`), nunca al navegador | `arranque.php`, `php.ini` de producción en el `Dockerfile` |
| `comun/` y `pruebas/` fuera de la raíz web; los JSON fuera de la imagen | `Dockerfile`, `.dockerignore` |

## Pruebas

Todas las pruebas automáticas las lanza un solo script:

    bash panel/pruebas/probar-panel.sh http://panel.huesca.empresa.lan

Los permisos del usuario `panel` en la base los prueba `sudo ./db/pruebas/probar.sh` (lo lanza también
`sudo ./instalar.sh verificar`).

> **Pendiente:** las pruebas se pasaron el 23/11/2026, cuando el panel aún guardaba sus datos en JSON. Con
> PostgreSQL hay que repetirlas en la VM contra `panel.huesca.empresa.lan` y guardar la salida como evidencia.

### Resumen

| Prueba | Qué se comprueba | Cómo | Resultado esperado |
|---|---|---|---|
| Panel en la sede | Sale del `compose.yaml` y responde por su nombre | `curl -I -H "Host: panel.huesca.empresa.lan" http://localhost/index.php` | `302` a `login.php` (también lo mira `web/probar.sh`) |
| A1 | Login con `password_hash` | `marta` / `bifi2026` | `302` a `index.php`; la cookie `PHPSESSID` cambia al entrar |
| A2 | Login fallido | clave mala, y usuario que no existe | El mismo mensaje en los dos casos: «Usuario o contraseña incorrectos.» |
| CSRF login | Login sin el código del formulario | POST con usuario y clave buenos pero sin `csrf` | `400` y no entra |
| A3 | El perfil va en la sesión | entrar como `marta` | La cabecera dice «Marta Gil · Responsable de proyecto» |
| A5 | El menú cambia según el perfil | `ana` y `cesar` | `ana` no ve «Nuevo proyecto»; `cesar` ve «Nuevo proyecto» y «Estado de la base» |
| A8 | Cada perfil ve lo suyo | `ana` en `index.php` | Solo `BIO-0001` |
| A4 | Cambiar la URL no sirve | `marta` → `proyecto-nuevo.php`; `ana` → `proyecto.php?codigo=FIS-0002` | `403` y `404` |
| A8c | Mandar el formulario a mano no sirve | POST de `ana` y de `jorge` a `BIO-0001` | `403` (`ana` lo ve pero no lo gestiona) y `404` (`jorge` ni lo ve) |
| CSRF | Un POST sin el código del formulario | POST de `marta` sin `csrf` | `400` y no cambia nada |
| A8b | El responsable añade y quita investigadores | `marta` añade y quita a `luis` en `BIO-0001` | Aparece y desaparece de la lista; con `jorge` (no es investigador): «Ese usuario no es un investigador.» |
| A7 | Alta con validación en el servidor | `cesar` envía datos malos y luego buenos | 4 mensajes de error y no se guarda; con datos buenos se guarda y sale en la lista; código repetido: rechazado |
| A9 | Salida escapada | alta con título `<script>alert("XSS")</script>` | En la lista sale el texto; en el HTML, `&lt;script&gt;…` |
| CSRF salir | Abrir `logout.php` por GET | enlace o `<img>` desde otra web | No cierra la sesión |
| A10 | Con la cookie de una sesión cerrada no se entra | guardar la cookie, salir, volver a usarla | Antes de salir: `200`; después: `302` a `login.php` |

### Cómo enseñarlo a mano

**A1 y A2 · Login.**
1. Abrir `http://panel.huesca.empresa.lan`: lleva a `login.php`.
2. En DevTools → *Application* → *Cookies*, anotar `PHPSESSID`.
3. Entrar como `marta` / `bifi2026`: la cookie cambia (`session_regenerate_id(true)` en `entrar()`).
4. Probar `marta` con una clave mala y `pepe` con cualquier clave: sale el mismo mensaje. `entrar()` llama a
   `password_verify()` también cuando el usuario no existe (con un hash de relleno), para que tampoco se
   note por el tiempo de respuesta.
5. Enseñar que en la base solo hay hashes:

       docker exec -u postgres mi-postgres psql -d bifi -c "SELECT usuario, perfil, left(hash, 7) || '…' AS hash FROM usuarios"

**A3, A5, A8 · Perfil en la sesión y menú.** `entrar()` guarda `usuario`, `nombre` y `perfil` en
`$_SESSION['usuario']` (nunca el hash). `menu()` en `comun/plantilla.php` lee ese perfil: el CESAR ve dos
enlaces más. Entrar con `ana`, `marta` y `cesar` y comparar el menú y la lista de proyectos.

**A4, A8b, A8c · Nadie llega a lo de otro.** Con `ana` dentro, escribir en la barra
`proyecto.php?codigo=FIS-0002` → «No hay ningún proyecto con ese código entre los tuyos» (404). Es el mismo
mensaje que para un código que no existe: así no se descubre qué proyectos hay.

Formulario a mano: entrar como `ana`, abrir `BIO-0001` y, en la consola de DevTools:

```js
fetch(location.href, {method: 'POST', body: new URLSearchParams({accion: 'anadir', investigador: 'luis'})})
  .then(r => console.log(r.status))   // 403 (ana es miembro, no responsable)
```

Con `jorge` sobre `BIO-0001` → 404. La comprobación está en `proyecto.php`, antes de tocar nada:
`puede_ver()` y luego `puede_gestionar()`. Además, `exigir_csrf()` rechaza el POST que no trae el código
del formulario (400).

**A7 · Alta de proyecto.** Como `cesar`, «Nuevo proyecto» con código `mal` y título `x`: salen los mensajes
junto a cada campo y los valores escritos se conservan. El formulario lleva `novalidate`: el navegador no
comprueba nada y aun así el servidor (`validar_proyecto()`) lo rechaza. Con datos buenos (`BIO-0003`, título
de 5 a 120 caracteres, tarifa y responsable de la lista) redirige al proyecto y aparece en «Proyectos». En
la base:

    docker exec -u postgres mi-postgres psql -d bifi -c "SELECT * FROM proyectos ORDER BY codigo"

**A9 · Salida escapada y qué pasa sin ella.**
1. Como `cesar`, dar de alta un proyecto con título `<script>alert("XSS")</script>`. En la lista se ve el
   texto tal cual; con «Ver código fuente» se ve `&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;`. En
   la base el título está guardado tal cual: se escapa al pintarlo, no al guardarlo.
2. Qué pasaría sin escapar, sin tocar el panel:

       docker exec panel php /var/www/panel/pruebas/demo-xss.php > demo-xss.html

   Abrir `demo-xss.html` en el navegador: el mismo título pintado con `e()` se ve como texto; pintado sin
   `e()`, el script se ejecuta (el fondo se pone rojo y cambia el aviso). Un script así podría leer la
   página o enviar lo que el usuario ve a otro sitio. La cookie de sesión es `HttpOnly`, así que no podría
   leerla, pero sí actuar en nombre del usuario mientras tiene la página abierta.

**A10 · La cookie de una sesión cerrada no sirve.** Como todos los formularios llevan código CSRF, con curl
hay que sacarlo de la página antes de cada POST:

```bash
P=http://panel.huesca.empresa.lan
csrf() { curl -s -b "$1" -c "$1" "$P/$2" | grep -o 'name="csrf" value="[^"]*"' | head -1 | cut -d'"' -f4; }

curl -s -o /dev/null -b vieja.txt -c vieja.txt -d usuario=marta -d clave=bifi2026 \
     -d "csrf=$(csrf vieja.txt login.php)" $P/login.php                       # entrar
curl -s -o /dev/null -w '%{http_code}\n' -b vieja.txt $P/index.php            # 200: la cookie vale
cp vieja.txt copia.txt                                                         # guardamos la cookie
curl -s -o /dev/null -b vieja.txt -c vieja.txt \
     -d "csrf=$(csrf vieja.txt index.php)" $P/logout.php                      # salir (botón «Salir»)
curl -s -o /dev/null -w '%{http_code}\n' -b copia.txt $P/index.php            # 302: ya no vale
```

`salir()` vacía `$_SESSION`, caduca la cookie y llama a `session_destroy()`, que borra la sesión en el
servidor. Aunque alguien conserve la cookie, el id ya no corresponde a nada; y con
`session.use_strict_mode` PHP ni siquiera lo reutiliza: crea uno nuevo y vacío.

En el navegador: entrar, copiar el valor de `PHPSESSID`, pulsar «Salir», volver a crear la cookie a mano
con ese valor en DevTools y recargar `index.php` → vuelve a `login.php`.

## Mantenimiento

Todo se hace como administrador (`postgres`) por el socket del contenedor. El usuario `panel` no tiene
permisos para nada de esto, a propósito.

**Cambiar la contraseña de alguien.** Se genera el hash y se guarda en la base:

    docker exec panel php -r 'echo password_hash("nueva-clave", PASSWORD_DEFAULT), PHP_EOL;'
    docker exec -i -u postgres mi-postgres psql -d bifi <<'SQL'
    UPDATE usuarios SET hash = '<el hash de arriba>' WHERE usuario = 'marta';
    SQL

(El `<<'SQL'` con comillas evita que el shell toque los `$` del hash.)

**Quitar los proyectos de prueba** que deja `probar-panel.sh`:

    docker exec -u postgres mi-postgres psql -d bifi \
        -c "DELETE FROM miembros WHERE proyecto LIKE 'TST-%'" -c "DELETE FROM proyectos WHERE codigo LIKE 'TST-%'"

**Volver a los datos de ejemplo** (borra las altas y los cambios de miembros):

    docker exec -u postgres mi-postgres psql -d bifi -c "TRUNCATE usos, miembros, proyectos, usuarios"
    sudo ./instalar.sh bd

Con la tabla `usuarios` vacía, la fase `bd` vuelve a cargar los JSON. Si alguien los ha borrado del
servidor: `git checkout -- panel/datos-ejemplo`.

**Volumen antiguo.** Las versiones anteriores guardaban los JSON en el volumen `datos-panel`. Ya no se usa;
en un servidor que venga de entonces se puede borrar:

    docker volume rm "$(docker volume ls -q | grep -E '(^|_)datos-panel$')"

# panel/ · Panel del BIFI (IAW RA5)

Aplicación en PHP 8.3 + Apache para gestionar los proyectos del BIFI: login con perfiles, alta de proyectos
validada en el servidor, gestión de miembros y consumo de cada proyecto. Sus datos están en ficheros JSON
(volumen `datos-panel`); además entra en la base `bifi` de PostgreSQL con el usuario `panel` (ASGBD RA2, P1).

## Cómo se arranca y dónde responde

Sale del `compose.yaml` de la raíz (servicio `panel`, contenedor `panel`) y lo levanta `sudo ./instalar.sh`.

| Dirección | Camino |
|---|---|
| `http://panel.huesca.empresa.lan` | DNS de la sede → Apache (`mi-apache`, `web/huesca.conf`) → proxy a `http://panel:80/` |
| `http://<IP_AULA>:8081` | Directo al contenedor (para probar sin el proxy) |

## Estructura

```text
Dockerfile           PHP 8.3 + Apache + pdo_pgsql. Solo se sirve public/
public/              Lo único que ve el navegador
  login.php          Formulario de entrada
  logout.php         Cierra la sesión
  index.php          Proyectos que puede ver el usuario
  proyecto.php       Detalle, miembros (añadir/quitar) y consumo
  proyecto-nuevo.php Alta de proyecto (solo CESAR)
  estado-bd.php      Conexión del panel con bifi: usuario, IP que ve el gestor, colación… (solo CESAR)
  estilo.css
comun/               Funciones propias, fuera del alcance del navegador (P8)
  arranque.php       Lo primero de cada página: carga lo demás y abre la sesión
  funciones.php      e() para escapar, leer_datos(), guardar_datos(), redirigir()
  sesion.php         iniciar_sesion(), entrar(), salir(), exigir_login(), exigir_perfil(), CSRF
  proyectos.php      puede_ver(), puede_gestionar(), validar_proyecto(), gestionar_miembros()…
  plantilla.php      cabecera(), menu() según el perfil, pie(), pagina_error()
  bd.php             conectar_bifi() y estado_bifi()
pruebas/             Para la línea de órdenes (no se sirven)
  probar-panel.sh    Pruebas A1–A10 con curl
  estado-bifi.php    P1: el contenedor entra en bifi (lo usa db/pruebas/probar.sh)
  demo-xss.php       A9: el mismo título con y sin escapar
datos-ejemplo/       usuarios.json, proyectos.json y usos.json iniciales
```

Qué funciones de `comun/` usa cada página:

| Función | La usan |
|---|---|
| `e()` | todas las páginas |
| `exigir_login()` | `index.php`, `proyecto.php` (y `exigir_perfil()` por dentro) |
| `exigir_perfil()` | `proyecto-nuevo.php`, `estado-bd.php` |
| `puede_ver()` | `index.php` (vía `proyectos_visibles()`), `proyecto.php` |
| `puede_gestionar()` | `proyecto.php` |
| `nombre_de()` | `index.php`, `proyecto.php` |
| `campo_csrf()` / `exigir_csrf()` | `proyecto.php`, `proyecto-nuevo.php` |
| `cabecera()`, `pie()` | todas las páginas |

## Usuarios de ejemplo

Todos con la contraseña `bifi2026`. En `datos-ejemplo/usuarios.json` solo está el hash hecho con `password_hash()`.

| Usuario | Perfil | Qué ve y qué hace |
|---|---|---|
| `ana` | Investigador | `BIO-0001` (es miembro). Solo su propio consumo. |
| `luis` | Investigador | `FIS-0002` (es miembro). Solo su propio consumo. |
| `marta` | Responsable | `BIO-0001` (es la responsable): añade y quita investigadores. |
| `jorge` | Responsable | `FIS-0002` (es el responsable): añade y quita investigadores. |
| `cesar` | Administración CESAR | Todos los proyectos, alta de proyectos y estado de la base. |

Para dar a alguien otra contraseña, se genera el hash y se pega en `usuarios.json` (dentro del volumen):

    docker exec panel php -r 'echo password_hash("nueva-clave", PASSWORD_DEFAULT), PHP_EOL;'

## Seguridad

| Qué | Dónde |
|---|---|
| Contraseñas con `password_hash` / `password_verify`; mismo mensaje y mismo tiempo si el usuario no existe | `entrar()` |
| Id de sesión nuevo al entrar (`session_regenerate_id(true)`) | `entrar()` |
| Cookie `HttpOnly` y `SameSite=Lax`; modo estricto de sesiones (no acepta ids que PHP no creó) | `iniciar_sesion()` |
| Salir: vacía `$_SESSION`, caduca la cookie y `session_destroy()` | `salir()` |
| Perfil en la sesión; el menú cambia según el perfil | `entrar()`, `menu()` |
| Autorización en el servidor en cada página y en cada POST (no solo ocultando enlaces) | `exigir_perfil()`, `puede_ver()`, `puede_gestionar()` |
| Proyecto ajeno o inexistente: el mismo 404 (no se revela que existe) | `proyecto.php` |
| Validación de todo lo que llega del navegador (el formulario lleva `novalidate`) | `validar_proyecto()`, `gestionar_miembros()` |
| Código CSRF en los formularios que cambian datos | `campo_csrf()`, `exigir_csrf()` |
| Salida escapada con `htmlspecialchars(…, ENT_QUOTES \| ENT_SUBSTITUTE, 'UTF-8')` | `e()` |
| `comun/`, `datos/` y `pruebas/` fuera de la raíz web | `Dockerfile` |

## Pruebas

    bash panel/pruebas/probar-panel.sh http://panel.huesca.empresa.lan

El detalle de cada prueba, con la salida esperada y cómo enseñarla a mano, está en [`pruebas.md`](pruebas.md).

## Volver a los datos de ejemplo

Los cambios se guardan en el volumen `datos-panel`. Para empezar de cero (borra las altas y los cambios de miembros):

    docker compose rm -sf panel
    docker volume rm "$(docker volume ls -q | grep -E '(^|_)datos-panel$')"
    docker compose up -d panel

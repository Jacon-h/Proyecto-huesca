# Pruebas del panel (IAW RA5)

Todas las pruebas automáticas de esta página las lanza un solo script:

    bash panel/pruebas/probar-panel.sh http://panel.huesca.empresa.lan

Usuarios de ejemplo: `ana`, `luis` (investigadores), `marta`, `jorge` (responsables) y `cesar` (CESAR),
todos con la contraseña `bifi2026`.

> **Dónde se han ejecutado.** El 23/11/2026 se pasaron todas en local (servidor integrado de PHP 8.3 y
> PostgreSQL 16 con la configuración de `db/conf/`): 23 de 23 correctas. **Hay que repetirlas en la VM**
> contra `panel.huesca.empresa.lan` y guardar la salida como evidencia.

## Resumen

| Prueba | Qué se comprueba | Cómo | Resultado esperado |
|---|---|---|---|
| Panel en la sede | Sale del `compose.yaml` y responde por su nombre | `curl -I -H "Host: panel.huesca.empresa.lan" http://localhost/index.php` | `302` a `login.php` (también lo mira `web/probar.sh`) |
| A1 | Login con `password_hash` | `marta` / `bifi2026` | `302` a `index.php`; la cookie `PHPSESSID` cambia al entrar |
| A2 | Login fallido y cierre de sesión | clave mala, y usuario que no existe | El mismo mensaje en los dos casos: «Usuario o contraseña incorrectos.» |
| A3 | El perfil va en la sesión | entrar como `marta` | La cabecera dice «Marta Gil · Responsable de proyecto» |
| A5 | El menú cambia según el perfil | `ana` y `cesar` | `ana` no ve «Nuevo proyecto»; `cesar` ve «Nuevo proyecto» y «Estado de la base» |
| A8 | Cada perfil ve lo suyo | `ana` en `index.php` | Solo `BIO-0001` |
| A4 | Cambiar la URL no sirve | `marta` → `proyecto-nuevo.php`; `ana` → `proyecto.php?codigo=FIS-0002` | `403` y `404` |
| A8c | Mandar el formulario a mano no sirve | POST de `ana` y de `jorge` a `BIO-0001` | `403` (`ana` lo ve pero no lo gestiona) y `404` (`jorge` ni lo ve) |
| CSRF | Un POST sin el código del formulario | POST de `marta` sin `csrf` | `400` y no cambia nada |
| A8b | El responsable añade y quita investigadores | `marta` añade y quita a `luis` en `BIO-0001` | Aparece y desaparece de la lista; con `jorge` (no es investigador): «Ese usuario no es un investigador.» |
| A7 | Alta con validación en el servidor | `cesar` envía datos malos y luego buenos | 4 mensajes de error y no se guarda; con datos buenos se guarda y sale en la lista; código repetido: rechazado |
| A9 | Salida escapada | alta con título `<script>alert("XSS")</script>` | En la lista sale el texto; en el HTML, `&lt;script&gt;…` |
| A10 | Con la cookie de una sesión cerrada no se entra | guardar la cookie, salir, volver a usarla | Antes de salir: `200`; después: `302` a `login.php` |

## Cómo enseñarlo a mano

### A1 y A2 · Login y cierre de sesión

1. Abrir `http://panel.huesca.empresa.lan` → lleva a `login.php`.
2. DevTools → *Application* → *Cookies*: anotar `PHPSESSID`.
3. Entrar como `marta` / `bifi2026`: la cookie cambia (`session_regenerate_id(true)` en `entrar()`).
4. Probar `marta` con clave mala y `pepe` con cualquier clave: sale el mismo mensaje. `entrar()` llama a
   `password_verify()` también cuando el usuario no existe (con un hash de relleno), para que tampoco
   se note por el tiempo de respuesta.
5. Enseñar `datos-ejemplo/usuarios.json`: solo hay hashes `$2y$10$…` (bcrypt de `password_hash`).

### A3, A5, A8 · Perfil en la sesión y menú

`entrar()` guarda `usuario`, `nombre` y `perfil` en `$_SESSION['usuario']` (nunca el hash). `menu()` en
`comun/plantilla.php` lee ese perfil: el CESAR ve dos enlaces más. Entrar con `ana`, `marta` y `cesar` y
comparar el menú y la lista de proyectos.

### A4, A8b, A8c · Nadie llega a lo de otro

Con `ana` dentro, escribir en la barra `proyecto.php?codigo=FIS-0002` → «No hay ningún proyecto con ese
código entre los tuyos» (404). Es el mismo mensaje que para un código que no existe: así no se descubre
qué proyectos hay.

Formulario a mano: entrar como `ana`, abrir `BIO-0001`, y en la consola de DevTools:

```js
fetch(location.href, {method: 'POST', body: new URLSearchParams({accion: 'anadir', investigador: 'luis'})})
  .then(r => console.log(r.status))   // 403 (ana es miembro, no responsable)
```

Con `jorge` sobre `BIO-0001` → 404. La comprobación está en `proyecto.php`, antes de tocar nada:
`puede_ver()` y luego `puede_gestionar()`. Además `exigir_csrf()` rechaza el POST que no trae el código
del formulario (400).

### A7 · Alta de proyecto

Como `cesar`, «Nuevo proyecto» con código `mal`, título `x`: salen los mensajes junto a cada campo y los
valores escritos se conservan. El formulario lleva `novalidate`: el navegador no comprueba nada y aun así
el servidor (`validar_proyecto()`) lo rechaza. Con datos buenos (`BIO-0003`, título de 5 a 120
caracteres, tarifa y responsable de la lista) redirige al proyecto y aparece en «Proyectos».

### A9 · Salida escapada y qué pasa sin ella

1. Como `cesar`, dar de alta un proyecto con título `<script>alert("XSS")</script>`. En la lista se ve el
   texto tal cual; con «Ver código fuente» se ve `&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;`.
2. Qué pasaría sin escapar, sin tocar el panel:

       docker exec panel php /var/www/panel/pruebas/demo-xss.php > demo-xss.html

   Abrir `demo-xss.html` en el navegador: el mismo título pintado con `e()` se ve como texto; pintado sin
   `e()`, el script se ejecuta (el fondo se pone rojo y cambia el aviso). Un script así podría leer la
   página o enviar lo que el usuario ve a otro sitio. La cookie de sesión es `HttpOnly`, así que no podría
   leerla, pero sí actuar en nombre del usuario mientras tiene la página abierta.

### A10 · La cookie de una sesión cerrada no sirve

```bash
P=http://panel.huesca.empresa.lan
curl -s -c vieja.txt -d usuario=marta -d clave=bifi2026 $P/login.php -o /dev/null
curl -s -o /dev/null -w '%{http_code}\n' -b vieja.txt $P/index.php     # 200: la cookie vale
cp vieja.txt copia.txt                                                  # guardamos la cookie
curl -s -o /dev/null -b vieja.txt -c vieja.txt $P/logout.php            # salir
curl -s -o /dev/null -w '%{http_code}\n' -b copia.txt $P/index.php     # 302: ya no vale
```

`salir()` vacía `$_SESSION`, caduca la cookie y llama a `session_destroy()`, que borra la sesión en el
servidor. Aunque alguien conserve la cookie, el id ya no corresponde a nada; y con
`session.use_strict_mode` PHP ni siquiera lo reutiliza: crea uno nuevo y vacío.

En el navegador: entrar, copiar el valor de `PHPSESSID`, pulsar «Salir», volver a crear la cookie a mano
con ese valor en DevTools y recargar `index.php` → vuelve a `login.php`.

## Resultado de la ejecución en local (23/11/2026)

```text
OK    A1 sin sesión, index.php redirige a login
OK    A1 marta entra (302 a index.php)
OK    A1 el id de sesión cambia al entrar
OK    A2 mismo mensaje con clave mala y con usuario que no existe
OK    A5 ana (investigadora) no ve «Nuevo proyecto»
OK    A5 cesar ve «Nuevo proyecto»
OK    A3 el perfil de marta sale de la sesión
OK    A8 ana solo ve sus proyectos
OK    A4 marta abre proyecto-nuevo.php a mano: 403
OK    A4 ana cambia la URL a FIS-0002: 404
OK    A4 marta abre estado-bd.php a mano: 403
OK    A8c ana (investigadora) manda el formulario a mano: 403
OK    A8c jorge manda el formulario a un proyecto ajeno: 404
OK    CSRF: POST sin código del formulario: 400
OK    A8b marta añade a Luis
OK    A8b rechaza añadir a quien no es investigador
OK    A8b marta quita a Luis (queda como estaba)
OK    A7 datos malos: 4 mensajes de error y no se guarda
OK    A7 alta válida (TST-6948): se guarda y se lista
OK    A7 código repetido: rechazado
OK    A9 el título con <script> (TST-5426) sale escapado y no se ejecuta
OK    A10 (control) antes de salir, esa cookie entra
OK    A10 la cookie de la sesión cerrada ya no entra (302 a login)
=== IAW RA5: todas las pruebas correctas ===
```

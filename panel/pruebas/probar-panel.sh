#!/bin/bash
# panel/pruebas/probar-panel.sh · Pruebas de IAW RA5 contra el panel en marcha, con curl
#
#   bash panel/pruebas/probar-panel.sh                         (por defecto http://localhost:8081)
#   bash panel/pruebas/probar-panel.sh http://panel.huesca.empresa.lan
#
# Usa los usuarios de ejemplo (contraseña bifi2026), que instalar.sh carga en PostgreSQL. Hace como mucho
# dos altas de proyecto (A7 y A9) con un código TST-nnnn al azar; se quedan en la base, como cualquier alta
# (el panel no puede borrar proyectos: si molestan, las quita el administrador, ver panel/readme.md).
# Lo demás lo deja como estaba. Devuelve 0 si todo va bien y 1 si algo falla.
#
# Todos los formularios llevan código CSRF, también el de login y el botón «Salir». Por eso antes de cada
# POST se abre la página con la misma cookie y se saca el código del HTML, como haría un navegador.

URL="${1:-http://localhost:8081}"
CLAVE=bifi2026
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FALLOS=0

bien() { echo "OK    $*"; }
mal()  { echo "FALLO $*"; FALLOS=1; }

# codigo <usuario> <método y ruta>  → solo el código HTTP, con la cookie de ese usuario
codigo() {
    local quien="$1"; shift
    curl -s -o /dev/null -w '%{http_code}' -b "$TMP/$quien" -c "$TMP/$quien" "$@"
}
# pagina <usuario> <ruta>  → el HTML de la página
pagina() {
    curl -s -b "$TMP/$1" -c "$TMP/$1" "$URL/$2"
}
# token <usuario> <ruta>  → el código CSRF del primer formulario de esa página
token() {
    pagina "$1" "$2" | grep -o 'name="csrf" value="[^"]*"' | head -1 | cut -d'"' -f4
}
# entrar <usuario>  → hace login y deja la cookie en $TMP/<usuario>
entrar() {
    rm -f "$TMP/$1"
    local t; t=$(token "$1" login.php)
    codigo "$1" -d "usuario=$1" -d "clave=$CLAVE" -d "csrf=$t" "$URL/login.php"
}
cookie_de() { awk '$6 == "PHPSESSID" {print $7}' "$TMP/$1"; }

echo "Probando $URL"

# --- A1, A2 · Login con password_hash y mensajes ----------------------------------------------
[ "$(codigo anonimo "$URL/index.php")" = 302 ] && bien "A1 sin sesión, index.php redirige a login" || mal "A1 sin sesión"

t=$(token anonimo login.php)
antes=$(cookie_de anonimo)
cp "$TMP/anonimo" "$TMP/marta"
r=$(codigo marta -d usuario=marta -d "clave=$CLAVE" -d "csrf=$t" "$URL/login.php")
[ "$r" = 302 ] && bien "A1 marta entra (302 a index.php)" || mal "A1 login de marta: $r"
[ -n "$antes" ] && [ "$antes" != "$(cookie_de marta)" ] && bien "A1 el id de sesión cambia al entrar" || mal "A1 el id de sesión no cambia"

t=$(token fallo login.php)
m1=$(curl -s -b "$TMP/fallo" -c "$TMP/fallo" -d usuario=marta -d clave=mala -d "csrf=$t" "$URL/login.php" | grep -c 'Usuario o contraseña incorrectos')
m2=$(curl -s -b "$TMP/fallo" -c "$TMP/fallo" -d usuario=noexiste -d clave=mala -d "csrf=$t" "$URL/login.php" | grep -c 'Usuario o contraseña incorrectos')
[ "$m1" = 1 ] && [ "$m2" = 1 ] && bien "A2 mismo mensaje con clave mala y con usuario que no existe" || mal "A2 mensajes de error"

r=$(codigo sincsrf -d usuario=marta -d "clave=$CLAVE" "$URL/login.php")
[ "$r" = 400 ] && bien "CSRF: login sin código del formulario: 400 (aunque la clave sea buena)" || mal "CSRF en login: $r"

# --- A3, A5, A8 · Perfil en la sesión y menú según el perfil ----------------------------------
entrar ana >/dev/null; entrar cesar >/dev/null; entrar jorge >/dev/null
pagina ana index.php   | grep -q 'Nuevo proyecto' && mal "A5 ana ve «Nuevo proyecto»" || bien "A5 ana (investigadora) no ve «Nuevo proyecto»"
pagina cesar index.php | grep -q 'Nuevo proyecto' && bien "A5 cesar ve «Nuevo proyecto»" || mal "A5 cesar no ve «Nuevo proyecto»"
pagina marta index.php | grep -q 'Responsable de proyecto' && bien "A3 el perfil de marta sale de la sesión" || mal "A3 perfil de marta"
pagina ana index.php   | grep -q 'FIS-0002' && mal "A8 ana ve FIS-0002" || bien "A8 ana solo ve sus proyectos"

# --- A4, A8b, A8c · Nadie llega a lo de otro (URL o formulario a mano) ------------------------
[ "$(codigo marta "$URL/proyecto-nuevo.php")" = 403 ] && bien "A4 marta abre proyecto-nuevo.php a mano: 403" || mal "A4 proyecto-nuevo.php para marta"
[ "$(codigo ana "$URL/proyecto.php?codigo=FIS-0002")" = 404 ] && bien "A4 ana cambia la URL a FIS-0002: 404" || mal "A4 URL ajena"
[ "$(codigo marta "$URL/estado-bd.php")" = 403 ] && bien "A4 marta abre estado-bd.php a mano: 403" || mal "A4 estado-bd.php para marta"

# ana no tiene el formulario de miembros, pero sí el botón «Salir»: el código es el suyo de verdad.
# Así el 403 sale de la autorización (puede_gestionar) y no del CSRF.
t=$(token ana "proyecto.php?codigo=BIO-0001")
r=$(codigo ana -d accion=anadir -d investigador=luis -d "csrf=$t" "$URL/proyecto.php?codigo=BIO-0001")
[ "$r" = 403 ] && bien "A8c ana (investigadora) manda el formulario a mano: 403" || mal "A8c POST de ana: $r"
t=$(token jorge index.php)
r=$(codigo jorge -d accion=anadir -d investigador=luis -d "csrf=$t" "$URL/proyecto.php?codigo=BIO-0001")
[ "$r" = 404 ] && bien "A8c jorge manda el formulario a un proyecto ajeno: 404" || mal "A8c POST de jorge: $r"
r=$(codigo marta -d accion=anadir -d investigador=luis "$URL/proyecto.php?codigo=BIO-0001")
[ "$r" = 400 ] && bien "CSRF: POST sin código del formulario: 400" || mal "CSRF sin token: $r"

# --- A8b · El responsable añade y quita investigadores -----------------------------------------
t=$(token marta "proyecto.php?codigo=BIO-0001")
codigo marta -d accion=anadir -d investigador=luis -d "csrf=$t" "$URL/proyecto.php?codigo=BIO-0001" >/dev/null
pagina marta "proyecto.php?codigo=BIO-0001" | grep -q '<li>Luis Sanz' && bien "A8b marta añade a Luis" || mal "A8b añadir"
curl -s -b "$TMP/marta" -d accion=anadir -d investigador=jorge -d "csrf=$t" "$URL/proyecto.php?codigo=BIO-0001" \
    | grep -q 'Ese usuario no es un investigador' && bien "A8b rechaza añadir a quien no es investigador" || mal "A8b validación de miembro"
codigo marta -d accion=quitar -d investigador=luis -d "csrf=$t" "$URL/proyecto.php?codigo=BIO-0001" >/dev/null
pagina marta "proyecto.php?codigo=BIO-0001" | grep -q '<li>Luis Sanz' && mal "A8b quitar" || bien "A8b marta quita a Luis (queda como estaba)"

# --- A7 · Alta de proyecto con validación en el servidor --------------------------------------
t=$(token cesar proyecto-nuevo.php)
html=$(curl -s -b "$TMP/cesar" -d codigo=mal -d titulo=x -d tarifa=gratis -d responsable=ana -d "csrf=$t" "$URL/proyecto-nuevo.php")
n=$(echo "$html" | grep -c 'class="error"')
[ "$n" -ge 4 ] && bien "A7 datos malos: $n mensajes de error y no se guarda" || mal "A7 validación ($n errores)"

CODIGO="TST-$(printf '%04d' $((RANDOM % 10000)))"
r=$(codigo cesar -d "codigo=$CODIGO" -d "titulo=Proyecto de prueba A7" -d tarifa=academica -d responsable=marta -d "csrf=$t" "$URL/proyecto-nuevo.php")
pagina cesar index.php | grep -q "$CODIGO" && bien "A7 alta válida ($CODIGO): se guarda y se lista" || mal "A7 alta válida: $r"
curl -s -b "$TMP/cesar" -d "codigo=$CODIGO" -d "titulo=Repetido" -d tarifa=academica -d responsable=marta -d "csrf=$t" "$URL/proyecto-nuevo.php" \
    | grep -q 'Ya existe un proyecto con ese código' && bien "A7 código repetido: rechazado" || mal "A7 código repetido"

# --- A9 · Salida escapada ----------------------------------------------------------------------
CODIGO2="TST-$(printf '%04d' $((RANDOM % 10000)))"
codigo cesar -d "codigo=$CODIGO2" --data-urlencode 'titulo=<script>alert("XSS")</script>' \
      -d tarifa=academica -d responsable=marta -d "csrf=$t" "$URL/proyecto-nuevo.php" >/dev/null
html=$(pagina cesar index.php)
if echo "$html" | grep -q '&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;' && ! echo "$html" | grep -q '<script>alert'; then
    bien "A9 el título con <script> ($CODIGO2) sale escapado y no se ejecuta"
else
    mal "A9 salida sin escapar"
fi

# --- A10 · Con la cookie de una sesión cerrada no se entra -------------------------------------
entrar marta >/dev/null
cp "$TMP/marta" "$TMP/marta-vieja"              # guardamos la cookie antes de salir
[ "$(codigo marta-vieja "$URL/index.php")" = 200 ] && bien "A10 (control) antes de salir, esa cookie entra" || mal "A10 control"
codigo marta "$URL/logout.php" >/dev/null        # por GET no se cierra nada: solo redirige
[ "$(codigo marta "$URL/index.php")" = 200 ] && bien "CSRF: abrir logout.php por GET no cierra la sesión" || mal "logout por GET cierra la sesión"
t=$(token marta index.php)                       # el primer formulario de index.php es el botón «Salir»
codigo marta -d "csrf=$t" "$URL/logout.php" >/dev/null
r=$(codigo marta-vieja "$URL/index.php")
[ "$r" = 302 ] && bien "A10 la cookie de la sesión cerrada ya no entra (302 a login)" || mal "A10 cookie vieja: $r"

echo
[ "$FALLOS" -eq 0 ] && echo "=== IAW RA5: todas las pruebas correctas ===" || echo "=== IAW RA5: HAY PRUEBAS FALLIDAS ==="
exit "$FALLOS"

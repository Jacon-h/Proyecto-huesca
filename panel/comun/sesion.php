<?php
// Sesión, login, control de acceso por perfil y protección de formularios (RA5 g, h).
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';
require_once __DIR__ . '/bd.php';

/**
 * Hash de una contraseña al azar que nadie conoce. Se usa cuando el usuario no existe, para que
 * entrar() tarde lo mismo en los dos casos y no se pueda saber por el tiempo qué usuarios existen.
 */
const HASH_DE_RELLENO = '$2y$10$/jREa4yOzTWCl9P0.SAGEuEx1eKxq.S0jcSeFI/8d7JIX7I.lO132';

function iniciar_sesion(): void
{
    // (A10) Modo estricto: PHP no acepta un identificador de sesión que él no haya creado. Una cookie
    // de una sesión ya destruida (o una inventada) no se reutiliza: PHP la cambia por una nueva y vacía.
    ini_set('session.use_strict_mode', '1');
    // La sesión solo viaja en la cookie, nunca en la URL.
    ini_set('session.use_only_cookies', '1');

    session_set_cookie_params([
        'httponly' => true,   // JavaScript no puede leer la cookie de sesión
        'samesite' => 'Lax',  // no viaja en peticiones POST que vienen de otros sitios
    ]);
    session_start();
}

/** El usuario con su hash, para el login. Fuera de entrar() no se usa: el hash no sale de aquí. */
function buscar_usuario(string $usuario): ?array
{
    $fila = consultar('SELECT usuario, nombre, perfil, hash FROM usuarios WHERE usuario = ?', [$usuario])->fetch();
    return $fila === false ? null : $fila;
}

/**
 * (A1) Comprueba usuario y contraseña contra la tabla usuarios, que guarda el hash hecho con
 * password_hash(), nunca la contraseña. Si son buenos, guarda en $_SESSION['usuario'] quién es y su
 * perfil y devuelve true.
 *
 * Devuelve false tanto si el usuario no existe como si la contraseña es mala: así login.php enseña
 * el mismo mensaje en los dos casos y no se descubre qué usuarios existen.
 */
function entrar(string $usuario, string $clave): bool
{
    $u = buscar_usuario($usuario);

    // password_verify se ejecuta siempre (con el hash de relleno si el usuario no existe).
    $hash = $u === null ? HASH_DE_RELLENO : (string) $u['hash'];
    $clave_correcta = password_verify($clave, $hash);

    if ($u === null || !$clave_correcta) {
        return false;
    }

    // Id de sesión nuevo al entrar: así no vale uno que alguien hubiera fijado antes del login.
    // El código CSRF también se renueva: el de la página de login lo ha visto alguien sin identificar.
    session_regenerate_id(true);
    unset($_SESSION['csrf']);
    // (A3) En la sesión va quién es y su perfil, nunca el hash.
    $_SESSION['usuario'] = [
        'usuario' => $u['usuario'],
        'nombre'  => $u['nombre'],
        'perfil'  => $u['perfil'],
    ];
    return true;
}

/**
 * (A2, A10) Cierra la sesión de verdad: que con la cookie antigua no se pueda volver a entrar.
 */
function salir(): void
{
    $_SESSION = [];  // fuera los datos de la sesión

    // Borra la cookie del navegador, con los mismos parámetros con los que se creó.
    $c = session_get_cookie_params();
    setcookie(session_name(), '', [
        'expires'  => time() - 3600,
        'path'     => $c['path'],
        'domain'   => $c['domain'],
        'secure'   => $c['secure'],
        'httponly' => $c['httponly'],
        'samesite' => $c['samesite'],
    ]);

    // Destruye la sesión en el servidor (borra su fichero): con la cookie de antes ya no se entra.
    session_destroy();
}

function usuario_actual(): ?array
{
    return $_SESSION['usuario'] ?? null;
}

/**
 * Para las páginas que piden login: si no hay nadie en la sesión, a login.php.
 */
function exigir_login(): array
{
    $u = usuario_actual();
    if ($u === null) {
        redirigir('login.php');
    }
    return $u;
}

/**
 * (A4) Para las páginas de unos perfiles concretos: si el perfil no está en la lista, error 403.
 * Se comprueba en el servidor en cada petición: no basta con quitar el enlace del menú.
 */
function exigir_perfil(array $perfiles): array
{
    $u = exigir_login();
    if (!in_array($u['perfil'], $perfiles, true)) {
        pagina_error(403, 'No tienes permiso para ver esta página.');
    }
    return $u;
}

// ------------------------------------------------------------------ Formularios (CSRF)
// Cada formulario que cambia datos lleva un código secreto de la sesión. Si otra web intenta enviar
// el formulario en nombre del usuario, no conoce ese código y la petición se rechaza.

function token_csrf(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

/** El campo oculto que va dentro de cada <form method="post">. */
function campo_csrf(): string
{
    return '<input type="hidden" name="csrf" value="' . e(token_csrf()) . '">';
}

/** Al recibir un POST: si el código no coincide, error 400 y no se toca nada. */
function exigir_csrf(): void
{
    $recibido = (string) ($_POST['csrf'] ?? '');
    if (!hash_equals(token_csrf(), $recibido)) {
        pagina_error(400, 'El formulario ha caducado o no viene de este panel. Vuelve a cargar la página.');
    }
}

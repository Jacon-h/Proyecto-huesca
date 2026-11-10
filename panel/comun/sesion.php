<?php
// Sesión, login y control de acceso por perfil (RA5 g, h).
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';

function iniciar_sesion(): void
{
    session_set_cookie_params([
        'httponly' => true,   // JavaScript no puede leer la cookie de sesión
        'samesite' => 'Lax',  // no viaja en peticiones que vienen de otros sitios
    ]);
    session_start();
}

function buscar_usuario(string $usuario): ?array
{
    foreach (leer_datos('usuarios') as $u) {
        if ($u['usuario'] === $usuario) {
            return $u;
        }
    }
    return null;
}

/**
 * (RA5 h). Comprueba usuario y contraseña contra datos/usuarios.json, que guarda el hash, nunca
 * la contraseña. Si son buenos, guarda en $_SESSION['usuario'] quién es y su perfil y devuelve true.
 * Pistas: buscar_usuario(), password_verify(), session_regenerate_id().
 *
 * Devuelve false tanto si el usuario no existe como si la contraseña es mala: así login.php puede
 * enseñar el mismo mensaje en los dos casos y no se descubre qué usuarios existen (prueba A2).
 */
function entrar(string $usuario, string $clave): bool
{
    $u = buscar_usuario($usuario);
    if ($u === null || !password_verify($clave, (string) $u['hash'])) {
        return false;
    }

    // Id de sesión nuevo al entrar: así no vale uno que alguien hubiera fijado antes del login.
    session_regenerate_id(true);
    // En la sesión va quién es, nunca el hash.
    $_SESSION['usuario'] = [
        'usuario' => $u['usuario'],
        'nombre'  => $u['nombre'],
        'perfil'  => $u['perfil'],
    ];
    return true;
}

/**
 * (RA5 h). Cierra la sesión de verdad: que con la cookie antigua no se pueda volver a entrar.
 * Pistas: $_SESSION = [], setcookie() con fecha pasada, session_destroy().
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

    // Destruye la sesión en el servidor: con la cookie de antes ya no se entra (prueba A10).
    session_destroy();
}

function usuario_actual(): ?array
{
    return $_SESSION['usuario'] ?? null;
}

/**
 * (RA5 g, h). Para las páginas que piden login: si no hay nadie en la sesión, a login.php.
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
 * (RA5 h). Para las páginas de unos perfiles concretos: si el perfil no está en la lista,
 * error 403 con pagina_error().
 */
function exigir_perfil(array $perfiles): array
{
    $u = exigir_login();
    if (!in_array($u['perfil'], $perfiles, true)) {
        pagina_error(403, 'No tienes permiso para ver esta página.');
    }
    return $u;
}

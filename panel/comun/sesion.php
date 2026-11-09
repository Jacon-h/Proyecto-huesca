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
 * TODO (RA5 h). Comprueba usuario y contraseña contra datos/usuarios.json, que guarda el hash, nunca
 * la contraseña. Si son buenos, guarda en $_SESSION['usuario'] quién es y su perfil y devuelve true.
 * Pistas: buscar_usuario(), password_verify(), session_regenerate_id().
 */
function entrar(string $usuario, string $clave): bool
{
    return false;
}

/**
 * TODO (RA5 h). Cierra la sesión de verdad: que con la cookie antigua no se pueda volver a entrar.
 * Pistas: $_SESSION = [], setcookie() con fecha pasada, session_destroy().
 */
function salir(): void
{
}

function usuario_actual(): ?array
{
    return $_SESSION['usuario'] ?? null;
}

/**
 * TODO (RA5 g, h). Para las páginas que piden login: si no hay nadie en la sesión, a login.php.
 * Mientras no esté hecho, todo el mundo entra como CESAR. Es justo el agujero que hay que cerrar.
 */
function exigir_login(): array
{
    return usuario_actual() ?? ['usuario' => 'nadie', 'nombre' => 'Sin login', 'perfil' => 'cesar'];
}

/**
 * TODO (RA5 h). Para las páginas de unos perfiles concretos: si el perfil no está en la lista,
 * error 403 con pagina_error().
 */
function exigir_perfil(array $perfiles): array
{
    return exigir_login();
}

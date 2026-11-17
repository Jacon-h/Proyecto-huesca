<?php
// Proyectos, miembros y usos: quién ve qué (RA5 i) y validación del alta (RA5 f).
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';

/**
 * (RA5 i). La regla de aislamiento: todo lo que enseña un proyecto pasa por aquí.
 * El CESAR ve todos; un responsable, los suyos; un investigador, aquellos en los que es miembro.
 */
function puede_ver(array $u, array $proyecto): bool
{
    return match ($u['perfil']) {
        'cesar'        => true,
        'responsable'  => $proyecto['responsable'] === $u['usuario'],
        'investigador' => in_array($u['usuario'], $proyecto['miembros'], true),
        default        => false,  // un perfil que no conocemos no ve nada
    };
}

/** (RA5 i). Quién cambia los miembros de un proyecto: su responsable o el CESAR. */
function puede_gestionar(array $u, array $proyecto): bool
{
    return $u['perfil'] === 'cesar'
        || ($u['perfil'] === 'responsable' && $proyecto['responsable'] === $u['usuario']);
}

/**
 * Función propia (RA5 e, P8): el nombre de una persona a partir de su usuario. Si no existe, el
 * propio usuario. La usan index.php y proyecto.php.
 */
function nombre_de(string $usuario): string
{
    return buscar_usuario($usuario)['nombre'] ?? $usuario;
}

function proyectos_visibles(array $u): array
{
    return array_values(array_filter(leer_datos('proyectos'), fn ($p) => puede_ver($u, $p)));
}

function buscar_proyecto(string $codigo): ?array
{
    foreach (leer_datos('proyectos') as $p) {
        if ($p['codigo'] === $codigo) {
            return $p;
        }
    }
    return null;
}

function usuarios_con_perfil(string $perfil): array
{
    return array_values(array_filter(leer_datos('usuarios'), fn ($u) => $u['perfil'] === $perfil));
}

function usos_de(string $codigo): array
{
    return array_values(array_filter(leer_datos('usos'), fn ($uso) => $uso['proyecto'] === $codigo));
}

function nucleo_horas(array $usos): float
{
    return array_sum(array_map(fn ($uso) => $uso['nucleos'] * $uso['horas'], $usos));
}

/**
 * (RA5 f). Valida el formulario de alta (solo lo usa el CESAR). Devuelve [proyecto, errores]:
 * si no hay errores, el proyecto está listo para guardar. Nada de lo que llega del navegador se da
 * por bueno.
 *
 * - Código: tres letras, un guion y cuatro cifras (BIO-0003), y que no exista ya.
 * - Título: entre 5 y 120 caracteres.
 * - Tarifa: una de TARIFAS.
 * - Responsable: tiene que existir y tener perfil de responsable.
 *
 * Cada error, en $errores['campo'] con un mensaje que entienda quien rellena el formulario.
 */
function validar_proyecto(array $entrada, array $u): array
{
    $errores = [];
    $proyecto = [
        'codigo'      => trim((string) ($entrada['codigo'] ?? '')),
        'titulo'      => trim((string) ($entrada['titulo'] ?? '')),
        'responsable' => trim((string) ($entrada['responsable'] ?? '')),
        'tarifa'      => trim((string) ($entrada['tarifa'] ?? '')),
        'miembros'    => [],
    ];

    // Código: tres letras mayúsculas, guion y cuatro cifras, y que no exista ya.
    if (!preg_match('/^[A-Z]{3}-[0-9]{4}$/', $proyecto['codigo'])) {
        $errores['codigo'] = 'El código son tres letras mayúsculas, un guion y cuatro cifras (por ejemplo, BIO-0003).';
    } elseif (buscar_proyecto($proyecto['codigo']) !== null) {
        $errores['codigo'] = 'Ya existe un proyecto con ese código.';
    }

    // Título: entre 5 y 120 caracteres (mb_strlen cuenta caracteres, no bytes: una ñ es uno).
    $largo = mb_strlen($proyecto['titulo']);
    if ($largo < 5 || $largo > 120) {
        $errores['titulo'] = 'El título tiene que tener entre 5 y 120 caracteres.';
    }

    // Tarifa: una de las que existen.
    if (!array_key_exists($proyecto['tarifa'], TARIFAS)) {
        $errores['tarifa'] = 'Elige una tarifa de la lista.';
    }

    // Responsable: tiene que existir y tener perfil de responsable.
    $responsables = array_column(usuarios_con_perfil('responsable'), 'usuario');
    if (!in_array($proyecto['responsable'], $responsables, true)) {
        $errores['responsable'] = 'Elige un responsable de la lista.';
    }

    return [$proyecto, $errores];
}

/**
 * (RA5 f). Añade o quita un investigador de un proyecto (formulario de proyecto.php).
 * $entrada['accion'] es 'anadir' o 'quitar'; $entrada['investigador'], el usuario.
 * Comprobad que es un investigador que existe y que no está ya (al añadir), cambiad
 * $proyecto['miembros'] y guardad la lista de proyectos con guardar_datos('proyectos', …).
 * Devuelve un mensaje de error, o '' si ha ido bien.
 */
function gestionar_miembros(array $proyecto, array $entrada): string
{
    $accion = (string) ($entrada['accion'] ?? '');
    $investigador = trim((string) ($entrada['investigador'] ?? ''));

    if (!in_array($accion, ['anadir', 'quitar'], true)) {
        return 'Acción no válida.';
    }

    // Solo se puede añadir o quitar a un investigador que existe (el panel no crea usuarios).
    $investigadores = array_column(usuarios_con_perfil('investigador'), 'usuario');
    if (!in_array($investigador, $investigadores, true)) {
        return 'Ese usuario no es un investigador.';
    }

    $miembros = $proyecto['miembros'];
    if ($accion === 'anadir') {
        if (in_array($investigador, $miembros, true)) {
            return 'Ya es miembro del proyecto.';
        }
        $miembros[] = $investigador;
    } else {
        if (!in_array($investigador, $miembros, true)) {
            return 'No es miembro del proyecto.';
        }
        $miembros = array_values(array_diff($miembros, [$investigador]));
    }

    // Se guarda releyendo la lista completa, para cambiar solo este proyecto.
    $proyectos = leer_datos('proyectos');
    foreach ($proyectos as $i => $p) {
        if ($p['codigo'] === $proyecto['codigo']) {
            $proyectos[$i]['miembros'] = $miembros;
        }
    }
    guardar_datos('proyectos', $proyectos);
    return '';
}

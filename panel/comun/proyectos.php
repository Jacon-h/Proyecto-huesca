<?php
// Proyectos, miembros y usos: quién ve qué (RA5 i), validación del alta (RA5 f) y las consultas a la base.
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';
require_once __DIR__ . '/bd.php';

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
 * propio usuario. Los nombres se leen una vez por petición: una tabla con cinco proyectos no debería
 * costar una consulta por cada fila que se pinta.
 */
function nombre_de(string $usuario): string
{
    static $nombres = null;
    $nombres ??= consultar('SELECT usuario, nombre FROM usuarios')->fetchAll(PDO::FETCH_KEY_PAIR);
    return $nombres[$usuario] ?? $usuario;
}

// Cada proyecto con sus miembros (como lista) y sus núcleo-horas. json_agg y no array_agg porque PDO
// devuelve los arrays de PostgreSQL como texto ("{ana,luis}") y el JSON se convierte sin trucos.
const SQL_PROYECTOS = <<<'SQL'
    SELECT p.codigo, p.titulo, p.responsable, p.tarifa,
           coalesce((SELECT json_agg(m.usuario ORDER BY m.usuario)
                     FROM miembros m WHERE m.proyecto = p.codigo), '[]') AS miembros,
           coalesce((SELECT sum(u.nucleos * u.horas)
                     FROM usos u WHERE u.proyecto = p.codigo), 0)       AS nucleo_horas
    FROM proyectos p
    SQL;

function proyecto_de_fila(array $fila): array
{
    $fila['miembros'] = json_decode($fila['miembros'], true);
    $fila['nucleo_horas'] = (float) $fila['nucleo_horas'];
    return $fila;
}

/**
 * Se leen todos y se filtran con puede_ver() en vez de repetir la regla en el WHERE: así la regla de
 * quién ve qué está en un único sitio y no pueden acabar diciendo cosas distintas.
 */
function proyectos_visibles(array $u): array
{
    $proyectos = array_map('proyecto_de_fila', consultar(SQL_PROYECTOS . ' ORDER BY p.codigo')->fetchAll());
    return array_values(array_filter($proyectos, fn ($p) => puede_ver($u, $p)));
}

function buscar_proyecto(string $codigo): ?array
{
    $fila = consultar(SQL_PROYECTOS . ' WHERE p.codigo = ?', [$codigo])->fetch();
    return $fila === false ? null : proyecto_de_fila($fila);
}

function usuarios_con_perfil(string $perfil): array
{
    return consultar('SELECT usuario, nombre FROM usuarios WHERE perfil = ? ORDER BY nombre', [$perfil])->fetchAll();
}

function usos_de(string $codigo): array
{
    return consultar('SELECT usuario, maquina, nucleos, horas, fecha FROM usos
                      WHERE proyecto = ? ORDER BY fecha, id', [$codigo])->fetchAll();
}

function nucleo_horas(array $usos): float
{
    return array_sum(array_map(fn ($uso) => $uso['nucleos'] * (float) $uso['horas'], $usos));
}

/**
 * (RA5 f). Valida el formulario de alta (solo lo usa el CESAR). Devuelve [proyecto, errores]:
 * si no hay errores, el proyecto está listo para guardar. Nada de lo que llega del navegador se da
 * por bueno. La base tiene además sus propias restricciones (CHECK, claves), por si algo se escapa.
 *
 * - Código: tres letras, un guion y cuatro cifras (BIO-0003), y que no exista ya.
 * - Título: entre 5 y 120 caracteres.
 * - Tarifa: una de TARIFAS.
 * - Responsable: tiene que existir y tener perfil de responsable.
 *
 * Cada error, en $errores['campo'] con un mensaje que entienda quien rellena el formulario.
 */
function validar_proyecto(array $entrada): array
{
    $errores = [];
    $proyecto = [
        'codigo'      => trim((string) ($entrada['codigo'] ?? '')),
        'titulo'      => trim((string) ($entrada['titulo'] ?? '')),
        'responsable' => trim((string) ($entrada['responsable'] ?? '')),
        'tarifa'      => trim((string) ($entrada['tarifa'] ?? '')),
    ];

    if (!preg_match('/^[A-Z]{3}-[0-9]{4}$/', $proyecto['codigo'])) {
        $errores['codigo'] = 'El código son tres letras mayúsculas, un guion y cuatro cifras (por ejemplo, BIO-0003).';
    } elseif (buscar_proyecto($proyecto['codigo']) !== null) {
        $errores['codigo'] = 'Ya existe un proyecto con ese código.';
    }

    // mb_strlen cuenta caracteres, no bytes: una ñ es uno (igual que char_length en PostgreSQL).
    $largo = mb_strlen($proyecto['titulo']);
    if ($largo < 5 || $largo > 120) {
        $errores['titulo'] = 'El título tiene que tener entre 5 y 120 caracteres.';
    }

    if (!array_key_exists($proyecto['tarifa'], TARIFAS)) {
        $errores['tarifa'] = 'Elige una tarifa de la lista.';
    }

    $responsables = array_column(usuarios_con_perfil('responsable'), 'usuario');
    if (!in_array($proyecto['responsable'], $responsables, true)) {
        $errores['responsable'] = 'Elige un responsable de la lista.';
    }

    return [$proyecto, $errores];
}

/**
 * Guarda un proyecto ya validado. Devuelve false si el código ya existe.
 *
 * validar_proyecto() ya mira si el código está libre, pero entre esa comprobación y el INSERT otra
 * persona puede dar de alta el mismo código. La clave primaria lo impide en la base, y aquí se recoge
 * ese caso (SQLSTATE 23505, unique_violation) para enseñar el mensaje normal en vez de un error 500.
 */
function crear_proyecto(array $p): bool
{
    try {
        consultar('INSERT INTO proyectos (codigo, titulo, responsable, tarifa) VALUES (?, ?, ?, ?)',
                  [$p['codigo'], $p['titulo'], $p['responsable'], $p['tarifa']]);
        return true;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23505') {
            return false;
        }
        throw $ex;
    }
}

/**
 * (RA5 f). Añade o quita un investigador de un proyecto (formulario de proyecto.php).
 * $entrada['accion'] es 'anadir' o 'quitar'; $entrada['investigador'], el usuario.
 * Devuelve un mensaje de error, o '' si ha ido bien.
 *
 * Cada cambio es una sola sentencia, así que no hace falta abrir una transacción. Si dos personas
 * tocan el mismo miembro a la vez, ON CONFLICT y el DELETE sin filas lo dejan bien igualmente.
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

    $es_miembro = in_array($investigador, $proyecto['miembros'], true);
    if ($accion === 'anadir') {
        if ($es_miembro) {
            return 'Ya es miembro del proyecto.';
        }
        consultar('INSERT INTO miembros (proyecto, usuario) VALUES (?, ?) ON CONFLICT DO NOTHING',
                  [$proyecto['codigo'], $investigador]);
    } else {
        if (!$es_miembro) {
            return 'No es miembro del proyecto.';
        }
        consultar('DELETE FROM miembros WHERE proyecto = ? AND usuario = ?', [$proyecto['codigo'], $investigador]);
    }
    return '';
}

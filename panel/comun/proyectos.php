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

    // Título: entre 5 y 120 caracteres.
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

<?php
// Funciones generales del panel: salida segura y lectura y escritura de los datos.
declare(strict_types=1);

const DATOS = __DIR__ . '/../datos';

const PERFILES = [
    'investigador' => 'Investigador',
    'responsable'  => 'Responsable de proyecto',
    'cesar'        => 'Administración del CESAR',
];

const TARIFAS = [
    'academica' => 'Académica',
    'empresa'   => 'Empresa',
];

// Euros por núcleo y hora. Valores de ejemplo, no las tarifas reales del CESAR.
const PRECIO_NUCLEO_HORA = [
    'academica' => 0.010,
    'empresa'   => 0.035,
];

/** Escapa un texto para meterlo en HTML. Todo lo que viene del usuario o de los datos pasa por aquí. */
function e(?string $texto): string
{
    return htmlspecialchars($texto ?? '', ENT_QUOTES, 'UTF-8');
}

/** Lee datos/<nombre>.json. Si no existe o está mal, devuelve una lista vacía. */
function leer_datos(string $nombre): array
{
    $fichero = DATOS . "/$nombre.json";
    if (!is_file($fichero)) {
        return [];
    }
    $datos = json_decode((string) file_get_contents($fichero), true);
    return is_array($datos) ? $datos : [];
}

/** Guarda datos/<nombre>.json, con bloqueo para que dos peticiones a la vez no se pisen. */
function guardar_datos(string $nombre, array $datos): void
{
    $json = json_encode(array_values($datos), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    if (file_put_contents(DATOS . "/$nombre.json", $json, LOCK_EX) === false) {
        throw new RuntimeException("No se puede escribir datos/$nombre.json");
    }
}

function redirigir(string $url): never
{
    header("Location: $url");
    exit;
}

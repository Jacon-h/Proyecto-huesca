<?php
// Funciones generales del panel: salida segura, redirecciones y los valores fijos (perfiles, tarifas).
declare(strict_types=1);

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

/**
 * (A9) Escapa un texto para meterlo en HTML. Todo lo que viene del usuario o de la base pasa por aquí.
 * - ENT_QUOTES: escapa también ' y ", así vale dentro de atributos value="..." o value='...'.
 * - ENT_SUBSTITUTE: si llega UTF-8 roto, cambia los bytes malos por � en vez de devolver una cadena vacía.
 * Lo que sale: < > & " ' convertidos en &lt; &gt; &amp; &quot; &#039;. El navegador los pinta como texto.
 */
function e(?string $texto): string
{
    return htmlspecialchars($texto ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function redirigir(string $url): never
{
    header("Location: $url");
    exit;
}

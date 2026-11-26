<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

$u = exigir_perfil(['cesar']);

$errores = [];
$p = ['codigo' => '', 'titulo' => '', 'tarifa' => 'academica', 'responsable' => ''];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    exigir_csrf();
    // (A7) Validación en el servidor: el formulario lleva "novalidate" a propósito, para que se vea
    // que aunque el navegador no compruebe nada, el servidor rechaza los datos malos.
    [$p, $errores] = validar_proyecto($_POST);
    if ($errores === []) {
        if (crear_proyecto($p)) {
            redirigir('proyecto.php?codigo=' . urlencode($p['codigo']));
        }
        // Alguien lo ha dado de alta justo entre la validación y el INSERT.
        $errores['codigo'] = 'Ya existe un proyecto con ese código.';
    }
}

/** Mensaje de error de un campo, si lo hay. */
function error_de(array $errores, string $campo): string
{
    return isset($errores[$campo]) ? '<span class="error">' . e($errores[$campo]) . '</span>' : '';
}

cabecera('Nuevo proyecto', $u);
?>
<form method="post" class="tarjeta" novalidate>
  <?= campo_csrf() ?>
  <label>Código <input name="codigo" value="<?= e($p['codigo']) ?>" placeholder="BIO-0003"></label>
  <?= error_de($errores, 'codigo') ?>
  <label>Título <input name="titulo" value="<?= e($p['titulo']) ?>"></label>
  <?= error_de($errores, 'titulo') ?>
  <label>Tarifa
    <select name="tarifa">
      <?php foreach (TARIFAS as $clave => $nombre): ?>
      <option value="<?= e($clave) ?>" <?= $p['tarifa'] === $clave ? 'selected' : '' ?>><?= e($nombre) ?></option>
      <?php endforeach ?>
    </select>
  </label>
  <?= error_de($errores, 'tarifa') ?>
  <label>Responsable
    <select name="responsable">
      <?php foreach (usuarios_con_perfil('responsable') as $r): ?>
      <option value="<?= e($r['usuario']) ?>" <?= $p['responsable'] === $r['usuario'] ? 'selected' : '' ?>><?= e($r['nombre']) ?></option>
      <?php endforeach ?>
    </select>
  </label>
  <?= error_de($errores, 'responsable') ?>
  <button>Dar de alta</button>
</form>
<?php
pie();

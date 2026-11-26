<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

$u = exigir_login();
$p = buscar_proyecto((string) ($_GET['codigo'] ?? ''));

// Aislamiento (RA5 i): si no existe o no es suyo, lo mismo. ¿Por qué no un 403 cuando no es suyo?
if ($p === null || !puede_ver($u, $p)) {
    pagina_error(404, 'No hay ningún proyecto con ese código entre los tuyos.');
}

// Añadir o quitar investigadores: solo su responsable o el CESAR.
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // (A8b, A8c) La autorización se comprueba aquí, en el servidor. Ocultar los botones no basta:
    // un POST hecho a mano (curl, DevTools) llega igual.
    if (!puede_gestionar($u, $p)) {
        pagina_error(403, 'Solo el responsable del proyecto o el CESAR cambian sus miembros.');
    }
    exigir_csrf();
    $error = gestionar_miembros($p, $_POST);
    if ($error === '') {
        redirigir('proyecto.php?codigo=' . urlencode($p['codigo']));  // PRG: recargar no repite el cambio
    }
}

$usos = usos_de($p['codigo']);
if ($u['perfil'] === 'investigador') {
    $usos = array_values(array_filter($usos, fn ($uso) => $uso['usuario'] === $u['usuario']));
}
$nh = nucleo_horas($usos);
$coste = $nh * (PRECIO_NUCLEO_HORA[$p['tarifa']] ?? 0);

cabecera($p['codigo'] . ' · ' . $p['titulo'], $u);

// Solo para pintar: el consumo repartido por máquina (con los mismos usos que se enseñan en la tabla).
$por_maquina = [];
foreach ($usos as $uso) {
    $por_maquina[$uso['maquina']] = ($por_maquina[$uso['maquina']] ?? 0) + $uso['nucleos'] * $uso['horas'];
}
arsort($por_maquina);
$mayor = $por_maquina === [] ? 0 : max($por_maquina);
?>
<div class="chips">
  <span class="chip"><small>Responsable</small><strong><?= e(nombre_de($p['responsable'])) ?></strong></span>
  <span class="chip"><small>Tarifa</small><strong><span class="etiqueta etiqueta-<?= e($p['tarifa']) ?>"><?= e(TARIFAS[$p['tarifa']] ?? $p['tarifa']) ?></span></strong></span>
</div>

<section class="kpis">
  <div class="kpi"><small>Núcleo-horas</small><b data-contar="<?= round($nh, 1) ?>" data-dec="1"><?= number_format($nh, 1, ',', '.') ?></b></div>
  <div class="kpi"><small>Estimación (precios de ejemplo)</small><b data-contar="<?= round($coste, 2) ?>" data-dec="2" data-sufijo=" €"><?= number_format($coste, 2, ',', '.') ?> €</b></div>
  <div class="kpi"><small><?= $u['perfil'] === 'investigador' ? 'Tus sesiones de cálculo' : 'Sesiones de cálculo' ?></small><b data-contar="<?= count($usos) ?>"><?= count($usos) ?></b></div>
</section>

<div class="dos">
  <section class="panel">
    <h2>Miembros</h2>
    <?php if ($p['miembros'] === []): ?><p class="suave">Todavía no hay investigadores en este proyecto.</p><?php endif ?>
    <ul class="miembros">
      <?php foreach ($p['miembros'] as $m): ?>
      <li><?= e(nombre_de($m)) ?>
        <?php if (puede_gestionar($u, $p)): ?>
        <form method="post" class="en-linea"><?= campo_csrf() ?><input type="hidden" name="accion" value="quitar">
          <input type="hidden" name="investigador" value="<?= e($m) ?>"><button class="peligro">Quitar</button></form>
        <?php endif ?>
      </li>
      <?php endforeach ?>
    </ul>

    <?php if (puede_gestionar($u, $p)): ?>
    <form method="post" class="en-linea">
      <?= campo_csrf() ?>
      <input type="hidden" name="accion" value="anadir">
      <?php if ($error !== ''): ?><p class="error"><?= e($error) ?></p><?php endif ?>
      <select name="investigador">
        <?php foreach (usuarios_con_perfil('investigador') as $i): ?>
          <?php if (!in_array($i['usuario'], $p['miembros'], true)): ?>
          <option value="<?= e($i['usuario']) ?>"><?= e($i['nombre']) ?></option>
          <?php endif ?>
        <?php endforeach ?>
      </select>
      <button>Añadir al proyecto</button>
    </form>
    <?php endif ?>
  </section>

  <?php if ($por_maquina !== []): ?>
  <section class="panel">
    <h2>Reparto por máquina</h2>
    <ul class="maquinas">
      <?php foreach ($por_maquina as $maquina => $valor): ?>
      <li>
        <span class="m-nombre"><?= e((string) $maquina) ?></span>
        <span class="m-val"><?= number_format($valor, 1, ',', '.') ?> núcleo-horas</span>
        <span class="progreso" style="--w:<?= $mayor > 0 ? round($valor / $mayor * 100) : 0 ?>%"><i></i></span>
      </li>
      <?php endforeach ?>
    </ul>
  </section>
  <?php endif ?>
</div>

<section class="panel">
  <h2><?= $u['perfil'] === 'investigador' ? 'Tu consumo' : 'Consumo' ?></h2>
  <?php if ($usos === []): ?>
  <p class="suave">Todavía no hay consumo registrado.</p>
  <?php else: ?>
  <div class="tabla-wrap">
  <table class="ordenable">
    <thead>
      <tr><th>Fecha</th><th>Persona</th><th>Máquina</th><th class="num">Núcleos</th><th class="num">Horas</th><th class="num">Núcleo-horas</th></tr>
    </thead>
    <tbody>
    <?php foreach ($usos as $uso): ?>
    <tr>
      <td><?= e($uso['fecha']) ?></td>
      <td><?= e(nombre_de($uso['usuario'])) ?></td>
      <td><?= e($uso['maquina']) ?></td>
      <td class="num"><?= (int) $uso['nucleos'] ?></td>
      <td class="num"><?= number_format((float) $uso['horas'], 1, ',', '.') ?></td>
      <td class="num"><?= number_format($uso['nucleos'] * $uso['horas'], 1, ',', '.') ?></td>
    </tr>
    <?php endforeach ?>
    </tbody>
  </table>
  </div>
  <?php endif ?>
  <p class="total"><strong>Total: <?= number_format($nh, 1, ',', '.') ?> núcleo-horas ·
     estimación <?= number_format($coste, 2, ',', '.') ?> €</strong> (precios de ejemplo)</p>
</section>
<?php
pie();


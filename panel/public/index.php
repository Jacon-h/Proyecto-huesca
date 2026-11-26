<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

$u = exigir_login();
$proyectos = proyectos_visibles($u);

cabecera('Proyectos', $u);
if ($proyectos === []) {
    echo '<div class="vacio"><p>No tienes proyectos.</p></div>';
} else {
    // Solo para pintar: el consumo de cada proyecto (el mismo número de la tabla), su suma y su barra.
    $consumos = [];
    foreach ($proyectos as $i => $p) {
        $consumos[$i] = nucleo_horas(usos_de($p['codigo']));
    }
    $total = array_sum($consumos);
    $maximo = max($consumos);
    $de_empresa = count(array_filter($proyectos, fn ($p) => ($p['tarifa'] ?? '') === 'empresa'));
    ?>
<section class="kpis">
  <div class="kpi"><small>Proyectos</small><b data-contar="<?= count($proyectos) ?>"><?= count($proyectos) ?></b></div>
  <div class="kpi"><small>Núcleo-horas</small><b data-contar="<?= round($total, 1) ?>" data-dec="1"><?= number_format($total, 1, ',', '.') ?></b></div>
  <div class="kpi"><small>Con tarifa de empresa</small><b data-contar="<?= $de_empresa ?>"><?= $de_empresa ?></b></div>
</section>
    <?php if ($u['perfil'] === 'cesar'): ?>
<p class="acciones"><a class="boton" href="proyecto-nuevo.php">Nuevo proyecto</a></p>
    <?php endif ?>
<div class="tabla-wrap">
<table class="ordenable" data-filtro>
  <thead>
    <tr><th>Código</th><th>Título</th><th>Responsable</th><th>Tarifa</th><th class="num">Núcleo-horas</th></tr>
  </thead>
  <tbody>
  <?php foreach ($proyectos as $i => $p): ?>
  <tr>
    <td><a class="codigo" href="proyecto.php?codigo=<?= urlencode($p['codigo']) ?>"><?= e($p['codigo']) ?></a></td>
    <td><?= e($p['titulo']) ?></td>
    <td><?= e(nombre_de($p['responsable'])) ?></td>
    <td><span class="etiqueta etiqueta-<?= e($p['tarifa']) ?>"><?= e(TARIFAS[$p['tarifa']] ?? $p['tarifa']) ?></span></td>
    <td class="num" data-valor="<?= round($consumos[$i], 2) ?>">
      <span class="nh"><span class="progreso" style="--w:<?= $maximo > 0 ? round($consumos[$i] / $maximo * 100) : 0 ?>%"><i></i></span><span class="val"><?= number_format($consumos[$i], 1, ',', '.') ?></span></span>
    </td>
  </tr>
  <?php endforeach ?>
  </tbody>
</table>
</div>
    <?php
}
pie();

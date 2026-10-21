<?php
$host = "mi-postgres";
$port = getenv('DB_PORT') ?: 5432;
$conn = @pg_connect("host=$host port=$port dbname=" . getenv('DB_NAME') . " user=" . getenv('DB_USER') . " password=" . getenv('DB_PASSWORD'));
if (!$conn) { http_response_code(500); die('Error de conexión a PostgreSQL'); }

session_start();
if (empty($_SESSION['t'])) $_SESSION['t'] = bin2hex(random_bytes(16));

if ($_SERVER['REQUEST_METHOD'] === 'POST' && hash_equals($_SESSION['t'], $_POST['t'] ?? '')) {
    $a = $_POST['accion'] ?? '';
    $nombre = trim($_POST['nombre'] ?? '');
    $desc = trim($_POST['descripcion'] ?? '');
    $id = (int)($_POST['id'] ?? 0);
    if ($a === 'crear' && $nombre !== '')
        pg_query_params($conn, 'INSERT INTO inventario (nombre, descripcion) VALUES ($1, $2)', [$nombre, $desc]);
    elseif ($a === 'editar' && $nombre !== '' && $id > 0)
        pg_query_params($conn, 'UPDATE inventario SET nombre = $1, descripcion = $2 WHERE id = $3', [$nombre, $desc, $id]);
    elseif ($a === 'borrar' && $id > 0)
        pg_query_params($conn, 'DELETE FROM inventario WHERE id = $1', [$id]);
    header('Location: ./');
    exit;
}

$version = pg_fetch_result(pg_query($conn, 'SELECT version()'), 0, 0);
$rows = pg_fetch_all(pg_query($conn, 'SELECT id, nombre, descripcion FROM inventario ORDER BY id DESC')) ?: [];
$t = $_SESSION['t'];
function e($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Web Pública Sede Huesca</title>
<style>
* { box-sizing: border-box; }
body { margin: 0; padding: 30px 15px; font-family: "Segoe UI", Arial, sans-serif; background: #0f172a; color: #e2e8f0; }
.wrap { max-width: 860px; margin: 0 auto; background: #1e293b; border: 1px solid #334155; border-radius: 16px; overflow: hidden; }
header { padding: 24px 28px; background: #172033; border-bottom: 1px solid #334155; }
h1 { margin: 0 0 6px; font-size: 1.6rem; }
header p { margin: 3px 0; color: #94a3b8; font-size: .9rem; }
.card { margin: 24px; padding: 20px; background: #172033; border: 1px solid #334155; border-radius: 12px; }
h2 { margin: 0 0 14px; font-size: 1.05rem; color: #38bdf8; display: flex; justify-content: space-between; }
h2 small { color: #94a3b8; font-weight: 600; }
label { display: block; margin: 10px 0 5px; font-size: .75rem; font-weight: 700; color: #94a3b8; text-transform: uppercase; }
input[type=text], textarea { width: 100%; padding: 10px 12px; background: #0f172a; border: 1px solid #334155; border-radius: 8px; color: #e2e8f0; font: inherit; }
textarea { height: 70px; resize: vertical; }
button { padding: 8px 14px; border: 0; border-radius: 8px; font-weight: 700; cursor: pointer; }
.principal { width: 100%; margin-top: 14px; padding: 12px; background: #38bdf8; color: #0f172a; }
.guardar { background: #3b82f6; color: #fff; }
.borrar { background: #3f2a35; color: #f87171; border: 1px solid #7f1d1d; }
table { width: 100%; border-collapse: collapse; }
th { text-align: left; padding: 8px; font-size: .75rem; color: #94a3b8; text-transform: uppercase; border-bottom: 1px solid #334155; }
td { padding: 8px; border-bottom: 1px solid #263248; vertical-align: middle; }
td input { padding: 7px 9px; font-size: .85rem; }
.id { font-weight: 700; width: 50px; }
.acc { white-space: nowrap; width: 150px; }
@media (max-width: 640px) { .acc { width: auto; } }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Gestión de Inventario - Sede Huesca</h1>
    <p>Añade, edita, borra y consulta registros en PostgreSQL</p>
  </header>

  <div class="card">
    <h2>+ Añadir nuevo registro</h2>
    <form method="post">
      <input type="hidden" name="t" value="<?= e($t) ?>">
      <input type="hidden" name="accion" value="crear">
      <label>Nombre / Elemento *</label>
      <input type="text" name="nombre" required maxlength="100" placeholder="Ej: Servidor Web Principal">
      <label>Descripción / Detalles</label>
      <textarea name="descripcion" placeholder="Ej: Instalación Apache en Debian"></textarea>
      <button class="principal" type="submit">Guardar en base de datos</button>
    </form>
  </div>

  <div class="card">
    <h2>Registros en inventario <small>Total: <?= count($rows) ?></small></h2>
    <table>
      <tr><th>ID</th><th>Nombre</th><th>Descripción</th><th>Acciones</th></tr>
      <?php foreach ($rows as $r): ?>
      <tr>
        <form method="post">
          <input type="hidden" name="t" value="<?= e($t) ?>">
          <input type="hidden" name="id" value="<?= (int)$r['id'] ?>">
          <td class="id">#<?= (int)$r['id'] ?></td>
          <td><input type="text" name="nombre" required maxlength="100" value="<?= e($r['nombre']) ?>"></td>
          <td><input type="text" name="descripcion" value="<?= e($r['descripcion']) ?>"></td>
          <td class="acc">
            <button class="guardar" name="accion" value="editar">Guardar</button>
            <button class="borrar" name="accion" value="borrar" formnovalidate onclick="return confirm('¿Borrar el registro #<?= (int)$r['id'] ?>?')">Borrar</button>
          </td>
        </form>
      </tr>
      <?php endforeach; ?>
    </table>
  </div>
</div>
</body>
</html>
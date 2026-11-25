<?php
/* ============================================================
   Web pública Sede Huesca · Gestión de inventario (PostgreSQL)
   Crear, editar y borrar registros sin recargar la página (fetch).
   Si JavaScript no está disponible, el formulario de alta sigue funcionando.
   ============================================================ */

function dsn() {   // cadena de conexión que admite contraseñas con espacios o comillas
    $p = ['host' => getenv('DB_HOST') ?: 'db', 'port' => '5432', 'dbname' => getenv('DB_NAME'),
          'user' => getenv('DB_USER'), 'password' => getenv('DB_PASSWORD')];
    $s = '';
    foreach ($p as $k => $v) $s .= "$k='" . addcslashes((string)$v, "'\\") . "' ";
    return $s;
}

function e($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

function responder($ok, $datos = [], $codigo = 200) {
    http_response_code($codigo);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode(array_merge(['ok' => $ok], $datos), JSON_UNESCAPED_UNICODE);
    exit;
}

function pagina_error() {
    http_response_code(500);
    ?><!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Sin conexión · Sede Huesca</title>
<style>
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;font-family:Inter,"Segoe UI",system-ui,sans-serif;color:#eaf0ff;
background:radial-gradient(800px 500px at 15% -10%,rgba(56,189,248,.14),transparent 60%),linear-gradient(#0b132b,#060b1c)}
.box{max-width:460px;padding:30px;border-radius:18px;background:rgba(16,26,56,.75);border:1px solid #1f2d52}
h1{margin:0 0 8px;font-size:1.4rem}p{margin:0 0 10px;color:#8d9cc6;line-height:1.5}
a{display:inline-block;margin-top:8px;padding:9px 16px;border-radius:10px;background:#38bdf8;color:#04101f;font-weight:600;text-decoration:none}
</style></head><body><div class="box"><h1>No se pudo conectar con la base de datos</h1>
<p>El inventario está temporalmente fuera de servicio. Comprueba que el contenedor de PostgreSQL está activo y vuelve a intentarlo.</p>
<a href="./">Reintentar</a></div></body></html><?php
    exit;
}

$conn = @pg_connect(dsn());
if (!$conn) pagina_error();

session_start();
if (empty($_SESSION['t'])) $_SESSION['t'] = bin2hex(random_bytes(16));

/* ¿Existe la columna creado_en? Si no, la web funciona igual sin fechas. */
$rf = @pg_query($conn, "SELECT 1 FROM information_schema.columns WHERE table_name = 'inventario' AND column_name = 'creado_en'");
$tieneFecha = $rf && pg_num_rows($rf) > 0;
$extra = $tieneFecha ? ", to_char(creado_en, 'DD/MM HH24:MI') AS fecha, (creado_en::date = current_date) AS hoy" : '';

/* ---------- Altas, ediciones y borrados ---------- */
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $ajax = ($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '') === 'fetch';
    if (!hash_equals($_SESSION['t'], (string)($_POST['t'] ?? ''))) {
        if ($ajax) responder(false, ['error' => 'La sesión ha caducado. Recarga la página.'], 403);
        header('Location: ./'); exit;
    }
    $a      = $_POST['accion'] ?? '';
    $nombre = trim($_POST['nombre'] ?? '');
    $desc   = trim($_POST['descripcion'] ?? '');
    $id     = (int)($_POST['id'] ?? 0);
    $error  = null; $fila = null;

    if ($a === 'crear' || $a === 'editar') {
        if ($nombre === '')                 $error = 'El nombre es obligatorio.';
        elseif (mb_strlen($nombre) > 100)   $error = 'El nombre admite 100 caracteres como máximo.';
        elseif (mb_strlen($desc) > 500)     $error = 'La descripción admite 500 caracteres como máximo.';
    }

    if (!$error) {
        if ($a === 'crear') {
            $res = @pg_query_params($conn, 'INSERT INTO inventario (nombre, descripcion) VALUES ($1, $2) RETURNING id, nombre, descripcion' . $extra, [$nombre, $desc]);
            if ($res) $fila = pg_fetch_assoc($res); else $error = 'No se pudo guardar el registro.';
        } elseif ($a === 'editar' && $id > 0) {
            $res = @pg_query_params($conn, 'UPDATE inventario SET nombre = $1, descripcion = $2 WHERE id = $3 RETURNING id, nombre, descripcion' . $extra, [$nombre, $desc, $id]);
            if (!$res) $error = 'No se pudo guardar el cambio.';
            elseif (($fila = pg_fetch_assoc($res)) === false) $error = 'El registro ya no existe.';
        } elseif ($a === 'borrar' && $id > 0) {
            $res = @pg_query_params($conn, 'DELETE FROM inventario WHERE id = $1', [$id]);
            if (!$res) {
                $error = stripos(pg_last_error($conn), 'permission denied') !== false
                    ? 'La base de datos no permite borrar a este usuario (falta el permiso DELETE sobre inventario).'
                    : 'No se pudo borrar el registro.';
            } elseif (pg_affected_rows($res) === 0) $error = 'El registro ya no existe.';
        } else $error = 'Acción no válida.';
    }

    if ($ajax) {
        if ($error) responder(false, ['error' => $error], 422);
        responder(true, ['fila' => $fila]);
    }
    header('Location: ./'); exit;
}

/* ---------- Lectura ---------- */
$versionRaw = pg_fetch_result(pg_query($conn, 'SELECT version()'), 0, 0);
$version = preg_match('/PostgreSQL\s+[\d.]+/', $versionRaw, $m) ? $m[0] : 'PostgreSQL';
$rows = pg_fetch_all(pg_query($conn, 'SELECT id, nombre, descripcion' . $extra . ' FROM inventario ORDER BY id DESC')) ?: [];
$t = $_SESSION['t'];
$flags = JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_UNESCAPED_UNICODE;
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Inventario · Sede Huesca</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@500;700&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#060b1c; --bg2:#0b132b; --panel:rgba(16,26,56,.72); --line:#1f2d52; --line2:#2b3c6b;
  --ink:#eaf0ff; --mute:#8d9cc6; --faint:#5d6c96;
  --cyan:#38bdf8; --mint:#34d399; --amber:#fbbf24; --coral:#fb7185; --violet:#a78bfa;
  --display:'Space Grotesk','Inter',system-ui,sans-serif; --text:'Inter',system-ui,sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
html{color-scheme:dark}
body{font-family:var(--text);color:var(--ink);min-height:100vh;font-size:14px;line-height:1.45;
  background:radial-gradient(900px 500px at 12% -10%,rgba(56,189,248,.14),transparent 60%),radial-gradient(800px 500px at 100% 0%,rgba(167,139,250,.10),transparent 55%),linear-gradient(var(--bg2),var(--bg)) fixed}
body::before{content:"";position:fixed;inset:0;pointer-events:none;opacity:.5;
  background-image:linear-gradient(rgba(255,255,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px);
  background-size:44px 44px;mask-image:radial-gradient(ellipse at top,#000 20%,transparent 75%);-webkit-mask-image:radial-gradient(ellipse at top,#000 20%,transparent 75%)}
.wrap{position:relative;max-width:960px;margin:0 auto;padding:30px 20px 80px}
:focus-visible{outline:2px solid var(--cyan);outline-offset:2px;border-radius:6px}
.num{font-variant-numeric:tabular-nums}
mark{background:rgba(251,191,36,.28);color:inherit;border-radius:3px;padding:0 1px}

/* Cabecera */
.top{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;flex-wrap:wrap;margin-bottom:22px}
.top h1{font-family:var(--display);font-size:2rem;font-weight:700;letter-spacing:-.02em;line-height:1.1}
.top h1 small{display:block;font-family:var(--text);font-weight:400;font-size:.88rem;color:var(--mute);letter-spacing:0;margin-top:7px;max-width:52ch}
.top .side{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.chip{display:inline-flex;align-items:center;gap:8px;padding:6px 13px;border-radius:999px;font-size:.8rem;font-weight:600;background:rgba(52,211,153,.12);color:var(--mint);border:1px solid rgba(52,211,153,.3)}
.chip i{width:8px;height:8px;border-radius:50%;background:currentColor;box-shadow:0 0 8px currentColor}
.link{color:var(--ink);text-decoration:none;font-weight:500;padding:7px 14px;border-radius:10px;border:1px solid var(--line);background:rgba(16,26,56,.6);transition:background .15s,color .15s,border-color .15s}
.link:hover{background:var(--cyan);color:#04101f;border-color:var(--cyan)}

/* Indicadores */
.kpis{display:grid;grid-template-columns:1fr 1.5fr 1fr;gap:14px;margin-bottom:18px}
.kpi{padding:16px 18px;border-radius:16px;background:var(--panel);border:1px solid var(--line);min-width:0}
.kpi small{display:block;color:var(--mute);font-size:.78rem;margin-bottom:4px}
.kpi b{display:block;font-family:var(--display);font-size:1.8rem;font-weight:700;letter-spacing:-.02em;line-height:1.15;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.kpi b.txt{font-size:1.2rem;padding-top:7px}
@media(max-width:640px){.kpis{grid-template-columns:1fr 1fr}.kpi:nth-child(2){grid-column:span 2;order:3}}

/* Paneles */
.p{background:var(--panel);border:1px solid var(--line);border-radius:18px;padding:22px;backdrop-filter:blur(8px);margin-bottom:18px}
.ph{display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin-bottom:14px;flex-wrap:wrap}
.ph h2{font-family:var(--display);font-size:1.12rem;font-weight:700;letter-spacing:-.01em}
.ph .hint{color:var(--mute);font-size:.8rem}

/* Formulario de alta */
.alta{display:grid;grid-template-columns:1fr 1.5fr auto;gap:12px;align-items:end}
.f label{display:block;margin-bottom:6px;font-size:.8rem;font-weight:500;color:var(--mute)}
input[type=text],input[type=search],select{width:100%;padding:10px 13px;background:rgba(6,11,28,.6);border:1px solid var(--line2);border-radius:11px;color:var(--ink);font:inherit;transition:border-color .15s}
input::placeholder{color:var(--faint)}
input:focus,select:focus{border-color:var(--cyan);outline:none;box-shadow:0 0 0 3px rgba(56,189,248,.18)}
.b{font:inherit;font-weight:600;border:1px solid var(--line2);background:rgba(16,26,56,.8);color:var(--ink);padding:8px 14px;border-radius:10px;cursor:pointer;white-space:nowrap;transition:background .15s,color .15s,border-color .15s}
.b:hover{border-color:var(--cyan);color:var(--cyan)}
.b.main{background:var(--cyan);border-color:var(--cyan);color:#04101f;padding:10px 20px}
.b.main:hover{background:#7dd3fc;color:#04101f}
.b.ok{background:var(--cyan);border-color:var(--cyan);color:#04101f}
.b.ok:hover{background:#7dd3fc;color:#04101f}
.b.danger:hover{border-color:var(--coral);color:var(--coral)}
.b.sure{background:var(--coral);border-color:var(--coral);color:#1d0309}
.b.sure:hover{background:#fda4af;color:#1d0309}
.b:disabled{opacity:.5;cursor:wait}
.err{color:var(--coral);font-size:.82rem;margin-top:10px;min-height:1.2em}
@media(max-width:760px){.alta{grid-template-columns:1fr}.b.main{width:100%}}

/* Barra de herramientas */
.tools{display:grid;grid-template-columns:1fr 190px;gap:12px;margin-bottom:14px}
@media(max-width:560px){.tools{grid-template-columns:1fr}}

/* Lista */
.lista{list-style:none;display:flex;flex-direction:column;gap:9px}
.it{display:grid;grid-template-columns:auto 1fr auto;gap:14px;align-items:center;padding:12px 14px;border-radius:14px;background:rgba(6,11,28,.45);border:1px solid var(--line);transition:border-color .2s,background .2s,opacity .3s,transform .3s}
.it:hover{border-color:var(--line2)}
.it.nuevo{animation:nuevo .7s ease-out}
@keyframes nuevo{from{background:rgba(56,189,248,.25);transform:translateY(-8px);opacity:0}to{background:rgba(6,11,28,.45);transform:none;opacity:1}}
.it.saliendo{opacity:0;transform:translateX(26px)}
.it.confirm{border-color:rgba(251,113,133,.5);background:rgba(251,113,133,.07)}
.av{width:42px;height:42px;display:grid;place-items:center;border-radius:12px;font-size:1.25rem;border:1px solid}
.main-col{min-width:0}
.main-col b{display:block;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.main-col span{display:block;color:var(--mute);font-size:.84rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.main-col span.vacia{color:var(--faint);font-style:italic}
.meta{color:var(--faint);font-size:.74rem;margin-top:2px}
.acts{display:flex;gap:8px;align-items:center}
.acts .q{color:var(--coral);font-size:.84rem;font-weight:500;margin-right:4px}
.fields{display:grid;grid-template-columns:1fr 1.6fr;gap:8px;min-width:0}
.it.editing{border-color:var(--cyan);background:rgba(56,189,248,.06)}
@media(max-width:700px){.it{grid-template-columns:auto 1fr}.acts{grid-column:1/-1;justify-content:flex-end;flex-wrap:wrap}.fields{grid-template-columns:1fr}}

.vacio{padding:26px;text-align:center;border-radius:14px;border:1px dashed var(--line2);color:var(--mute)}
.vacio b{display:block;color:var(--ink);font-family:var(--display);font-size:1.05rem;margin-bottom:4px}
.vacio .b{margin-top:12px}
.mas{display:flex;justify-content:space-between;align-items:center;margin-top:14px;color:var(--mute);font-size:.82rem;gap:10px;flex-wrap:wrap}

/* Avisos */
#toasts{position:fixed;right:18px;bottom:18px;display:flex;flex-direction:column;gap:10px;z-index:20;max-width:min(380px,calc(100vw - 36px))}
.toast{padding:12px 16px;border-radius:12px;background:#0a1330;border:1px solid var(--line2);box-shadow:0 10px 30px rgba(0,0,0,.4);font-size:.86rem;border-left:4px solid var(--mint);animation:toast .25s ease-out}
.toast.error{border-left-color:var(--coral)}
@keyframes toast{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}

@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>
</head>
<body>
<div class="wrap">

  <header class="top">
    <h1>Inventario Sede Huesca
      <small>Añade, edita y borra los elementos de la sede. Todo se guarda al momento en PostgreSQL.</small>
    </h1>
    <div class="side">
      <span class="chip"><i></i><?= e($version) ?> conectado</span>
      <a class="link" href="http://intranet.huesca.empresa.lan">Ir a la intranet</a>
    </div>
  </header>

  <section class="kpis" aria-label="Resumen">
    <div class="kpi"><small>Registros</small><b class="num" id="k-total" data-v="0">0</b></div>
    <div class="kpi"><small>Último añadido</small><b class="txt" id="k-ultimo">—</b></div>
    <div class="kpi"><small id="k3-l"><?= $tieneFecha ? 'Añadidos hoy' : 'Sin descripción' ?></small><b class="num" id="k-tres" data-v="0">0</b></div>
  </section>

  <section class="p" aria-labelledby="h-alta">
    <div class="ph"><h2 id="h-alta">Nuevo registro</h2></div>
    <form method="post" id="form-alta">
      <input type="hidden" name="t" value="<?= e($t) ?>">
      <input type="hidden" name="accion" value="crear">
      <div class="alta">
        <div class="f"><label for="a-nombre">Nombre *</label><input type="text" id="a-nombre" name="nombre" required maxlength="100" placeholder="Ej: Servidor web principal" autocomplete="off"></div>
        <div class="f"><label for="a-desc">Descripción</label><input type="text" id="a-desc" name="descripcion" maxlength="500" placeholder="Ej: Apache sobre Debian en la sala de servidores" autocomplete="off"></div>
        <button class="b main" type="submit" id="a-btn">Guardar</button>
      </div>
      <p class="err" id="a-err" role="alert"></p>
    </form>
  </section>

  <section class="p" aria-labelledby="h-reg">
    <div class="ph"><h2 id="h-reg">Registros</h2><span class="hint" id="contador" aria-live="polite"></span></div>
    <div class="tools">
      <input type="search" id="q" placeholder="Buscar por nombre, descripción o #id" aria-label="Buscar registros" autocomplete="off">
      <select id="orden" aria-label="Ordenar por">
        <option value="rec">Más recientes</option>
        <option value="ant">Más antiguos</option>
        <option value="az">Nombre A–Z</option>
        <option value="za">Nombre Z–A</option>
      </select>
    </div>
    <ul class="lista" id="lista"></ul>
    <div class="mas" id="mas"></div>
    <noscript><p class="err">Activa JavaScript para ver y gestionar los registros.</p></noscript>
  </section>
</div>
<div id="toasts" aria-live="polite"></div>

<script>
const T = <?= json_encode($t, $flags) ?>;
const HAS_DATE = <?= $tieneFecha ? 'true' : 'false' ?>;
const norm = r => ({id:+r.id, nombre:r.nombre, descripcion:r.descripcion || '', fecha:r.fecha || null, hoy:r.hoy === 't' || r.hoy === true});
let DATA = <?= json_encode($rows, $flags) ?>.map(norm);

const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const S = {q:'', orden:'rec', limite:10, edit:null, confirm:null, flash:null, busy:false};

/* ---------- API ---------- */
async function api(accion, campos) {
  const fd = new FormData(); fd.append('t', T); fd.append('accion', accion);
  for (const k in campos) fd.append(k, campos[k]);
  let r, j;
  try { r = await fetch('./', {method:'POST', body:fd, headers:{'X-Requested-With':'fetch'}}); j = await r.json(); }
  catch (e) { throw new Error('No se pudo contactar con el servidor.'); }
  if (!j.ok) throw new Error(j.error || 'Error inesperado.');
  return j;
}

/* ---------- utilidades visuales ---------- */
const ICONOS = [[/servidor|server|proxmox|vm\b/i,'🖥️'],[/router|switch|vlan|firewall|red\b|wifi|ap\b/i,'🌐'],[/base de datos|postgres|sql|\bbd\b/i,'🗄️'],
  [/port[áa]til|laptop|pc\b|ordenador|equipo/i,'💻'],[/impresora|printer/i,'🖨️'],[/sai|ups|cable|rack|regleta/i,'🔌'],[/disco|nas|backup|copia|ssd|hdd/i,'💾'],
  [/c[áa]mara|cctv|sensor/i,'📷'],[/m[óo]vil|tel[ée]fono|tablet/i,'📱']];
const icono = n => (ICONOS.find(([re]) => re.test(n)) || [0,'📦'])[1];
const hue = n => { let h = 0; for (const c of n) h = (h*31 + c.charCodeAt(0)) % 360; return h; };
const hl = t => {
  if (!S.q) return esc(t);
  const re = new RegExp('(' + S.q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig');
  return String(t).split(re).map((p, i) => i % 2 ? '<mark>' + esc(p) + '</mark>' : esc(p)).join('');
};
function countTo(el, n) {
  const from = +el.dataset.v || 0; el.dataset.v = n; if (from === n) { el.textContent = n; return; }
  const t0 = performance.now();
  (function f(t) { const k = Math.min(1, (t - t0)/500); el.textContent = Math.round(from + (n - from)*k); if (k < 1) requestAnimationFrame(f); })(t0);
}
function toast(msg, tipo = 'ok') {
  const el = document.createElement('div'); el.className = 'toast ' + (tipo === 'error' ? 'error' : ''); el.textContent = msg;
  $('#toasts').appendChild(el); setTimeout(() => el.remove(), tipo === 'error' ? 7000 : 3500);
}

/* ---------- pintado ---------- */
function filtrados() {
  const q = S.q.toLowerCase();
  let a = DATA.filter(r => !q || r.nombre.toLowerCase().includes(q) || r.descripcion.toLowerCase().includes(q) || ('#' + r.id) === q || String(r.id) === q);
  const cmp = {rec:(x, y) => y.id - x.id, ant:(x, y) => x.id - y.id, az:(x, y) => x.nombre.localeCompare(y.nombre, 'es'), za:(x, y) => y.nombre.localeCompare(x.nombre, 'es')}[S.orden];
  return a.sort(cmp);
}
function item(r) {
  const h = hue(r.nombre), av = `style="background:hsl(${h} 55% 22%);border-color:hsl(${h} 55% 42%)"`;
  const cls = 'it' + (S.edit === r.id ? ' editing' : '') + (S.confirm === r.id ? ' confirm' : '') + (S.flash === r.id ? ' nuevo' : '');
  if (S.edit === r.id) return `<li class="${cls}" data-id="${r.id}"><span class="av" ${av}>${icono(r.nombre)}</span>
    <div class="fields"><input type="text" class="e-nombre" maxlength="100" value="${esc(r.nombre)}" aria-label="Nombre"><input type="text" class="e-desc" maxlength="500" value="${esc(r.descripcion)}" aria-label="Descripción"></div>
    <div class="acts"><button class="b ok" data-a="save">Guardar</button><button class="b" data-a="cancel">Cancelar</button></div></li>`;
  const acts = S.confirm === r.id
    ? `<span class="q">¿Borrar este registro?</span><button class="b sure" data-a="del">Sí, borrar</button><button class="b" data-a="nodel">Cancelar</button>`
    : `<button class="b" data-a="edit">Editar</button><button class="b danger" data-a="ask">Borrar</button>`;
  return `<li class="${cls}" data-id="${r.id}"><span class="av" ${av}>${icono(r.nombre)}</span>
    <div class="main-col"><b>${hl(r.nombre)}</b>${r.descripcion ? `<span>${hl(r.descripcion)}</span>` : '<span class="vacia">Sin descripción</span>'}
    <div class="meta num">#${r.id}${r.fecha ? ' · ' + esc(r.fecha) : ''}</div></div><div class="acts">${acts}</div></li>`;
}
function render() {
  const todos = filtrados(), vis = todos.slice(0, S.limite), lista = $('#lista');
  if (!DATA.length) lista.innerHTML = '<li class="vacio"><b>Todavía no hay registros</b>Añade el primero con el formulario de arriba.</li>';
  else if (!todos.length) lista.innerHTML = `<li class="vacio"><b>Nada coincide con «${esc(S.q)}»</b>Prueba con otra palabra o quita el filtro.<br><button class="b" data-a="clear">Quitar filtro</button></li>`;
  else lista.innerHTML = vis.map(item).join('');
  S.flash = null;
  $('#contador').textContent = DATA.length ? `Mostrando ${vis.length} de ${todos.length}${todos.length !== DATA.length ? ' (filtrado de ' + DATA.length + ')' : ''}` : '';
  const resto = todos.length - vis.length;
  $('#mas').innerHTML = resto > 0 ? `<span>Quedan ${resto} más</span><button class="b" data-a="more">Ver más</button>` : '';
  kpis();
}
function kpis() {
  countTo($('#k-total'), DATA.length);
  const ult = DATA.reduce((m, r) => !m || r.id > m.id ? r : m, null);
  $('#k-ultimo').textContent = ult ? ult.nombre : '—'; $('#k-ultimo').title = ult ? ult.nombre : '';
  countTo($('#k-tres'), HAS_DATE ? DATA.filter(r => r.hoy).length : DATA.filter(r => !r.descripcion).length);
}

/* ---------- acciones ---------- */
$('#form-alta').addEventListener('submit', async ev => {
  ev.preventDefault(); if (S.busy) return;
  const nombre = $('#a-nombre').value.trim(), desc = $('#a-desc').value.trim(), btn = $('#a-btn'), err = $('#a-err');
  err.textContent = ''; if (!nombre) { err.textContent = 'El nombre es obligatorio.'; $('#a-nombre').focus(); return; }
  S.busy = true; btn.disabled = true;
  try {
    const j = await api('crear', {nombre, descripcion:desc});
    const fila = norm(j.fila); DATA.unshift(fila);
    S.q = ''; $('#q').value = ''; S.orden = 'rec'; $('#orden').value = 'rec'; S.edit = S.confirm = null; S.flash = fila.id;
    render(); ev.target.reset(); $('#a-nombre').focus(); toast('Añadido: ' + fila.nombre);
  } catch (e) { err.textContent = e.message; }
  finally { S.busy = false; btn.disabled = false; }
});

$('#q').addEventListener('input', e => { S.q = e.target.value.trim(); S.limite = 10; S.edit = S.confirm = null; render(); });
$('#orden').addEventListener('change', e => { S.orden = e.target.value; render(); });

async function guardar(li) {
  const id = +li.dataset.id, nombre = li.querySelector('.e-nombre').value.trim(), desc = li.querySelector('.e-desc').value.trim();
  if (!nombre) { toast('El nombre no puede quedar vacío.', 'error'); li.querySelector('.e-nombre').focus(); return; }
  S.busy = true; li.querySelectorAll('button').forEach(b => b.disabled = true);
  try {
    const j = await api('editar', {id, nombre, descripcion:desc}), i = DATA.findIndex(r => r.id === id);
    if (i >= 0) DATA[i] = norm(j.fila);
    S.edit = null; S.flash = id; render(); toast('Cambios guardados');
  } catch (e) { toast(e.message, 'error'); li.querySelectorAll('button').forEach(b => b.disabled = false); }
  finally { S.busy = false; }
}
async function borrar(li) {
  const id = +li.dataset.id; S.busy = true; li.querySelectorAll('button').forEach(b => b.disabled = true);
  try {
    await api('borrar', {id});
    li.classList.add('saliendo');
    setTimeout(() => { DATA = DATA.filter(r => r.id !== id); S.confirm = null; render(); toast('Registro borrado'); }, 300);
  } catch (e) { S.confirm = null; render(); toast(e.message, 'error'); }
  finally { S.busy = false; }
}

document.addEventListener('click', ev => {
  const b = ev.target.closest('button[data-a]'); if (!b || S.busy) return;
  const li = b.closest('li'), a = b.dataset.a;
  if (a === 'edit')   { S.edit = +li.dataset.id; S.confirm = null; render(); const i = $('.e-nombre'); i && (i.focus(), i.select()); }
  else if (a === 'cancel') { S.edit = null; render(); }
  else if (a === 'save')   guardar(li);
  else if (a === 'ask')    { S.confirm = +li.dataset.id; S.edit = null; render(); }
  else if (a === 'nodel')  { S.confirm = null; render(); }
  else if (a === 'del')    borrar(li);
  else if (a === 'more')   { S.limite += 10; render(); }
  else if (a === 'clear')  { S.q = ''; $('#q').value = ''; render(); }
});
$('#lista').addEventListener('keydown', ev => {
  const li = ev.target.closest('li.editing'); if (!li) return;
  if (ev.key === 'Enter') { ev.preventDefault(); guardar(li); }
  if (ev.key === 'Escape') { S.edit = null; render(); }
});

render();
</script>
</body>
</html>

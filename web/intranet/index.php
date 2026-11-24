<?php
/* ============================================================
   Intranet Sede Huesca · estado de servicios + rendimiento
   - ?api=1  -> devuelve las métricas en JSON (la página lo consulta cada pocos segundos)
   - Métricas del servidor: /proc (CPU, RAM, carga, disco)
   - Métricas por contenedor: API de Docker (vía dockerproxy, solo lectura)
   ============================================================ */

$servicios = [
    'Servidor Web (Apache)'        => ['host' => '127.0.0.1', 'port' => 80,   'icono' => '🌐'],
    'Base de Datos (PostgreSQL)'   => ['host' => 'db',        'port' => 5432, 'icono' => '🗄️'],
    'Servicio Git (Forgejo)'       => ['host' => 'git',       'port' => 3000, 'icono' => '📦'],
    'Servidor DNS (BIND9)'         => ['host' => 'host.docker.internal', 'port' => 53, 'icono' => '🌍'],
    'Directorio (OpenLDAP)'        => ['host' => 'ldap',      'port' => 389,  'icono' => '🔑'],
    'Gestor LDAP (LAM)'            => ['host' => 'lam',       'port' => 80,   'icono' => '👥'],
    'Panel del BIFI (Reto 1)'      => ['host' => 'panel',     'port' => 80,   'icono' => '📊']
];

/* Nombres legibles para los contenedores (clave = nombre del servicio en compose.yaml) */
$nombres_amigables = [
    'web'         => 'Servidor Web (Apache)',
    'db'          => 'Base de Datos (PostgreSQL)',
    'git'         => 'Servicio Git (Forgejo)',
    'dns'         => 'Servidor DNS (BIND9)',
    'ldap'        => 'Directorio (OpenLDAP)',
    'lam'         => 'Gestor LDAP (LAM)',
    'panel'       => 'Panel del BIFI',
    'dockerproxy' => 'Proxy Docker (métricas)',
];
/* Por si algún contenedor no se creó con compose: se adivina por su nombre */
$pistas_nombre = [
    '/apache/' => 'web', '/postgres/' => 'db', '/forgejo/' => 'git', '/bind/' => 'dns',
    '/openldap|ldap/' => 'ldap', '/lam/' => 'lam', '/panel/' => 'panel', '/dockerproxy|socket-proxy/' => 'dockerproxy',
];

/* ---------- utilidades ---------- */

function verificar_puerto($host, $port) {
    $t = microtime(true);
    $c = @fsockopen($host, $port, $errno, $errstr, 0.8);
    if (is_resource($c)) {
        fclose($c);
        return [true, round((microtime(true) - $t) * 1000, 1)];
    }
    return [false, null];
}

function cpu_muestra() {
    $l = @file('/proc/stat', FILE_IGNORE_NEW_LINES);
    if (!$l) return null;
    $cores = 0; $tot = 0; $idle = 0;
    foreach ($l as $r) {
        if (preg_match('/^cpu\d+/', $r)) { $cores++; }
        elseif (strpos($r, 'cpu ') === 0) {
            $p = array_map('intval', array_slice(preg_split('/\s+/', trim($r)), 1));
            $tot  = array_sum(array_slice($p, 0, 8));
            $idle = ($p[3] ?? 0) + ($p[4] ?? 0);
        }
    }
    return ['tot' => $tot, 'idle' => $idle, 'cores' => max(1, $cores)];
}

function meminfo() {
    $m = [];
    foreach ((@file('/proc/meminfo', FILE_IGNORE_NEW_LINES) ?: []) as $r) {
        if (preg_match('/^(\w+):\s+(\d+)/', $r, $x)) $m[$x[1]] = (int)$x[2] * 1024;
    }
    return $m;
}

function docker_ch($ruta) {
    $api = getenv('DOCKER_API') ?: 'http://dockerproxy:2375';
    $ch = curl_init();
    if (strpos($api, 'unix://') === 0) {
        curl_setopt($ch, CURLOPT_UNIX_SOCKET_PATH, substr($api, 7));
        $url = 'http://localhost' . $ruta;
    } else {
        $url = rtrim($api, '/') . $ruta;
    }
    curl_setopt_array($ch, [CURLOPT_URL => $url, CURLOPT_RETURNTRANSFER => true,
                            CURLOPT_CONNECTTIMEOUT => 2, CURLOPT_TIMEOUT => 8]);
    return $ch;
}

function procesar_stats($s) {
    $cpu = 0;
    $cd = ($s['cpu_stats']['cpu_usage']['total_usage'] ?? 0) - ($s['precpu_stats']['cpu_usage']['total_usage'] ?? 0);
    $sd = ($s['cpu_stats']['system_cpu_usage'] ?? 0) - ($s['precpu_stats']['system_cpu_usage'] ?? 0);
    $n  = $s['cpu_stats']['online_cpus'] ?? max(1, count($s['cpu_stats']['cpu_usage']['percpu_usage'] ?? []));
    if ($sd > 0 && $cd >= 0) $cpu = $cd / $sd * $n * 100;

    $m = $s['memory_stats'] ?? [];
    $st = $m['stats'] ?? [];
    $cache = $st['inactive_file'] ?? ($st['total_inactive_file'] ?? ($st['cache'] ?? 0));
    $mem = max(0, ($m['usage'] ?? 0) - $cache);

    $rx = 0; $tx = 0;
    foreach (($s['networks'] ?? []) as $net) { $rx += $net['rx_bytes'] ?? 0; $tx += $net['tx_bytes'] ?? 0; }

    $br = 0; $bw = 0;
    foreach (($s['blkio_stats']['io_service_bytes_recursive'] ?? []) as $e) {
        $op = strtolower($e['op'] ?? '');
        if ($op === 'read')  $br += $e['value'] ?? 0;
        if ($op === 'write') $bw += $e['value'] ?? 0;
    }
    return ['cpu' => round($cpu, 2), 'mem' => $mem, 'mem_limit' => $m['limit'] ?? 0,
            'rx' => $rx, 'tx' => $tx, 'blk_r' => $br, 'blk_w' => $bw,
            'pids' => $s['pids_stats']['current'] ?? null];
}

function recolectar($servicios, $nombres_amigables, $pistas_nombre) {
    $cpuA = cpu_muestra();
    $t0 = microtime(true);

    /* ---- Docker ---- */
    $docker = ['disponible' => false, 'error' => null, 'contenedores' => []];
    $mt = (meminfo()['MemTotal'] ?? 0);

    $ch = docker_ch('/containers/json?all=1');
    $raw = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if ($raw === false) {
        $docker['error'] = 'No se pudo conectar con la API de Docker (' . $err . ').';
    } elseif ($code !== 200) {
        $docker['error'] = "La API de Docker respondió HTTP $code (¿falta CONTAINERS=1 en el proxy?).";
    } else {
        $lista = json_decode($raw, true);
        if (!is_array($lista)) {
            $docker['error'] = 'Respuesta inesperada de la API de Docker.';
        } else {
            $docker['disponible'] = true;
            $mh = curl_multi_init();
            $hs = [];
            foreach ($lista as $c) {
                $id = $c['Id'];
                $hs[$id]['i'] = docker_ch("/containers/$id/json");
                curl_multi_add_handle($mh, $hs[$id]['i']);
                if (($c['State'] ?? '') === 'running') {
                    $hs[$id]['s'] = docker_ch("/containers/$id/stats?stream=false");
                    curl_multi_add_handle($mh, $hs[$id]['s']);
                }
            }
            do {
                $st = curl_multi_exec($mh, $activo);
                if ($activo) curl_multi_select($mh, 0.2);
            } while ($activo && $st === CURLM_OK);

            foreach ($lista as $c) {
                $id  = $c['Id'];
                $nom = ltrim($c['Names'][0] ?? $id, '/');
                $svc = $c['Labels']['com.docker.compose.service'] ?? '';
                $clave = isset($nombres_amigables[$svc]) ? $svc : '';
                if (!$clave) {
                    foreach ($pistas_nombre as $re => $k) { if (preg_match($re, strtolower($nom))) { $clave = $k; break; } }
                }
                $ins = json_decode(curl_multi_getcontent($hs[$id]['i']), true) ?: [];
                $ini = $ins['State']['StartedAt'] ?? '';
                $started = ($ini === '' || strpos($ini, '0001-') === 0) ? null : strtotime(preg_replace('/\.\d+/', '', $ini));
                $o = [
                    'id' => substr($id, 0, 12), 'nombre' => $nombres_amigables[$clave] ?? $nom, 'contenedor' => $nom,
                    'imagen' => $c['Image'] ?? '', 'state' => $c['State'] ?? '', 'status' => $c['Status'] ?? '',
                    'health' => $ins['State']['Health']['Status'] ?? null,
                    'restarts' => $ins['RestartCount'] ?? 0, 'started' => $started,
                    'cpu' => null, 'mem' => null, 'mem_limit' => null, 'rx' => 0, 'tx' => 0, 'blk_r' => 0, 'blk_w' => 0, 'pids' => null,
                ];
                if (isset($hs[$id]['s'])) {
                    $s = json_decode(curl_multi_getcontent($hs[$id]['s']), true);
                    if (is_array($s) && isset($s['cpu_stats'])) {
                        $p = procesar_stats($s);
                        if ($p['mem_limit'] <= 0 || ($mt > 0 && $p['mem_limit'] > $mt)) $p['mem_limit'] = $mt;
                        $o = array_merge($o, $p);
                    }
                }
                $docker['contenedores'][] = $o;
                curl_multi_remove_handle($mh, $hs[$id]['i']);
                if (isset($hs[$id]['s'])) curl_multi_remove_handle($mh, $hs[$id]['s']);
            }
            curl_multi_close($mh);
            usort($docker['contenedores'], fn($a, $b) => strcmp($a['nombre'], $b['nombre']));
        }
    }

    /* ---- Servidor (CPU medida entre dos muestras) ---- */
    if (microtime(true) - $t0 < 0.3) usleep(300000);
    $cpuB = cpu_muestra();
    $cpuPct = 0; $cores = 1;
    if ($cpuA && $cpuB) {
        $cores = $cpuB['cores'];
        $dt = $cpuB['tot'] - $cpuA['tot'];
        $di = $cpuB['idle'] - $cpuA['idle'];
        if ($dt > 0) $cpuPct = max(0, min(100, (1 - $di / $dt) * 100));
    }
    $mi = meminfo();
    $mTot = $mi['MemTotal'] ?? 0;
    $mUsed = $mTot - ($mi['MemAvailable'] ?? ($mi['MemFree'] ?? 0));
    $sTot = $mi['SwapTotal'] ?? 0;
    $sUsed = $sTot - ($mi['SwapFree'] ?? 0);
    $upRaw = @file_get_contents('/proc/uptime');
    $uptime = $upRaw ? (float)explode(' ', $upRaw)[0] : 0;
    $dTot = @disk_total_space('/') ?: 0;
    $dFree = @disk_free_space('/') ?: 0;
    $load = function_exists('sys_getloadavg') ? (sys_getloadavg() ?: [0, 0, 0]) : [0, 0, 0];

    /* ---- Puertos de los servicios ---- */
    $svc = [];
    foreach ($servicios as $nombre => $i) {
        [$up, $ms] = verificar_puerto($i['host'], $i['port']);
        $svc[] = ['nombre' => $nombre, 'icono' => $i['icono'], 'host' => $i['host'], 'puerto' => $i['port'], 'up' => $up, 'ms' => $ms];
    }

    return [
        'ts' => time(),
        'host' => [
            'cpu' => round($cpuPct, 1), 'cores' => $cores,
            'mem_total' => $mTot, 'mem_used' => $mUsed, 'mem_pct' => $mTot ? round($mUsed / $mTot * 100, 1) : 0,
            'swap_total' => $sTot, 'swap_used' => $sUsed,
            'load' => array_map(fn($x) => round($x, 2), $load),
            'uptime' => $uptime, 'boot' => time() - (int)$uptime,
            'disk_total' => $dTot, 'disk_used' => $dTot - $dFree, 'disk_pct' => $dTot ? round(($dTot - $dFree) / $dTot * 100, 1) : 0,
        ],
        'servicios' => $svc,
        'docker' => $docker,
    ];
}

if (isset($_GET['api'])) {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode(recolectar($servicios, $nombres_amigables, $pistas_nombre), JSON_UNESCAPED_UNICODE);
    exit;
}

$hostActual = htmlspecialchars(explode(':', $_SERVER['HTTP_HOST'] ?? 'localhost')[0]);
$accesos = [
    ['GNS3',       'http://gns3.huesca.empresa.lan',          '🧭', true],
    ['Git',        'http://git.huesca.empresa.lan',           '📦', true],
    ['Web',        'http://www.huesca.empresa.lan',           '🌐', true],
    ['Intranet',   'http://intranet.huesca.empresa.lan',      '🏠', false],
    ['LAM (LDAP)', 'http://lam.huesca.empresa.lan:8080',      '👥', true],
    ['Panel BIFI', 'http://' . $hostActual . ':8081',         '📊', true],
];
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Intranet Sede Huesca</title>
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
  background:
    radial-gradient(900px 500px at 12% -10%, rgba(56,189,248,.14), transparent 60%),
    radial-gradient(800px 500px at 100% 0%, rgba(167,139,250,.10), transparent 55%),
    linear-gradient(var(--bg2), var(--bg)) fixed;}
body::before{content:"";position:fixed;inset:0;pointer-events:none;opacity:.5;
  background-image:linear-gradient(rgba(255,255,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px);
  background-size:44px 44px;mask-image:radial-gradient(ellipse at top,#000 20%,transparent 75%);-webkit-mask-image:radial-gradient(ellipse at top,#000 20%,transparent 75%)}
.wrap{position:relative;max-width:1260px;margin:0 auto;padding:30px 24px 70px}
:focus-visible{outline:2px solid var(--cyan);outline-offset:2px;border-radius:6px}
.num{font-variant-numeric:tabular-nums}

/* Cabecera */
.top{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;flex-wrap:wrap;margin-bottom:18px}
.top h1{font-family:var(--display);font-size:2rem;font-weight:700;letter-spacing:-.02em;line-height:1.1}
.top h1 small{display:block;font-family:var(--text);font-weight:400;font-size:.85rem;color:var(--mute);letter-spacing:0;margin-top:6px}
.pill{display:inline-flex;align-items:center;gap:9px;padding:7px 15px;border-radius:999px;font-weight:600;font-size:.82rem;
  background:rgba(52,211,153,.12);color:var(--mint);border:1px solid rgba(52,211,153,.3);transition:background .4s,color .4s,border-color .4s}
.pill i{width:9px;height:9px;border-radius:50%;background:currentColor;box-shadow:0 0 0 0 currentColor;animation:ping 2s infinite}
.pill.warn{background:rgba(251,191,36,.12);color:var(--amber);border-color:rgba(251,191,36,.35)}
.pill.bad{background:rgba(251,113,133,.12);color:var(--coral);border-color:rgba(251,113,133,.35)}
@keyframes ping{0%{box-shadow:0 0 0 0 color-mix(in srgb,currentColor 60%,transparent)}70%,100%{box-shadow:0 0 0 10px transparent}}

/* Accesos rápidos */
.quick{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:26px}
.quick a{display:inline-flex;align-items:center;gap:9px;padding:10px 16px;border-radius:12px;text-decoration:none;color:var(--ink);font-weight:500;
  background:rgba(16,26,56,.6);border:1px solid var(--line);transition:background .15s,border-color .15s,color .15s}
.quick a:hover{background:var(--cyan);color:#04101f;border-color:var(--cyan)}
.quick a span{font-size:1.05rem}

/* Rejilla y paneles */
.grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:18px}
.p{background:var(--panel);border:1px solid var(--line);border-radius:18px;padding:22px;backdrop-filter:blur(8px);min-width:0}
.p-pulse{grid-column:span 5}.p-chart{grid-column:span 7}.p-svc{grid-column:span 5}.p-rank{grid-column:span 7}.p-wide{grid-column:span 12}
.ph{display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin-bottom:16px;flex-wrap:wrap}
.ph h2{font-family:var(--display);font-size:1.12rem;font-weight:700;letter-spacing:-.01em}
.ph .hint{color:var(--mute);font-size:.8rem}
@media(max-width:980px){.p-pulse,.p-chart,.p-svc,.p-rank{grid-column:span 12}.top h1{font-size:1.65rem}}

/* Indicadores circulares */
.gauges{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin-bottom:18px}
.gauge{--c:var(--cyan);text-align:center}
.gauge.warn{--c:var(--amber)}.gauge.crit{--c:var(--coral)}
.gw{position:relative;width:100%;max-width:132px;margin:0 auto}
.gw svg{width:100%;display:block;transform:rotate(-90deg)}
.gw circle{fill:none;stroke-width:9}
.gw .trk{stroke:rgba(141,156,198,.16)}
.gw .val{stroke:var(--c);stroke-linecap:round;stroke-dasharray:314.16;stroke-dashoffset:314.16;
  filter:drop-shadow(0 0 5px var(--c));transition:stroke-dashoffset 1.1s cubic-bezier(.2,.8,.2,1),stroke .4s}
.gv{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-family:var(--display);font-weight:700}
.gv b{font-size:1.9rem;letter-spacing:-.03em}.gv span{font-size:.9rem;color:var(--mute);margin:6px 0 0 2px}
.gl{font-weight:600;margin-top:8px}
.gs{color:var(--mute);font-size:.76rem}
.facts{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.fact{padding:11px 13px;border-radius:12px;background:rgba(6,11,28,.45);border:1px solid var(--line)}
.fact small{display:block;color:var(--mute);font-size:.74rem}
.fact b{font-family:var(--display);font-size:1.02rem;font-weight:600}

/* Gráfico histórico */
.legend{display:flex;gap:18px;color:var(--mute);font-size:.82rem;flex-wrap:wrap}
.legend b{color:var(--ink);font-family:var(--display)}
.legend i{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px}
.chart{position:relative;height:210px;margin-left:34px}
.chart svg{position:absolute;inset:0;width:100%;height:100%;overflow:visible}
.chart .gl-y{position:absolute;left:-34px;width:28px;text-align:right;color:var(--faint);font-size:.7rem;transform:translateY(-50%)}
.chart .gridline{stroke:rgba(141,156,198,.14);stroke-dasharray:3 5;vector-effect:non-scaling-stroke}
.chart path{vector-effect:non-scaling-stroke}
.cross{position:absolute;top:0;bottom:0;width:1px;background:rgba(234,240,255,.3);display:none;pointer-events:none}
.tip{position:absolute;top:6px;display:none;pointer-events:none;background:#0a1330;border:1px solid var(--line2);border-radius:10px;padding:8px 11px;font-size:.78rem;white-space:nowrap;z-index:3}
.tip b{font-family:var(--display)}
.chart-foot{display:flex;justify-content:space-between;margin:8px 0 0 34px;color:var(--faint);font-size:.72rem}

/* Servicios */
.svcs{list-style:none;display:flex;flex-direction:column;gap:8px}
.svc{display:grid;grid-template-columns:auto 1fr auto auto;align-items:center;gap:12px;padding:11px 13px;border-radius:12px;background:rgba(6,11,28,.45);border:1px solid var(--line);transition:border-color .3s,background .3s}
.svc.down{border-color:rgba(251,113,133,.4);background:rgba(251,113,133,.06)}
.svc .ico{width:38px;height:38px;display:grid;place-items:center;border-radius:10px;background:var(--bg2);border:1px solid var(--line);font-size:1.15rem}
.svc .sn b{display:block;font-weight:600;font-size:.9rem}
.svc .sn small{color:var(--mute);font-size:.76rem}
.svc .lat{display:flex;flex-direction:column;align-items:flex-end;color:var(--mute);font-size:.76rem;min-width:70px}
.svc .lat b{color:var(--ink);font-family:var(--display);font-weight:600;font-size:.9rem}
.st{display:inline-flex;align-items:center;gap:7px;padding:5px 12px;border-radius:999px;font-weight:600;font-size:.78rem;background:rgba(52,211,153,.13);color:var(--mint);border:1px solid rgba(52,211,153,.28)}
.st i{width:7px;height:7px;border-radius:50%;background:currentColor;box-shadow:0 0 8px currentColor}
.svc.down .st{background:rgba(251,113,133,.13);color:var(--coral);border-color:rgba(251,113,133,.3)}
@media(max-width:560px){.svc{grid-template-columns:auto 1fr auto}.svc .lat{display:none}}

/* Ranking */
.tabs{display:flex;gap:6px;background:rgba(6,11,28,.5);border:1px solid var(--line);padding:4px;border-radius:12px}
.tabs button{border:0;background:transparent;color:var(--mute);font:inherit;font-weight:600;padding:6px 14px;border-radius:8px;cursor:pointer;transition:background .15s,color .15s}
.tabs button[aria-pressed=true]{background:var(--cyan);color:#04101f}
.insight{margin-bottom:14px;color:var(--mute);min-height:2.6em}
.insight b{color:var(--ink)}
.rank{position:relative}
.rk{position:absolute;left:0;right:0;height:40px;display:grid;grid-template-columns:26px 1fr 46px;gap:10px;align-items:center;transition:transform .7s cubic-bezier(.2,.8,.2,1)}
.rk .pos{width:26px;height:26px;border-radius:8px;display:grid;place-items:center;font-family:var(--display);font-weight:700;font-size:.82rem;background:var(--bg2);border:1px solid var(--line);color:var(--mute)}
.rk:first-child .pos,.rk.top1 .pos{background:var(--amber);color:#1b1300;border-color:var(--amber)}
.rk-top{display:flex;justify-content:space-between;gap:10px;font-size:.84rem;margin-bottom:5px}
.rk-top span:first-child{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rk-top span:last-child{font-family:var(--display);font-weight:600;white-space:nowrap}
.bar{height:8px;border-radius:99px;background:rgba(141,156,198,.14);overflow:hidden}
.bar i{display:block;height:100%;width:0;border-radius:99px;background:linear-gradient(90deg,var(--cyan),var(--violet));transition:width .8s cubic-bezier(.2,.8,.2,1)}
.rk.top1 .bar i{background:linear-gradient(90deg,var(--amber),var(--coral))}
.rk .share{color:var(--mute);font-size:.78rem;text-align:right}

/* Tabla de contenedores */
.scroll{overflow-x:auto}
table{width:100%;border-collapse:collapse;min-width:860px}
th{font-weight:500;color:var(--mute);font-size:.78rem;text-align:left;padding:0 12px 10px;white-space:nowrap;border-bottom:1px solid var(--line)}
th button{all:unset;cursor:pointer;display:inline-flex;gap:5px;align-items:center}
th button:hover,th button[data-on=true]{color:var(--ink)}
th button:focus-visible{outline:2px solid var(--cyan);border-radius:4px}
td{padding:12px;border-bottom:1px solid rgba(31,45,82,.6);vertical-align:middle;font-size:.84rem}
tr.off td{opacity:.55}
.cn{display:flex;align-items:center;gap:10px}
.dot{width:9px;height:9px;border-radius:50%;background:var(--mint);box-shadow:0 0 8px var(--mint);flex:none}
.dot.off{background:var(--faint);box-shadow:none}.dot.warn{background:var(--amber);box-shadow:0 0 8px var(--amber)}.dot.bad{background:var(--coral);box-shadow:0 0 8px var(--coral)}
.cn b{display:block;font-weight:600}.cn small{color:var(--faint);font-size:.74rem}
.sub{display:block;color:var(--mute);font-size:.76rem}
.cell{display:flex;align-items:center;gap:10px}
.cell .v{min-width:56px;font-family:var(--display);font-weight:600}
.cell .bar{width:70px;flex:none}
.spark{color:var(--cyan);flex:none}
.tag{display:inline-block;margin-left:6px;padding:1px 7px;border-radius:99px;font-size:.7rem;font-weight:600;background:rgba(251,191,36,.14);color:var(--amber)}
.tag.fire{background:rgba(251,113,133,.16);color:var(--coral)}

/* Línea de arranque */
.tl{display:flex;flex-direction:column;gap:6px}
.tl-row{display:grid;grid-template-columns:210px 1fr 190px;gap:14px;align-items:center;font-size:.82rem}
.tl-n{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tl-track{position:relative;height:22px;border-radius:99px;background:rgba(141,156,198,.08)}
.tl-bar{position:absolute;top:7px;height:8px;border-radius:99px;background:linear-gradient(90deg,var(--cyan),rgba(56,189,248,.15));transition:left .6s,width .6s}
.tl-dot{position:absolute;top:3px;width:16px;height:16px;margin-left:-8px;border-radius:50%;background:var(--cyan);border:3px solid #0a1330;box-shadow:0 0 10px var(--cyan)}
.tl-row.host .tl-dot{background:var(--violet);box-shadow:0 0 10px var(--violet)}.tl-row.host .tl-bar{background:linear-gradient(90deg,var(--violet),rgba(167,139,250,.15))}
.tl-row.re .tl-dot{background:var(--amber);box-shadow:0 0 10px var(--amber)}
.tl-t{color:var(--mute);text-align:right}.tl-t b{color:var(--ink);font-weight:600}
.tl-axis{display:grid;grid-template-columns:210px 1fr 190px;gap:14px;color:var(--faint);font-size:.72rem;margin-top:4px}
.tl-axis div:nth-child(2){display:flex;justify-content:space-between}
@media(max-width:820px){.tl-row,.tl-axis{grid-template-columns:110px 1fr}.tl-t{display:none}.tl-axis div:last-child{display:none}}

.vacio{padding:18px;border-radius:12px;border:1px dashed var(--line2);color:var(--mute);background:rgba(6,11,28,.35)}
.vacio b{color:var(--ink)}.vacio code{background:#0a1330;padding:1px 6px;border-radius:6px;color:var(--cyan)}

/* Pie */
.foot{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;align-items:center;margin-top:22px;color:var(--mute);font-size:.8rem}
.ctrl{display:flex;gap:8px;align-items:center}
.ctrl select,.ctrl button{font:inherit;color:var(--ink);background:rgba(16,26,56,.8);border:1px solid var(--line2);border-radius:9px;padding:6px 11px;cursor:pointer}
.ctrl button[aria-pressed=true]{background:var(--amber);color:#1b1300;border-color:var(--amber)}

@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>
</head>
<body>
<div class="wrap">

  <header class="top">
    <h1>Intranet Sede Huesca
      <small>Servidor <span id="clock" class="num">--:--:--</span> · encendido hace <span class="live num" id="bootlive">—</span></small>
    </h1>
    <span class="pill" id="pill"><i></i><span id="pilltxt">Comprobando infraestructura…</span></span>
  </header>

  <nav class="quick" aria-label="Accesos rápidos">
    <?php foreach ($accesos as [$txt, $url, $ico, $nueva]): ?>
      <a href="<?= $url ?>"<?= $nueva ? ' target="_blank" rel="noopener"' : '' ?>><span><?= $ico ?></span><?= $txt ?></a>
    <?php endforeach; ?>
  </nav>

  <main class="grid">

    <section class="p p-pulse" aria-labelledby="h-pulso">
      <div class="ph"><h2 id="h-pulso">Estado del servidor</h2><span class="hint">en vivo</span></div>
      <div class="gauges">
        <?php foreach ([['cpu','CPU'],['ram','Memoria'],['dsk','Disco']] as [$k,$l]): ?>
        <div class="gauge" id="g-<?= $k ?>">
          <div class="gw">
            <svg viewBox="0 0 120 120" aria-hidden="true"><circle class="trk" cx="60" cy="60" r="50"/><circle class="val" cx="60" cy="60" r="50"/></svg>
            <div class="gv"><b class="num">0</b><span>%</span></div>
          </div>
          <div class="gl"><?= $l ?></div><div class="gs num">—</div>
        </div>
        <?php endforeach; ?>
      </div>
      <div class="facts">
        <div class="fact"><small>Carga media (1 / 5 / 15 min)</small><b class="num" id="f-load">—</b></div>
        <div class="fact"><small>Núcleos de CPU</small><b class="num" id="f-cores">—</b></div>
        <div class="fact"><small>Swap en uso</small><b class="num" id="f-swap">—</b></div>
        <div class="fact"><small>Contenedores activos</small><b class="num" id="f-cont">—</b></div>
      </div>
    </section>

    <section class="p p-chart" aria-labelledby="h-hist">
      <div class="ph"><h2 id="h-hist">Consumo en los últimos minutos</h2>
        <div class="legend"><span><i style="background:var(--cyan)"></i>CPU <b class="num" id="lg-cpu">—</b></span><span><i style="background:var(--violet)"></i>Memoria <b class="num" id="lg-ram">—</b></span></div>
      </div>
      <div class="chart" id="chart">
        <span class="gl-y" style="top:0%">100%</span><span class="gl-y" style="top:50%">50%</span><span class="gl-y" style="top:100%">0%</span>
        <svg viewBox="0 0 600 160" preserveAspectRatio="none" aria-hidden="true">
          <defs>
            <linearGradient id="aC" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#38bdf8" stop-opacity=".35"/><stop offset="1" stop-color="#38bdf8" stop-opacity="0"/></linearGradient>
            <linearGradient id="aR" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a78bfa" stop-opacity=".25"/><stop offset="1" stop-color="#a78bfa" stop-opacity="0"/></linearGradient>
          </defs>
          <line class="gridline" x1="0" x2="600" y1="0" y2="0"/><line class="gridline" x1="0" x2="600" y1="80" y2="80"/><line class="gridline" x1="0" x2="600" y1="160" y2="160"/>
          <path id="ar-ram" fill="url(#aR)"/><path id="ar-cpu" fill="url(#aC)"/>
          <path id="ln-ram" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linejoin="round"/>
          <path id="ln-cpu" fill="none" stroke="#38bdf8" stroke-width="2.4" stroke-linejoin="round"/>
        </svg>
        <div class="cross" id="cross"></div><div class="tip" id="tip"></div>
      </div>
      <div class="chart-foot"><span id="ch-from">hace —</span><span>ahora</span></div>
    </section>

    <section class="p p-svc" aria-labelledby="h-svc">
      <div class="ph"><h2 id="h-svc">Servicios</h2><span class="hint" id="svc-hint">—</span></div>
      <ul class="svcs" id="svc"></ul>
    </section>

    <section class="p p-rank" aria-labelledby="h-rank">
      <div class="ph"><h2 id="h-rank">Quién consume más</h2>
        <div class="tabs" role="group" aria-label="Recurso">
          <button data-m="cpu" aria-pressed="true">CPU</button><button data-m="ram" aria-pressed="false">Memoria</button>
          <button data-m="net" aria-pressed="false">Red</button><button data-m="dsk" aria-pressed="false">Disco</button>
        </div>
      </div>
      <p class="insight" id="insight">Cargando…</p>
      <div class="rank" id="rank"></div>
    </section>

    <section class="p p-wide" aria-labelledby="h-cont">
      <div class="ph"><h2 id="h-cont">Detalle por contenedor</h2><span class="hint">CPU: 100 % = un núcleo completo · Red y disco: velocidad actual</span></div>
      <div class="scroll">
        <table>
          <thead><tr>
            <th><button data-k="nombre">Servicio</button></th>
            <th><button data-k="started">Arranque</button></th>
            <th><button data-k="cpu">CPU</button></th>
            <th><button data-k="mem">Memoria</button></th>
            <th><button data-k="net">Red ↓ ↑</button></th>
            <th><button data-k="dsk">Disco L / E</button></th>
            <th><button data-k="pids">Procesos</button></th>
          </tr></thead>
          <tbody id="tbody"><tr><td colspan="7" style="color:var(--mute)">Cargando…</td></tr></tbody>
        </table>
      </div>
    </section>

    <section class="p p-wide" aria-labelledby="h-tl">
      <div class="ph"><h2 id="h-tl">Cuándo se inició cada cosa</h2><span class="hint">Cada punto marca el arranque; la barra, el tiempo que lleva activo</span></div>
      <div id="tl" class="tl"></div>
    </section>

  </main>

  <footer class="foot">
    <span>Última actualización: <b class="num" id="last">—</b> · <span id="conn">conectando…</span></span>
    <div class="ctrl">
      <label for="int">Actualizar cada</label>
      <select id="int"><option value="3000">3 s</option><option value="5000" selected>5 s</option><option value="10000">10 s</option><option value="30000">30 s</option></select>
      <button id="pause" aria-pressed="false">Pausar</button>
    </div>
  </footer>
</div>

<script>
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmtB = b => { if (b == null) return '—'; const u = ['B','KB','MB','GB','TB']; let i = 0; while (b >= 1024 && i < 4) { b /= 1024; i++; } return (i < 2 ? b.toFixed(0) : b.toFixed(1)) + ' ' + u[i]; };
const fmtDur = s => { s = Math.max(0, Math.floor(s)); const d = Math.floor(s/86400), h = Math.floor(s%86400/3600), m = Math.floor(s%3600/60), x = s%60;
  if (d) return d + ' d ' + h + ' h'; if (h) return h + ' h ' + String(m).padStart(2,'0') + ' min'; if (m) return m + ' min ' + String(x).padStart(2,'0') + ' s'; return x + ' s'; };
const fmtDate = t => new Date(t*1000).toLocaleString('es-ES', {day:'numeric', month:'short', hour:'2-digit', minute:'2-digit'});
const lvl = p => p >= 85 ? 'crit' : p >= 60 ? 'warn' : '';
const MAXH = 60, ROW = 46, C = 2*Math.PI*50;

const S = { d:null, off:0, hist:[], ch:{}, lat:{}, prev:{}, rank:'cpu', sk:'cpu', sd:-1, timer:null, busy:false, paused:false };
const nowS = () => Date.now()/1000 + S.off;

/* ---------- carga de datos ---------- */
async function tick() {
  if (S.busy || S.paused || document.hidden) return;
  S.busy = true;
  try {
    const r = await fetch('?api=1', {cache:'no-store'});
    if (!r.ok) throw new Error(r.status);
    ingest(await r.json());
    render();
    $('#conn').textContent = 'conectado'; $('#conn').style.color = '';
  } catch (e) {
    $('#conn').textContent = 'sin respuesta del servidor'; $('#conn').style.color = 'var(--coral)';
    setPill('bad', 'Sin conexión con el servidor');
  } finally { S.busy = false; }
}
function schedule() { clearInterval(S.timer); S.timer = setInterval(tick, +$('#int').value); }

function ingest(d) {
  const prev = S.d;
  S.off = d.ts - Date.now()/1000;
  S.hist.push({t:d.ts, cpu:d.host.cpu, ram:d.host.mem_pct});
  if (S.hist.length > MAXH) S.hist.shift();
  d.servicios.forEach(s => { const a = S.lat[s.nombre] = S.lat[s.nombre] || []; a.push(s.up ? s.ms : 0); if (a.length > 30) a.shift(); });
  d.docker.contenedores.forEach(c => {
    const a = S.ch[c.id] = S.ch[c.id] || []; a.push(c.cpu || 0); if (a.length > 30) a.shift();
    const p = S.prev[c.id]; c.net_s = 0; c.dsk_s = 0;
    if (p && d.ts > p.t && c.rx >= p.rx && c.blk_r + c.blk_w >= p.blk) {
      const dt = d.ts - p.t;
      c.net_s = ((c.rx - p.rx) + (c.tx - p.tx)) / dt; c.rx_s = (c.rx - p.rx)/dt; c.tx_s = (c.tx - p.tx)/dt;
      c.dsk_s = (c.blk_r + c.blk_w - p.blk) / dt; c.r_s = (c.blk_r - p.r)/dt; c.w_s = (c.blk_w - p.w)/dt;
    }
    c.rx_s = c.rx_s || 0; c.tx_s = c.tx_s || 0; c.r_s = c.r_s || 0; c.w_s = c.w_s || 0;
    S.prev[c.id] = {t:d.ts, rx:c.rx, tx:c.tx, blk:c.blk_r + c.blk_w, r:c.blk_r, w:c.blk_w};
  });
  S.d = d;
}

/* ---------- pintado ---------- */
function render() { renderTop(); renderGauges(); renderChart(); renderServices(); renderRank(); renderTable(); renderTimeline(); tickLive(); }

function setPill(cls, txt) { const p = $('#pill'); p.className = 'pill ' + cls; $('#pilltxt').textContent = txt; }

function renderTop() {
  const caidos = S.d.servicios.filter(s => !s.up).length;
  if (!caidos) setPill('', 'Infraestructura activa');
  else if (caidos < S.d.servicios.length / 2) setPill('warn', caidos + (caidos === 1 ? ' servicio caído' : ' servicios caídos'));
  else setPill('bad', caidos + ' servicios caídos');
  $('#last').textContent = new Date().toLocaleTimeString('es-ES');
}

function setGauge(id, pct, detail) {
  const g = $('#g-' + id); pct = Math.max(0, Math.min(100, pct));
  g.className = 'gauge ' + lvl(pct);
  g.querySelector('.val').style.strokeDashoffset = C * (1 - pct/100);
  g.querySelector('.gv b').textContent = pct.toFixed(0);
  g.querySelector('.gs').textContent = detail;
}
function renderGauges() {
  const h = S.d.host;
  setGauge('cpu', h.cpu, h.cores + (h.cores === 1 ? ' núcleo' : ' núcleos'));
  setGauge('ram', h.mem_pct, fmtB(h.mem_used) + ' / ' + fmtB(h.mem_total));
  setGauge('dsk', h.disk_pct, fmtB(h.disk_used) + ' / ' + fmtB(h.disk_total));
  $('#f-load').textContent = h.load.join(' / ');
  $('#f-cores').textContent = h.cores;
  $('#f-swap').textContent = h.swap_total ? fmtB(h.swap_used) + ' de ' + fmtB(h.swap_total) : 'sin swap';
  const run = S.d.docker.contenedores.filter(c => c.state === 'running').length;
  $('#f-cont').textContent = S.d.docker.disponible ? run + ' de ' + S.d.docker.contenedores.length : 'sin datos';
  $('#bootlive').dataset.since = h.boot;
}

function renderChart() {
  const h = S.hist, n = h.length, W = 600, H = 160, step = W/(MAXH-1);
  const pts = k => h.map((p, i) => [W - (n-1-i)*step, H - Math.min(100, p[k])/100*H]);
  const line = a => a.map((q, i) => (i ? 'L' : 'M') + q[0].toFixed(1) + ' ' + q[1].toFixed(1)).join(' ');
  const area = a => line(a) + ' L' + a[a.length-1][0].toFixed(1) + ' ' + H + ' L' + a[0][0].toFixed(1) + ' ' + H + ' Z';
  const c = pts('cpu'), r = pts('ram');
  $('#ln-cpu').setAttribute('d', line(c)); $('#ar-cpu').setAttribute('d', area(c));
  $('#ln-ram').setAttribute('d', line(r)); $('#ar-ram').setAttribute('d', area(r));
  const last = h[n-1];
  $('#lg-cpu').textContent = last.cpu.toFixed(1) + ' %'; $('#lg-ram').textContent = last.ram.toFixed(1) + ' %';
  $('#ch-from').textContent = 'hace ' + fmtDur(h[n-1].t - h[0].t);
}
(function chartHover() {
  const ch = $('#chart'), cross = $('#cross'), tip = $('#tip');
  ch.addEventListener('pointermove', e => {
    const n = S.hist.length; if (!n) return;
    const b = ch.getBoundingClientRect(), fx = Math.min(1, Math.max(0, (e.clientX - b.left)/b.width));
    const idx = n - 1 - Math.round((1 - fx)*(MAXH-1)); if (idx < 0 || idx >= n) { cross.style.display = tip.style.display = 'none'; return; }
    const p = S.hist[idx], x = b.width - (n-1-idx)/(MAXH-1)*b.width;
    cross.style.display = tip.style.display = 'block'; cross.style.left = x + 'px';
    tip.innerHTML = new Date(p.t*1000).toLocaleTimeString('es-ES') + '<br><span style="color:var(--cyan)">CPU</span> <b>' + p.cpu.toFixed(1) + ' %</b> · <span style="color:var(--violet)">RAM</span> <b>' + p.ram.toFixed(1) + ' %</b>';
    tip.style.left = (x > b.width/2 ? x - tip.offsetWidth - 10 : x + 10) + 'px';
  });
  ch.addEventListener('pointerleave', () => { cross.style.display = tip.style.display = 'none'; });
})();

function spark(a, w = 64, h = 22) {
  if (!a || a.length < 2) return '';
  const mx = Math.max(5, ...a), st = w/(a.length-1);
  const d = a.map((v, i) => (i ? 'L' : 'M') + (i*st).toFixed(1) + ' ' + (h - 2 - v/mx*(h-4)).toFixed(1)).join(' ');
  return `<svg class="spark" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true"><path d="${d}" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
}

function renderServices() {
  const sv = S.d.servicios, ok = sv.filter(s => s.up).length;
  $('#svc-hint').textContent = ok + ' de ' + sv.length + ' en línea';
  $('#svc').innerHTML = sv.map(s => `
    <li class="svc ${s.up ? '' : 'down'}">
      <span class="ico">${s.icono}</span>
      <div class="sn"><b>${esc(s.nombre)}</b><small>${esc(s.host)}:${s.puerto}</small></div>
      <div class="lat">${s.up ? `<b class="num">${s.ms.toFixed(1)} ms</b>` + spark(S.lat[s.nombre], 56, 16) : '<b>sin respuesta</b>'}</div>
      <span class="st"><i></i>${s.up ? 'Online' : 'Offline'}</span>
    </li>`).join('');
}

/* ---------- ranking de consumo ---------- */
const RK = {
  cpu:{t:'CPU',  v:c => c.cpu,   f:v => v.toFixed(1) + ' %'},
  ram:{t:'memoria', v:c => c.mem, f:v => fmtB(v)},
  net:{t:'tráfico de red', v:c => c.net_s, f:v => fmtB(v) + '/s'},
  dsk:{t:'actividad de disco', v:c => c.dsk_s, f:v => fmtB(v) + '/s'},
};
function sinDocker(el) {
  const d = S.d.docker;
  el.innerHTML = `<div class="vacio"><b>Faltan los datos por contenedor.</b> ${esc(d.error || '')}<br>Añade el servicio <code>dockerproxy</code> al <code>compose.yaml</code> en la misma red que <code>web</code> y vuelve a levantar la intranet.</div>`;
}
function renderRank() {
  const box = $('#rank');
  if (!S.d.docker.disponible) { sinDocker($('#insight')); $('#insight').style.minHeight = 0; box.style.height = 0; box.innerHTML = ''; return; }
  const m = RK[S.rank];
  const arr = S.d.docker.contenedores.filter(c => c.state === 'running' && c.cpu != null).map(c => ({c, v: m.v(c) || 0})).sort((a, b) => b.v - a.v);
  const max = Math.max(...arr.map(x => x.v), 1e-9), tot = arr.reduce((s, x) => s + x.v, 0);
  box.style.height = arr.length*ROW + 'px';
  const seen = new Set();
  arr.forEach((x, i) => {
    let el = box.querySelector(`[data-id="${x.c.id}"]`);
    if (!el) {
      el = document.createElement('div'); el.className = 'rk'; el.dataset.id = x.c.id;
      el.innerHTML = '<span class="pos"></span><div><div class="rk-top"><span></span><span></span></div><div class="bar"><i></i></div></div><span class="share num"></span>';
      box.appendChild(el);
    }
    seen.add(x.c.id);
    el.style.transform = `translateY(${i*ROW}px)`;
    el.classList.toggle('top1', i === 0 && x.v > 0);
    el.querySelector('.pos').textContent = i + 1;
    const sp = el.querySelectorAll('.rk-top span'); sp[0].textContent = x.c.nombre; sp[1].textContent = m.f(x.v);
    el.querySelector('.bar i').style.width = (x.v/max*100) + '%';
    el.querySelector('.share').textContent = tot > 0 ? Math.round(x.v/tot*100) + ' %' : '—';
  });
  box.querySelectorAll('.rk').forEach(el => { if (!seen.has(el.dataset.id)) el.remove(); });
  const ins = $('#insight'); ins.style.minHeight = '';
  if (arr.length && arr[0].v > 0) {
    const a = arr[0], sh = Math.round(a.v/tot*100), b = arr[1];
    ins.innerHTML = `<b>${esc(a.c.nombre)}</b> es quien más ${m.t === 'CPU' ? 'CPU' : 'usa de ' + m.t} ahora: ${m.f(a.v)} (${sh} % del total de contenedores)` + (b && b.v > 0 ? `, seguido de <b>${esc(b.c.nombre)}</b> con ${m.f(b.v)}.` : '.');
  } else ins.textContent = 'Ahora mismo ningún contenedor muestra actividad de ' + m.t + '.';
}
document.querySelectorAll('.tabs button').forEach(b => b.addEventListener('click', () => {
  S.rank = b.dataset.m;
  document.querySelectorAll('.tabs button').forEach(x => x.setAttribute('aria-pressed', x === b));
  if (S.d) renderRank();
}));

/* ---------- tabla ---------- */
const SORT = {
  nombre:c => c.nombre.toLowerCase(), started:c => c.started || 0, cpu:c => c.cpu ?? -1, mem:c => c.mem ?? -1,
  net:c => c.net_s || 0, dsk:c => c.dsk_s || 0, pids:c => c.pids ?? -1,
};
function renderTable() {
  const tb = $('#tbody'), d = S.d.docker;
  if (!d.disponible) { tb.innerHTML = '<tr><td colspan="7"></td></tr>'; sinDocker(tb.querySelector('td')); return; }
  const host = S.d.host, f = SORT[S.sk];
  const rows = [...d.contenedores].sort((a, b) => { const x = f(a), y = f(b); return (x > y ? 1 : x < y ? -1 : 0) * S.sd; });
  const topCpu = rows.reduce((m, c) => (c.cpu ?? 0) > (m.cpu ?? 0) ? c : m, {cpu:0});
  tb.innerHTML = rows.map(c => {
    const run = c.state === 'running';
    const dot = !run ? 'off' : c.health === 'unhealthy' ? 'bad' : (c.restarts > 0 && c.started && nowS() - c.started < 600) ? 'warn' : '';
    const cpuW = Math.min(100, (c.cpu || 0) / (host.cores*100) * 100);
    const memP = c.mem_limit ? c.mem / c.mem_limit * 100 : 0;
    const fire = run && c.id === topCpu.id && (c.cpu || 0) > 1 ? '<span class="tag fire">más CPU</span>' : '';
    const re = c.restarts > 0 ? `<span class="tag" title="Reinicios acumulados">↻ ${c.restarts}</span>` : '';
    if (!run) return `<tr class="off"><td><div class="cn"><i class="dot off"></i><div><b>${esc(c.nombre)}</b><small>${esc(c.contenedor)}</small></div></div></td><td colspan="6">${esc(c.status || 'Parado')}</td></tr>`;
    return `<tr>
      <td><div class="cn"><i class="dot ${dot}"></i><div><b>${esc(c.nombre)}${fire}${re}</b><small>${esc(c.contenedor)} · ${esc(c.imagen.split('@')[0])}</small></div></div></td>
      <td>${c.started ? fmtDate(c.started) : '—'}<span class="sub">activo <span class="live num" data-since="${c.started || ''}">${c.started ? fmtDur(nowS() - c.started) : '—'}</span></span></td>
      <td><div class="cell"><span class="v num">${(c.cpu || 0).toFixed(1)} %</span><div class="bar"><i style="width:${cpuW}%"></i></div>${spark(S.ch[c.id])}</div></td>
      <td><div class="cell"><span class="v num">${fmtB(c.mem)}</span><div class="bar"><i style="width:${Math.min(100, memP)}%"></i></div></div><span class="sub num">${memP.toFixed(1)} % de ${fmtB(c.mem_limit)}</span></td>
      <td class="num">↓ ${fmtB(c.rx_s)}/s<span class="sub">↑ ${fmtB(c.tx_s)}/s · total ${fmtB(c.rx + c.tx)}</span></td>
      <td class="num">L ${fmtB(c.r_s)}/s<span class="sub">E ${fmtB(c.w_s)}/s · total ${fmtB(c.blk_r + c.blk_w)}</span></td>
      <td class="num">${c.pids ?? '—'}</td></tr>`;
  }).join('');
  document.querySelectorAll('th button').forEach(b => { b.dataset.on = b.dataset.k === S.sk; b.textContent = b.textContent.replace(/ [▲▼]$/, '') + (b.dataset.k === S.sk ? (S.sd > 0 ? ' ▲' : ' ▼') : ''); });
}
document.querySelectorAll('th button').forEach(b => b.addEventListener('click', () => {
  const k = b.dataset.k; if (S.sk === k) S.sd *= -1; else { S.sk = k; S.sd = k === 'nombre' ? 1 : -1; }
  if (S.d) renderTable();
}));

/* ---------- línea de arranque ---------- */
function renderTimeline() {
  const box = $('#tl'), d = S.d, now = nowS();
  if (!d.docker.disponible) { box.innerHTML = ''; sinDocker(box); return; }
  const items = [{n:'Servidor (arranque del sistema)', t:d.host.boot, host:true}]
    .concat(d.docker.contenedores.filter(c => c.state === 'running' && c.started).map(c => ({n:c.nombre, t:c.started, re:c.restarts > 0})))
    .sort((a, b) => a.t - b.t);
  const t0 = items[0].t, span = Math.max(now - t0, 60);
  box.innerHTML = items.map(i => {
    const p = Math.min(98, (i.t - t0)/span*100);
    return `<div class="tl-row ${i.host ? 'host' : ''} ${i.re ? 're' : ''}">
      <div class="tl-n" title="${esc(i.n)}">${esc(i.n)}</div>
      <div class="tl-track"><span class="tl-bar" style="left:${p}%;width:${100-p}%"></span><span class="tl-dot" style="left:${p}%"></span></div>
      <div class="tl-t"><b>${fmtDate(i.t)}</b> · <span class="live num" data-since="${i.t}">${fmtDur(now - i.t)}</span></div></div>`;
  }).join('') + `<div class="tl-axis"><div></div><div><span>${fmtDate(t0)}</span><span>ahora</span></div><div></div></div>`;
}

/* ---------- relojes ---------- */
function tickLive() {
  document.querySelectorAll('.live').forEach(el => { const s = +el.dataset.since; if (s) el.textContent = fmtDur(nowS() - s); });
  $('#clock').textContent = new Date(nowS()*1000).toLocaleTimeString('es-ES');
}
setInterval(tickLive, 1000);

/* ---------- controles ---------- */
$('#int').addEventListener('change', schedule);
$('#pause').addEventListener('click', e => {
  S.paused = !S.paused; e.target.setAttribute('aria-pressed', S.paused); e.target.textContent = S.paused ? 'Reanudar' : 'Pausar';
  if (!S.paused) tick();
});
document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });

tick(); schedule();
</script>
</body>
</html>

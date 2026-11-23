<?php
// Conexión del panel con la base bifi (ASGBD RA2, P1).
// Por ahora el panel guarda sus datos en JSON; aquí solo se comprueba que entra en PostgreSQL desde
// Compose con su usuario "panel". La usan public/estado-bd.php y pruebas/estado-bifi.php.
declare(strict_types=1);

/**
 * Abre la conexión con los datos que compose.yaml pone en el entorno del contenedor:
 * BIFI_HOST, BIFI_DB, BIFI_USER y BIFI_PASSWORD (esta última sale de .env).
 * Si falla, lanza PDOException con el motivo que da PostgreSQL.
 */
function conectar_bifi(): PDO
{
    $dsn = sprintf(
        'pgsql:host=%s;port=5432;dbname=%s;connect_timeout=5',
        getenv('BIFI_HOST') ?: 'db',
        getenv('BIFI_DB') ?: 'bifi'
    );
    return new PDO($dsn, (string) getenv('BIFI_USER'), (string) getenv('BIFI_PASSWORD'), [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
}

/**
 * Lo que dice el gestor de esta conexión: quién soy, en qué base, desde qué IP me ve (Maestro),
 * con qué codificación y colación (P7) y qué límites me aplica (P5, P6).
 * Es una consulta fija, sin datos del usuario: no necesita parámetros.
 */
function estado_bifi(PDO $bd): array
{
    $sql = "SELECT current_user                              AS usuario,
                   current_database()                        AS base,
                   host(inet_client_addr())                  AS ip_cliente,
                   host(inet_server_addr())                  AS ip_servidor,
                   pg_encoding_to_char(d.encoding)           AS codificacion,
                   d.datcollate                              AS colacion,
                   current_setting('statement_timeout')      AS statement_timeout,
                   r.rolconnlimit                            AS limite_conexiones
            FROM pg_database d, pg_roles r
            WHERE d.datname = current_database() AND r.rolname = current_user";
    return $bd->query($sql)->fetch();
}

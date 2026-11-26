-- db/panel/datos-iniciales.sql · Primera carga de las tablas del panel a partir de panel/datos-ejemplo/*.json
--
-- Lo lanza instalar.sh (fase bd) como administrador, por el socket del contenedor:
--   docker exec -i -u postgres mi-postgres psql -d bifi -v usuarios="$(cat usuarios.json)" \
--       -v proyectos="$(cat proyectos.json)" -v usos="$(cat usos.json)" < db/panel/datos-iniciales.sql
--
-- Está en una subcarpeta a propósito: PostgreSQL solo ejecuta al crear el volumen los ficheros sueltos en
-- la raíz de db/, y este necesita los JSON, que solo le llegan desde instalar.sh.
--
-- Solo carga si la tabla de usuarios está vacía, es decir, la primera vez. Si cargara en cada instalación,
-- aunque fuera sin duplicar, volverían a aparecer los miembros que alguien haya quitado desde el panel.
-- Todo va en una transacción: o entra todo y cuadra con los JSON, o no queda nada a medias.

\set ON_ERROR_STOP on

SELECT NOT EXISTS (SELECT 1 FROM usuarios) AS vacia \gset

\if :vacia

BEGIN;

-- Los hashes se copian tal cual: ya son password_hash() (bcrypt). No hay contraseñas en claro en ningún sitio.
INSERT INTO usuarios (usuario, nombre, perfil, hash)
SELECT usuario, nombre, perfil, hash
FROM jsonb_to_recordset(:'usuarios'::jsonb) AS j(usuario text, nombre text, perfil text, hash text)
ON CONFLICT (usuario) DO NOTHING;

INSERT INTO proyectos (codigo, titulo, responsable, tarifa)
SELECT codigo, titulo, responsable, tarifa
FROM jsonb_to_recordset(:'proyectos'::jsonb) AS j(codigo text, titulo text, responsable text, tarifa text)
ON CONFLICT (codigo) DO NOTHING;

-- En el JSON los miembros son una lista dentro de cada proyecto; aquí, una fila por proyecto y persona.
INSERT INTO miembros (proyecto, usuario)
SELECT j.codigo, m.usuario
FROM jsonb_to_recordset(:'proyectos'::jsonb) AS j(codigo text, miembros jsonb),
     jsonb_array_elements_text(j.miembros) AS m(usuario)
ON CONFLICT DO NOTHING;

-- usos no tiene clave natural (la misma persona puede usar la misma máquina dos veces el mismo día),
-- así que se evita el duplicado comparando la fila entera.
INSERT INTO usos (proyecto, usuario, maquina, nucleos, horas, fecha)
SELECT j.proyecto, j.usuario, j.maquina, j.nucleos, j.horas, j.fecha
FROM jsonb_to_recordset(:'usos'::jsonb)
     AS j(proyecto text, usuario text, maquina text, nucleos integer, horas numeric, fecha date)
WHERE NOT EXISTS (
    SELECT 1 FROM usos u
    WHERE (u.proyecto, u.usuario, u.maquina, u.nucleos, u.horas, u.fecha)
        = (j.proyecto, j.usuario, j.maquina, j.nucleos, j.horas, j.fecha)
);

-- Antes de confirmar: cada registro de los JSON tiene que estar en la base. Si falta alguno, se deshace todo.
SELECT
    (SELECT count(*) FROM jsonb_to_recordset(:'usuarios'::jsonb) AS j(usuario text)
      WHERE NOT EXISTS (SELECT 1 FROM usuarios t WHERE t.usuario = j.usuario))
  + (SELECT count(*) FROM jsonb_to_recordset(:'proyectos'::jsonb) AS j(codigo text)
      WHERE NOT EXISTS (SELECT 1 FROM proyectos t WHERE t.codigo = j.codigo))
  + (SELECT count(*) FROM jsonb_to_recordset(:'proyectos'::jsonb) AS j(codigo text, miembros jsonb),
                          jsonb_array_elements_text(j.miembros) AS m(usuario)
      WHERE NOT EXISTS (SELECT 1 FROM miembros t WHERE t.proyecto = j.codigo AND t.usuario = m.usuario))
  + (SELECT count(*) FROM jsonb_to_recordset(:'usos'::jsonb)
                          AS j(proyecto text, usuario text, maquina text, nucleos integer, horas numeric, fecha date)
      WHERE NOT EXISTS (SELECT 1 FROM usos t
                        WHERE (t.proyecto, t.usuario, t.maquina, t.nucleos, t.horas, t.fecha)
                            = (j.proyecto, j.usuario, j.maquina, j.nucleos, j.horas, j.fecha)))
  AS faltan \gset

SELECT :faltan = 0 AS cuadra \gset

\if :cuadra
COMMIT;
SELECT format('cargados %s usuarios, %s proyectos, %s miembros y %s usos',
              (SELECT count(*) FROM usuarios), (SELECT count(*) FROM proyectos),
              (SELECT count(*) FROM miembros), (SELECT count(*) FROM usos)) AS resumen \gset
\echo :resumen
\else
ROLLBACK;
\echo 'ERROR: faltan' :faltan 'registros de los JSON en la base; no se ha guardado nada'
-- Para que psql termine con error (y instalar.sh se entere) hace falta un fallo de verdad.
DO $$ BEGIN RAISE EXCEPTION 'carga de datos del panel incompleta'; END $$;
\endif

\else
\echo 'las tablas del panel ya tenían datos: no se carga nada'
\endif

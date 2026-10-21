# db/ · ASGBD

Lo que hace que la base de datos nazca con su tabla, sus filas y sus usuarios
sin intervención (DS6). No hay copias con datos de personas ni contraseñas: las
claves llegan desde `.env`.

## Qué hay

| Fichero | Qué hace |
|---|---|
| `01_esquema.sql` | Crea la tabla `inventario` y su secuencia de IDs. |
| `02_datos.sql` | Carga los 20 registros de material de la sede. |

## En qué orden se ejecuta

PostgreSQL ejecuta los ficheros de esta carpeta en orden alfabético, solo la
primera vez, cuando el volumen de datos está vacío: primero el esquema y
después los datos.

El usuario y la base de datos los crea la propia imagen de PostgreSQL con las
variables `POSTGRES_USER`, `POSTGRES_PASSWORD` y `POSTGRES_DB`, que se leen de
`sede.env`. Las contraseñas nunca están escritas en estos ficheros.

## Cómo se usa

La carpeta se monta en el contenedor de PostgreSQL desde `compose.yaml`:

    ./db:/docker-entrypoint-initdb.d:ro

## Comprobación

    docker compose exec mi-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT COUNT(*) FROM inventario;"

Debe devolver 20.

## Volver a empezar desde cero

Estos ficheros no se repiten si el volumen ya existe. Para recrear la base
desde cero: `docker compose down -v` y `docker compose up -d`. Esto borra los
datos que hubiera en el volumen.

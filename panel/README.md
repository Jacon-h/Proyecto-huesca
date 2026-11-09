# Panel del BIFI · esqueleto

Punto de partida del panel. **Funciona, pero no es seguro**: cualquiera entra como si fuera el
CESAR, ve todos los proyectos y puede dar de alta cualquier cosa. Lo que falta es justo lo que se
evalúa en IAW RA5, y está marcado con `TODO` en el código. El encargo:
[`../encargos/iaw-panel-ra5.md`](../encargos/iaw-panel-ra5.md).

## Qué hay

```text
Dockerfile          PHP 8.3 con Apache y pdo_pgsql (para el RA6). Solo se sirve public/
public/             lo que pide el navegador: una página por pantalla
  index.php         lista de proyectos
  proyecto.php      un proyecto: miembros y consumo
  proyecto-nuevo.php formulario de alta
  login.php         formulario de entrada
  logout.php        salir
  estilo.css
comun/              funciones; el navegador no llega aquí
  arranque.php      lo primero de cada página: carga lo demás y abre la sesión
  funciones.php     e() para escapar, leer_datos() y guardar_datos()
  sesion.php        login, salir y control por perfil          ← TODO
  proyectos.php     quién ve qué, validación del alta y miembros ← TODO
  plantilla.php     cabecera, menú y pie                        ← TODO el menú
datos-ejemplo/      usuarios, proyectos y usos en JSON
```

Los datos van en ficheros JSON hasta el RA6, cuando pasan a PostgreSQL. El modelo, en
[`../modelo-datos.md`](../modelo-datos.md).

## Usuarios de ejemplo

Todos con la contraseña `bifi2026`. En `datos-ejemplo/usuarios.json` está su *hash*, no la
contraseña.

| Usuario | Perfil | Proyectos |
|---|---|---|
| `ana` | Investigador | Miembro de BIO-0001 |
| `luis` | Investigador | Miembro de FIS-0002 |
| `marta` | Responsable | BIO-0001: añade y quita investigadores |
| `jorge` | Responsable | FIS-0002: añade y quita investigadores |
| `cesar` | Administración del CESAR | Todos; da de alta proyectos |

## Levantarlo

Copiad la carpeta `panel/` a la raíz del repositorio de vuestra sede y añadid a vuestro
`compose.yaml` el servicio de [`compose.ejemplo.yaml`](compose.ejemplo.yaml). Después:

```bash
docker compose up -d --build panel
```

Para probar antes de tener el nombre `panel.<sede>.empresa.lan` en el DNS y en el Apache de la
sede, publicad un puerto (`ports: ["8081:80"]`) y abrid `http://<IP_AULA>:8081`.

`datos/` es un volumen: la primera vez se llena con `datos-ejemplo/` y lo que se da de alta queda
ahí aunque se recree el contenedor. Para volver a los datos de ejemplo:
`docker compose down panel && docker volume rm <sede>_datos-panel`.

Cada cambio en el código necesita `docker compose up -d --build panel`. Para no reconstruir a cada
paso mientras programáis, montad el código: `- ./panel/public:/var/www/panel/public` y
`- ./panel/comun:/var/www/panel/comun` en `volumes:`.

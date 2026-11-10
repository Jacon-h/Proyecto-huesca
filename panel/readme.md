# Panel del BIFI · Servicio de Gestión de Proyectos

Aplicación web desarrollada en PHP 8.3 para la gestión de proyectos de investigación del BIFI (Instituto de Biocomputación y Física de Sistemas Complejos). El servicio permite la autenticación de usuarios por perfiles, el control de acceso granular por proyecto, la gestión de miembros e imputación de consumos.

## Estado de la aplicación

Todas las funciones requeridas para el Reto 1 (P1 a P9 del encargo IAW RA5) han sido implementadas y verificadas correctamente en la máquina virtual.

| Función / Módulo | Descripción | Estado |
|---|---|---|
| Autenticación | Login seguro (`password_verify`, `session_regenerate_id`) y logout | Completado |
| Control de Acceso | Redirección HTTP 404 para proyectos no permitidos (privacidad) | Completado |
| Permisos por Perfil | CESAR (alta), Responsables (gestión), Investigadores (lectura) | Completado |
| Validación | Reglas en `validar_proyecto()` y verificación estricta de miembros | Completado |
| Persistencia | Ficheros JSON respaldados en el volumen Docker `datos-panel` | Completado |

## Estructura del código

```text
Dockerfile          PHP 8.3 con Apache. Sirve únicamente el directorio public/
public/             Punto de entrada web accesible públicamente
  index.php         Lista de proyectos visibles según el perfil autenticado
  proyecto.php      Detalle del proyecto, miembros y cálculo de consumos
  proyecto-nuevo.php Formulario de alta (exclusivo para perfil CESAR)
  login.php         Formulario de autenticación
  logout.php        Cierre de sesión y destrucción de variables de sesión
  estilo.css        Estilos visuales de la interfaz
comun/              Lógica interna (protegida de acceso directo por navegador)
  arranque.php      Inicialización de sesión y carga de dependencias
  funciones.php     Funciones auxiliares (escape HTML, lectura/escritura JSON)
  sesion.php        Gestión de sesiones (`entrar()`, `salir()`, `exigir_login()`, `exigir_perfil()`)
  proyectos.php     Visibilidad (`puede_ver()`), gestión de miembros y validaciones
  plantilla.php     Renderizado de la estructura común y menú dinámico según perfil
datos-ejemplo/      Datos iniciales (usuarios, proyectos y usos en JSON)
```

## Usuarios de ejemplo

Todos los usuarios utilizan la contraseña `bifi2026`. Las contraseñas están almacenadas mediante hash seguro en `datos-ejemplo/usuarios.json`.

| Usuario | Perfil | Permisos / Visibilidad |
|---|---|---|
| `ana` | Investigador | Miembro de `BIO-0001` (solo lectura) |
| `luis` | Investigador | Miembro de `FIS-0002` (solo lectura) |
| `marta` | Responsable | Responsable de `BIO-0001` (añade/quita investigadores) |
| `jorge` | Responsable | Responsable de `FIS-0002` (añade/quita investigadores) |
| `cesar` | Administración CESAR | Acceso global y creación de nuevos proyectos |

## Despliegue y Ejecución

El servicio se despliega integrado en la infraestructura de contenedores junto con el servicio web de la sede.

### Arranque de los servicios

Para construir e iniciar los contenedores del servidor web y el panel de proyectos:

```bash
docker compose up -d --build web panel
```

### Acceso a la aplicación

- **Vía Proxy Inverso Apache (Recomendado):** `http://panel.huesca.empresa.lan`
- **Acceso directo por puerto:** `http://192.168.6.2:8081`

### Gestión de datos y volúmenes

Los datos modificados se persisten en el volumen `datos-panel`. Si es necesario restablecer el estado inicial con los datos de ejemplo:

```bash
docker compose down panel
docker volume rm huesca_datos-panel
docker compose up -d panel
```

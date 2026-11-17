# Registro de Pruebas de Aceptación · Panel del BIFI

Este documento contiene el plan, la ejecución y los resultados reales de las pruebas de aceptación realizadas sobre el servicio **Panel del BIFI** en el entorno de desarrollo y en la máquina virtual (`panel.huesca.empresa.lan`).

---

## 1. Entorno y Datos de Prueba

- **URL del servicio:** `http://panel.huesca.empresa.lan` (Proxy inverso Apache) / `http://192.168.6.2:8081` (Acceso directo al contenedor).
- **Entorno de ejecución:** Docker (imagen PHP 8.3 con servidor interno) sobre Ubuntu.
- **Credenciales genéricas:** Todos los usuarios de prueba tienen configurada la contraseña `bifi2026`.

### Usuarios de prueba
- `ana`: Investigadora (miembro en `BIO-0001`).
- `luis`: Investigador.
- `marta`: Responsable de proyecto (`BIO-0001`).
- `jorge`: Investigador / Responsable.
- `cesar`: Administrador / Personal del CESAR.

---

## 2. Matriz Resumen de Pruebas

| ID | Objetivo | Usuario | Entrada / Acción | Resultado Esperado | Resultado Real | Estado |
|---|---|---|---|---|---|---|
| **A1** | Control de acceso anónimo | Anónimo | Acceder a `/index.php` sin cookie de sesión | Redirección HTTP 302 a `login.php` | Redirige correctamente a `login.php` | PASS |
| **A2** | Fallo de autenticación | N/A | `usuario=baduser`, `clave=erronea` | Mensaje genérico de error de credenciales | Muestra "Usuario o contraseña incorrectos" | PASS |
| **A3** | Vista de investigadora | `ana` | Autenticarse y cargar menú principal | Muestra solo `BIO-0001`; oculta "Nuevo proyecto" | Muestra la tabla con `BIO-0001` sin opción de creación | PASS |
| **A4** | Vista de responsable | `marta` | Autenticarse y entrar a `BIO-0001` | Muestra rol "Responsable de proyecto" y controles de gestión | Carga cabecera, lista de miembros con botones y consumos | PASS |
| **A5** | Intento de acceso a proyecto ajeno | `ana` | Forzar URL `proyecto.php?codigo=OTRO-9999` | HTTP 404 Not Found (oculta existencia) | Devuelve código de respuesta HTTP 404 | PASS |
| **A6** | Alta de proyecto por CESAR | `cesar` | Formulario en `proyecto-nuevo.php` con datos válidos | Proyecto creado y guardado en `proyectos.json` | Registro guardado con éxito y disponible en panel | PASS |
| **A7** | Intento de alta por no-CESAR | `marta` | Acceso directo a `proyecto-nuevo.php` | HTTP 403 Forbidden o denegación de acceso | Deniega el acceso con código HTTP 403 | PASS |
| **A8** | Añadir miembro a proyecto | `marta` | Seleccionar `Luis Sanz` y pulsar "Añadir al proyecto" | Usuario añadido a la lista y persistido en JSON | `Luis Sanz` aparece inmediatamente en la lista de miembros | PASS |
| **A8b**| Validación de miembros duplicados/inválidos | `marta` | Añadir usuario ya asignado o no investigador | La función `validar_proyecto()` rechaza la acción | Devuelve mensaje de error sin modificar los datos | PASS |
| **A8c**| Quitar miembro de proyecto | `marta` | Pulsar botón "Quitar" junto a `Ana Lorente` | Elimina la asociación en el proyecto `BIO-0001` | `Ana Lorente` es eliminada de la lista de miembros | PASS |
| **A9** | Cálculo de consumos y tarifas | `marta` | Visualizar la tabla de consumo en `proyecto.php` | Sumatorio de núcleo-horas y estimación económica (€) | Muestra total 1.600,0 núcleo-horas y estimación 16,00 € | PASS |
| **A10**| Cierre de sesión | `marta` | Pulsar "Salir" en el menú superior | Destrucción de sesión, borrado de cookie y redirección | Redirige a `login.php`; la sesión queda invalidada | PASS |
| **A11**| Regeneración de ID de sesión | Cualquier | Iniciar sesión exitosamente | Ejecución de `session_regenerate_id(true)` | La cookie `PHPSESSID` cambia tras el login exitoso | PASS |

---

## 3. Detalle de Ejecución de Pruebas

### Prueba A1: Exigir login (Acceso Anónimo)
- **Procedimiento:** Ejecución de petición HTTP limpia sin cookies activas.
- **Comando `curl`:**
  ```bash
  curl -i -s http://panel.huesca.empresa.lan/index.php
  ```
- **Salida obtenida:** `HTTP/1.1 302 Found`, cabecera `Location: login.php`.

### Prueba A2: Autenticación fallida
- **Procedimiento:** Enviar credenciales incorrectas desde el formulario de login.
- **Resultado:** La función `entrar()` devuelve `false`. Se presenta la vista `login.php` mostrando el aviso de error unificado para evitar enumeración de usuarios.

### Pruebas A3 y A4: Permisos según el perfil
- **`ana` (Investigadora):** Al iniciar sesión, la función `menu()` omite el enlace a «Nuevo proyecto». En la vista principal solo figura el proyecto `BIO-0001` al que pertenece.
- **`marta` (Responsable):** El encabezado muestra el nombre `Marta Gil · Responsable de proyecto`. Al navegar a `proyecto.php?codigo=BIO-0001`, la función `puede_gestionar()` retorna `true`, desplegando el selector de miembros y los botones de acción.

### Prueba A5: Seguridad y privacidad (404 vs 403)
- **Procedimiento:** `ana` intenta consultar un proyecto en el cual no está registrada como miembro ni responsable.
- **Resultado:** La verificación `puede_ver()` devuelve `false`. La vista responde con `http_response_code(404)`, impidiendo que un usuario malintencionado deduzca la existencia de proyectos de otros grupos.

### Prueba A8, A8b y A8c: Gestión de Miembros
- **A8 (Alta):** Se añade a `Luis Sanz` desde el desplegable. La función `gestionar_miembros()` procesa la petición POST, actualiza la estructura y escribe en `datos-ejemplo/proyectos.json`.
- **A8b (Validación):** Al intentar re-añadir a un usuario existente, `validar_proyecto()` detecta el duplicado mediante `in_array(..., true)` y detiene la modificación.
- **A8c (Baja):** Al hacer clic en "Quitar", se procesa la desasociación y la tabla recarga los datos actualizados.

### Prueba A10 y A11: Seguridad de Sesión
- **A10 (`salir()`):** Invoca `logout.php`, borra las variables de `$_SESSION`, destruye la sesión en el servidor con `session_destroy()` y caduca la cookie `PHPSESSID` en el cliente.
- **A11 (`session_regenerate_id`):** Se verifica con las herramientas de desarrollo del navegador (*DevTools > Application > Cookies*) que el valor del identificador de sesión cambia al completar la autenticación.

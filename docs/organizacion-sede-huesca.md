# Organización del equipo · Sede Huesca (`huesca.empresa.lan`)

> Para pegar en el `README` del repositorio el primer día. Sustituid `Persona 1..4` por los
> nombres reales.

## 0. Datos de la sede (los rellena Dirección de Sistemas)

| Dato | Valor |
|---|---|
| Sede | Huesca |
| Dirección fija del servidor en la red del aula | |
| Máscara y puerta de enlace de la red del aula | |
| Resolutor de nombres del centro | |
| Usuario del profesorado en vuestro Forgejo | |
| Red interna | `10.5.0.0/24` |

## 1. Quién es quién

| Persona | Responsable de | Segunda/o en |
|---|---|---|
| Persona 1 | Nombres y red (SRI) | Datos |
| Persona 2 | Servidor, acceso remoto y Forgejo (ASO + Optativo) | Nombres y red |
| Persona 3 | Web (IAW) | Servidor, acceso y Forgejo |
| Persona 4 | Datos + Seguridad transversal (ASGBD + SAD) | Web |

Ciclo cerrado: P1→P2→P3→P4→P1.

## 2. Coordinación rotatoria

| Semana | Coordina |
|---|---|
| S1 | Persona 1 |
| S2 | Persona 2 |
| S3 | Persona 3 (+ verificación cruzada con Zaragoza) |
| S4 | Persona 4 (+ cierre de documentación final) |

Quien coordina esa semana: mantiene el tablero de incidencias, escribe el cuaderno de sede con
lo que aporta cada área, y revisa que todos tengan tarea asignada.

---

## 3. Lista de tareas imprescindibles, por persona

Sin fechas: se marcan cuando estén hechas de verdad (funciona y está en el repositorio), no
cuando alguien las empieza. Entre paréntesis, la necesidad o prueba a la que responde.

### Persona 1 — Nombres y red

**Investigación**
- [ ] Investigación de nombres fusionada por PR antes de implementar nada: qué es, cómo funciona
  con diagrama propio, tres alternativas Linux/Windows en tabla, elección justificada, fuentes

**Servicio de nombres**
- [ ] Existen los nombres `ns1, ns2, srv, www, intranet, git, db, correo` y los de los clientes;
  `www/intranet/git/db` son alias del servidor, no direcciones repetidas (N5)
- [ ] Vuestro servidor responde como fuente oficial de `<sede>.empresa.lan`, no como intermediario (N1)
- [ ] Dada una dirección interna, se obtiene el nombre del equipo (N6)
- [ ] Reenvía a internet solo lo que no es de la sede, y solo para vuestros clientes (N7, N8)
- [ ] La segunda consulta a un nombre de internet no vuelve a salir fuera (caché) (N9)
- [ ] El propio servidor usa vuestro DNS, no el del centro (N10)

**Segundo servidor de nombres**
- [ ] Existe un segundo servidor de nombres con la misma información que el primero, sin copiarla
  a mano (N2)
- [ ] Solo el segundo puede pedir la lista completa de nombres; cualquier otro recibe negativa (N3)
- [ ] Un nombre nuevo llega al segundo en menos de un minuto (N4)
- [ ] Si el primero cae, el segundo sigue respondiendo como fuente oficial (prueba 7)

**Red interna (GNS3)**
- [ ] Red `10.2.0.0/24` en GNS3 con el segundo servidor de nombres y al menos dos clientes (R1)
- [ ] Desde el aula, con vuestro servidor como resolutor, se llega por nombre a `www`, `intranet`, `git` (R4)
- [ ] Topología de GNS3 en el repositorio, igual que en la documentación (R5)

**Verificación y documentación**
- [ ] Pruebas 1–11 y 16 pasadas por vosotros antes de que llegue el otro grupo
- [ ] Sección "Red" de la documentación final cerrada (diagrama con direcciones, topología)
- [ ] Sabéis dibujar la red en pizarra y recorrer una consulta de nombre de principio a fin

### Persona 2 — Servidor, acceso remoto y Forgejo

**Investigación**
- [ ] Investigación de acceso remoto fusionada
- [ ] Investigación de contenedores fusionada

**Servidor**
- [ ] Ubuntu Server LTS instalado
- [ ] Un usuario con permisos de administración por persona; nadie usa root directamente (S1)
- [ ] Acceso solo por clave SSH, sin contraseñas, desde los cuatro portátiles (S2)
- [ ] Tras un reinicio real, red interna, salida a internet y todos los servicios vuelven solos,
  sin tocar nada (S3)
- [ ] Todos los servicios corren en contenedores gestionados con Compose (S4)
- [ ] El servidor está en las dos redes (aula e interna) y hace de salida de la interna (R2, R3)

**Forgejo**
- [ ] Forgejo responde en `git.<sede>.empresa.lan`; sus datos sobreviven a que se destruya el
  contenedor (volumen persistente) (F1)
- [ ] Una cuenta por miembro y una de administración para el profesorado; nadie se crea cuenta
  sola (F2)
- [ ] Repositorio dentro de una organización con el nombre de la sede; clonado por SSH en puerto
  distinto del 22, con la dirección de clonado correcta (F3)
- [ ] Etiquetas y plantillas de incidencia creadas antes de la primera tarea (F4)
- [ ] Copia de seguridad de Forgejo hecha y restauración comprobada (F5)

**Verificación y documentación**
- [ ] Pruebas 2, 11, 15, 16, 18, 19, 20 pasadas por vosotros antes de la verificación
- [ ] Secciones "Instalación desde cero" y "Operación" de la documentación final cerradas

### Persona 3 — Web

**Investigación**
- [ ] Investigación web fusionada: Apache y alternativas en tabla, elección justificada

**Apache**
- [ ] `www.<sede>.empresa.lan` sirve la web pública con Apache (W1)
- [ ] `intranet.<sede>.empresa.lan` es un sitio distinto que pide usuario y contraseña; fichero
  de contraseñas fuera del repositorio (W2)
- [ ] Una página muestra un dato real leído de la base de datos: versión del gestor y número de
  filas de la tabla propia, con consulta preparada y errores controlados (W3)
- [ ] Los registros de Apache se pueden consultar y sabéis leer un error en ellos (W7)

**Verificación y documentación**
- [ ] Pruebas 1, 12, 13 pasadas por vosotros antes de la verificación
- [ ] Sección de cada servicio web en la documentación final, con los ficheros de configuración
  explicados donde importe

### Persona 4 — Datos y seguridad

**Investigación**
- [ ] Investigación de base de datos fusionada: PostgreSQL y alternativas en tabla, requisitos
  verificados

**Base de datos**
- [ ] PostgreSQL en contenedor, con volumen y fichero de entorno; credenciales fuera de Git, con
  plantilla de ejemplo dentro (W4)
- [ ] Tabla propia con al menos veinte filas de datos de la sede (W4)
- [ ] El puerto de PostgreSQL no responde desde la red del aula (W5)
- [ ] Copia de seguridad de PostgreSQL hecha y restauración comprobada sobre base vacía (W6)
- [ ] Sabéis conectar desde el contenedor web, y leer un error en los registros de PostgreSQL (W7)

**Seguridad**
- [ ] Política de contraseñas escrita y aplicada en servidor, Forgejo, intranet y base de datos (P1)
- [ ] Datos que gestiona la sede clasificados: cuáles son personales y qué obligaciones traen (P2)
- [ ] Ninguna clave privada sale del equipo de su dueño (P3)
- [ ] Nadie entra en un servicio de otra sede sin invitación escrita de esa sede (P4)

**Verificación y documentación**
- [ ] Pruebas 13, 14, 18, 20 pasadas por vosotros antes de la verificación
- [ ] Secciones de seguridad y datos personales de la documentación final cerradas

---

## 4. Comunes a los cuatro, siempre

- [ ] Toda tarea empieza con una incidencia (`tarea` + módulo) asignada a una persona
- [ ] Ninguna implementación sin la investigación de ese servicio ya fusionada
- [ ] Cuaderno de sede con una entrada por sesión, escrita ese mismo día
- [ ] Nada se hace a mano en el servidor sin pasar por el repositorio
- [ ] Cada confirmación con identidad propia y mensaje que explica qué cambia y por qué
- [ ] Ninguna contraseña ni clave en el repositorio ni en su historial

## 5. Cómo pedir ayuda

1. Antes de nada: mirar registros, cuaderno de sede, buscar.
2. Incidencia con etiqueta `ayuda` + módulo, asignada al profesor/a responsable. Título =
   síntoma. Cuerpo: qué queréis conseguir, qué habéis hecho, qué veis (salida pegada, no
   descrita), dónde está en el repositorio.
3. Respuesta en un día lectivo máximo. Se cierra desde la confirmación que la resuelve.

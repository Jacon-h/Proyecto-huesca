Parte B · Investigación
1. La necesidad
Instalar servicios directamente sobre el sistema operativo base (bare-metal o máquina virtual anfitriona) crea un acoplamiento rígido entre las dependencias del software y el sistema operativo.

Qué problema resuelve la contenerización
Aislamiento de dependencias: Evita colisiones de librerías (por ejemplo, dos aplicaciones que requieren versiones distintas de Python, PHP o GLIBC).

Portabilidad estricta: Elimina el clásico problema de "en mi máquina funciona". La imagen empaqueta el binario, las librerías del espacio de usuario y las configuraciones exactas.

Ciclo de vida efímero: Los contenedores pueden destruirse y recrearse en segundos sin dejar basura técnica, archivos residuales ni registros alterados en el SO anfitrión.

Qué gana quien administra
Inmutabilidad y repetibilidad: Despliegues idénticos en desarrollo, pruebas y producción.

Control fino de recursos: Capacidad de limitar memoria CPU/RAM por servicio vía cgroups.

Facilidad de migración y respaldo: Desplazar la pila a un nuevo servidor requiere únicamente copiar la configuración (docker-compose.yml, secretos) y restaurar los volúmenes de datos.

Qué se complica
Complejidad de red y persistencia: Es necesario abstraer las capas de red virtual y gestionar explícitamente el almacenamiento persistente mediante volúmenes.

Monitoreo y depuración: La observabilidad requiere inspeccionar logs redirigidos a stdout/stderr y abstraer procesos que ya no son visibles de forma nativa en el espacio de usuario habitual.

Seguridad de capas: Un mal diseño de la imagen o ejecutar procesos con privilegios de root dentro del contenedor incrementa la superficie de ataque.

Por qué "lo instalo a mano y tomo notas" no es equivalente
Documentar pasos manuales es propenso al error humano y no contempla los cambios del entorno a lo largo del tiempo.

Ejemplo 3 semanas después: Se actualiza un paquete del sistema anfitrión (sudo apt upgrade actualiza libssl o la versión del motor de base de datos). La aplicación instalada a mano deja de funcionar por una incompatibilidad de librerías compartidas. Además, si el administrador original enferma, reinstalar el servidor desde las notas requiere horas de prueba y error intentando adivinar dependencias implícitas que no se anotaron. En Docker, la imagen guardó el entorno exacto del día 1 y levantará de forma idéntica sin importar las actualizaciones del SO anfitrión.

2. El servicio: Anatomía y ejecución de Docker
Al ejecutar el comando docker compose up -d, la herramienta interactúa con la API de Docker y ejecuta la siguiente secuencia cronológica interna:

1) Parseo y orquestación: Lee y valida la sintaxis del archivo docker-compose.yml, expande las variables del archivo .env y resuelve las dependencias entre servicios (depends_on).

2) Obtención y ensamblado de imágenes (Capas): Comprueba en el almacenamiento local si existen las imágenes. Si no están, las descarga (pull) del registro. Cada imagen se compone de capas de solo lectura ensambladas mediante el sistema de archivos unificado overlay2.

3) Creación de la infraestructura de red: Si la red declarada no existe, el motor crea una red virtual (bridge), asigna una subred IP interna y configura interfaces de red virtuales (veth) acopladas a la red anfitriona. Configura las reglas de iptables/nftables en el anfitrión para la publicación de puertos.

4) Provisionamiento de volúmenes: Inicializa o vincula los volúmenes con nombre (/var/lib/docker/volumes/) o bind mounts.

5) Creación y ejecución del contenedor (Runtime): Llama al runtime de bajo nivel (containerd / runc) para instanciar el proceso. Para cada contenedor se configuran:

     - Namespaces: Aísla la vista del sistema (PID procesos, NET red, MNT puntos de montaje, IPC comunicación entre procesos, UTS hostname).

     - cgroups: Limita y monitoriza los recursos asignados (CPU, RAM, I/O).

     - Capa de escritura (Container Layer): Añade una capa delgada de lectura/escritura en la parte superior del apilamiento overlay2.

6) Desacoplamiento y captura de registros: Arranca el proceso principal (PID 1) definido en el CMD/ENTRYPOINT. Desconecta la salida a la terminal (modo -d) y conecta stdout y stderr del proceso al driver de registro configurado (json-file por defecto).

3. Alternativas de Aislamiento

| Criterio | Docker Engine | Podman | LXC / LXD (Incus) | Máquina Virtual (KVM / Hyper-V) |
| :--- | :--- | :--- | :--- | :--- |
| **Qué es y quién lo mantiene** | Motor de contenedores de aplicaciones (Docker Inc. / Moby Project). | Motor de contenedores sin demonio (Red Hat / CNCF). | Contenedores de sistema operativo completo (Canonical / Linux Containers). | Virtualización por hardware completo (Kernel/Procesador). |
| **Licencia** | Apache 2.0 (Motor open source). *Docker Desktop requiere pago en empresas*. | Apache 2.0 (100% libre y gratuito). | Apache 2.0 / GPLv2. | GPLv2 (KVM) / Propietaria (Hyper-V). |
| **Qué aísla y qué comparte** | Aísla procesos y ficheros mediante Namespaces/cgroups. **Comparte Kernel Linux**. | Aísla procesos y ficheros mediante Namespaces/cgroups. **Comparte Kernel Linux**. | Aísla un entorno de SO completo. **Comparte Kernel Linux**. | Aísla Hardware completo. **Kernel totalmente independiente**. |
| **Sistemas donde corre** | Linux nativo. En Windows/macOS corre dentro de una MV (WSL2 / Hyper-V). | Linux nativo. En Windows/macOS corre dentro de una MV (Podman Machine). | Linux nativo únicamente. | Cualquier SO con soporte de virtualización por hardware (VT-x/AMD-V). |
| **Necesita root** | **Sí**, el demonio `dockerd` corre como `root` (salvo configuración Rootless). | **No**, diseñado nativamente para ser *Rootless* desde el espacio de usuario. | Típicamente requiere `root` (LXD), aunque admite contenedores unprivileged. | Requiere `root` para inicializar los módulos del Hypervisor en el Kernel. |
| **Varios servicios juntos** | `docker compose` (Nativo). | `podman compose` o lectura directa de pods/manifests de Kubernetes. | Orquestación vía scripts, Juju, o Ansible. | Vagrant, Terraform u orquestadores de hipervisores. |
| **Arranque y consumo** | **Arranque:** ~100 ms.<br>**Consumo:** ~10-30 MB RAM overhead base. | **Arranque:** ~100 ms.<br>**Consumo:** ~10-20 MB RAM (al no tener demonio permanente). | **Arranque:** 1 - 3 segundos.<br>**Consumo:** ~50-100 MB RAM (corre `init/systemd`). | **Arranque:** 15 - 45 segundos.<br>**Consumo:** >512 MB a varios GB RAM reservados fijos. |
| **Qué hace bien / qué hace mal** | **Bien:** Estándar de la industria, enorme ecosistema.<br>**Mal:** Demonio central con privilegios elevados (`root`). | **Bien:** Mayor seguridad (*Rootless* y sin demonio).<br>**Mal:** Ligera incompatibilidad en redes complejas frente a Docker Compose. | **Bien:** Ideal para reemplazar MVs tradicionales ligeras.<br>**Mal:** No está optimizado para microservicios de una sola app. | **Bien:** Aislamiento total de seguridad y kernels distintos.<br>**Mal:** Elevado consumo de RAM, CPU y disco. |

4. Elección y Justificación
Justificación del uso de Docker Compose
Docker Compose proporciona la declaración declarativa del estado de la infraestructura. Aporta:

Resiliencia ante reinicios: Con la directiva restart: unless-stopped, el propio motor levantará todos los servicios automáticamente tras una caída de tensión o reinicio del servidor físico.

Reproducibilidad y Documentación viva: Un administrador ajeno puede clonar el repositorio y ejecutar docker compose up -d en un servidor limpio, obteniendo la infraestructura exacta en minutos sin intervención manual.

Qué perderíamos si hubiéramos elegido otra alternativa
Si eligiéramos Podman: Perderíamos la integración directa y sin fricciones de docker compose oficial y el ecosistema estandarizado de la comunidad para la gestión de volúmenes.

Si eligiéramos LXC/LXD: Perderíamos la ligereza del concepto de "un proceso por contenedor", teniendo que administrar internamente cada contenedor como un sistema operativo completo (actualizaciones apt, gestión de systemd).

Si eligiéramos Máquinas Virtuales (KVM/VirtualBox): Perderíamos el rendimiento nativo del hardware, la eficiencia en el uso de memoria RAM y la velocidad de despliegue (minutos frente a segundos).



6. Fuentes y Referencias
Docker Documentation (Core & Architecture): https://docs.docker.com/get-started/overview/ (Consultado el 22/09/2026).

Compose File Specification: https://docs.docker.com/compose/compose-file/ (Consultado el 22/09/2026).

Podman Official Documentation: https://podman.io/docs (Consultado el 22/09/2026).

Linux Containers (LXC/LXD/Incus): https://linuxcontainers.org/ (Consultado el 22/09/2026).

Red Hat Container Security Guide: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/ (Consultado el 22/09/2026).


Preguntas de Pizarra 
1. docker compose down y luego docker compose up -d: ¿Qué desaparece y qué no? ¿Dónde están los datos de Forgejo en ese momento?Qué desaparece: Se destruyen los contenedores, la capa de escritura efímera del contenedor, las interfaces de red virtuales asignadas y la tabla de procesos en memoria del anfitrión.  Qué NO desaparece: Las imágenes descargadas/construidas, las redes declaradas (se recrean idénticas) y los volúmenes nombrados de Docker.  Ubicación de los datos de Forgejo: En el volumen nombrado montado en la máquina anfitriona (por defecto dentro del directorio del motor en /var/lib/docker/volumes/<nombre_proyecto>_forgejo_data/_data). Los datos no se ven afectados por el comando down.  
2. Tres contenedores, dos redes y un puerto publicado: ¿Quién alcanza a quién? ¿Dónde queda la base de datos?Red 1 (Frontend): Conecta Web y App.Red 2 (Backend): Conecta App y Database.Puerto Publicado: Únicamente Web publica el puerto 80/443 al anfitrión.Matriz de alcanzabilidad:Desde otro contenedor en Red 1: Web y App se alcanzan por nombre.Desde otro contenedor en Red 2: App y Database se alcanzan por nombre.Inter-Redes: Web NO puede alcanzar a Database directamente porque no comparten interfaz en la misma red de Docker.Desde el Anfitrión: Solo puede alcanzar a Web a través del puerto publicado en localhost o la IP del servidor.Desde otro equipo de la red física: Solo puede alcanzar a Web.Ubicación de la Base de Datos: Queda aislada exclusivamente dentro de la red privada Backend, inaccesible directamente desde el anfitrión o desde la red física externa.
3. Un compañero propone privileged: true en el contenedor web para no tener problemas de permisos. ¿Qué le decís?Respuesta técnica: "Aceptar privileged: true elimina las barreras de seguridad del contenedor. Otorga al contenedor casi todas las capacidades del Kernel del anfitrión (CAP_SYS_ADMIN), deshabilita los perfiles AppArmor/SELinux y permite el acceso a todos los dispositivos en /dev del anfitrión. Si el servidor web sufre una vulnerabilidad de ejecución remota de código (RCE), el atacante tomará el control total de la máquina física (Container Escape). Los problemas de permisos se resuelven asignando correctamente el propietario (chown) o ajustando el UID/GID dentro del volumen, jamás elevando los privilegios del contenedor."  
4. El servidor se reinicia de madrugada. ¿Qué tiene que pasar para que a las ocho esté todo funcionando sin que nadie toque nada?
   - A nivel del sistema operativo anfitrión: El servicio del motor de Docker debe estar habilitado en el arranque del sistema operativo mediante systemctl enable docker.service.

   - A nivel de la configuración de Docker Compose: Todos los servicios dentro del archivo docker-compose.yml deben incluir la directiva de política de reinicio: restart: unless-stopped (o restart: always).

   - Flujo automático al arrancar: Al iniciar Ubuntu, el demonio dockerd se ejecuta automáticamente, inspecciona los contenedores que estaban activos antes del apagado y vuelve a levantar el grafo de dependencias de la pila en segundo plano sin requerir interacción humana.
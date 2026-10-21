# red/ · SRI · ASO

Red del servidor: interfaz del aula, puente de la red interna, reenvío, NAT.

- netplan, `sysctl`, reglas de NAT: lo que hoy está hecho a mano en el servidor, como fichero.
- Lo que haga falta para que Docker no corte el NAT de la red interna.

Plantilla: 
# red/ · SRI · ASO

Red del servidor, instalada por la fase `red` de `instalar.sh`.

| Fichero | Qué hace |
|---|---|
| `netplan/60-sede.yaml.tpl` | IP fija en la interfaz del aula y puente de la red interna. Los valores salen de `sede.env`. |
| `sysctl/99-sede.conf` | Activa el reenvío de paquetes (`ip_forward`). |
| `nat/sede-nat.sh` | NAT (masquerade) de la red interna hacia el aula y reglas en `DOCKER-USER`. |
| `nat/sede-nat.service` | Aplica las reglas en cada arranque, después de Docker. |

**Por qué `DOCKER-USER`:** Docker deja `FORWARD` en DROP y cortaría el NAT de la red interna.
Esa cadena no la toca Docker, así que las reglas sobreviven a reinicios de Docker.

**Por qué en este orden (DS9):** va antes de web y db, que necesitan salida a Internet para
descargar imágenes. No deja el servidor sin acceso porque la IP del aula no cambia.

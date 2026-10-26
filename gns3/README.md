# gns3/ · SRI

Proyecto de GNS3 de la red interna y la configuración de sus nodos.

Plantilla: borrad esta línea y explicad cómo se abre el proyecto y qué hay que tener antes.
# gns3/ · SRI

Proyecto de GNS3 de la red interna de la sede Huesca (`red_huesca.gns3project`) y la configuración de sus nodos.

## Qué hay que tener antes

- GNS3 2.2.x con el servidor local, en **el propio servidor de la sede** (el proyecto usa su interfaz `enp5s0`).
- La fase `red` de `instalar.sh` ya ejecutada: crea el puente `br-virtual` (10.2.0.1/24), al que se conecta el proyecto.
  Sin él, el nodo Cloud1 no tiene dónde engancharse.
- La imagen Docker `dns-secundario:1.0` en el Docker local (`docker image ls dns-secundario:1.0`).
- Un usuario con permiso para GNS3 (grupos `ubridge` y `docker`).

## Cómo se abre

1. GNS3 → *File → Import portable project* → `gns3/red_huesca.gns3project`.
2. Es normal que avise de interfaces que no existen en esta máquina (`br-…`, `wlp7s0`): solo se usa `br-virtual`.
3. Arrancad todos los nodos (el proyecto no los arranca solo).

## Topología

```
Cloud1 (br-virtual) ── Switch1 ─┬─ PC1
                                ├─ PC2
                                └─ dns-secundario-1
```

| Nodo | Tipo | Dirección | Puerto de Switch1 |
|---|---|---|---|
| Cloud1 | Cloud → `br-virtual` | 10.2.0.1 (el servidor) | Ethernet0 |
| PC2 | VPCS | 10.2.0.21/24, puerta 10.2.0.1, DNS 10.2.0.1 | Ethernet1 |
| PC1 | VPCS | 10.2.0.20/24, puerta 10.2.0.1, DNS 10.2.0.1 | Ethernet2 |
| dns-secundario-1 | Docker `dns-secundario:1.0` | 10.2.0.2/24, puerta 10.2.0.1, DNS 10.2.0.1 | Ethernet3 |

Los datos de red coinciden con `sede.env` (`RED_INTERNA=10.2.0.0/24`, `IP_INTERNA=10.2.0.1/24`).
La configuración de los PC está en `project-files/vpcs/*/startup.vpc` y la del secundario en
`project-files/docker/<id>/etc/network/interfaces`, dentro del proyecto.

El BIND del secundario (zonas `slave`) se carga con el fichero que genera `sudo ./instalar.sh dns` en
`generado/dns-secundario/named.conf.local`; ver `dns/README.md`.

## Pruebas

Desde la consola de PC1 o PC2:

```
ping 10.2.0.1        # llega al servidor
ping 8.8.8.8         # sale por el NAT de la fase red
ping google.com      # resuelve con el DNS
```

## Si no responde

- `ip -br addr show br-virtual` en el servidor: debe tener `10.2.0.1/24` y estar `UP`.
- `sudo iptables -S DOCKER-USER`: deben estar las reglas de la fase `red`.
- Comprobad que los nodos están arrancados y que el enlace Cloud1 → Switch1 es verde.
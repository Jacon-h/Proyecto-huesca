# web/ · IAW

`Dockerfile` de la imagen propia, sitios de Apache y contenido (`www`, `intranet`, página de estado).

El fichero de contraseñas de la intranet no va aquí: va en `secretos/intranet.htpasswd`, fuera de Git, y se monta desde `compose.yaml`.

# Servidor Web y Base de Datos - Sede Huesca

Este directorio contiene la infraestructura web completa para la Sede Huesca (`huesca.empresa.lan`), compuesta por un servidor **Apache con PHP 8.2** (`mi-apache`) y un motor de base de datos **PostgreSQL 16** (`mi-postgres`).

---

## 📁 Estructura del Módulo

- Los contenedores se definen en el `compose.yaml` de la raíz.
- `Dockerfile`: Construcción de la imagen PHP + Apache instalando extensiones de PostgreSQL.
- `huesca.conf`: Configuración de VirtualHosts (`www` e `intranet`).
- El `.htpasswd` de la intranet lo genera `instalar.sh` en `secretos/` a partir de `.env`.
- `www/`: Código PHP del portal público.
- `intranet/`: Código PHP de la intranet privada.

---

## 🚀 Arranque del Servidor Web en un solo comando

Ejecuta desde la raíz del repositorio:

```bash
sudo ./instalar.sh web
```


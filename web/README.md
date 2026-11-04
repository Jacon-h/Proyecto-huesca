# web/ · IAW

`Dockerfile` de la imagen propia, sitios de Apache y contenido (`www`, `intranet`, `estado.php`).

El fichero de contraseñas de la intranet no va aquí: va en `secretos/intranet.htpasswd`, fuera de Git, y se monta desde `compose.yaml`.

# Servidor Web y Base de Datos - Sede Huesca

Este directorio contiene la infraestructura web completa para la Sede Huesca (`huesca.empresa.lan`), compuesta por un servidor **Apache con PHP 8.2** (`mi-apache`) y un motor de base de datos **PostgreSQL 16** (`mi-postgres`).

---

## 📁 Estructura del Módulo

- Los contenedores se definen en el `compose.yaml` de la raíz.
- La web entra en PostgreSQL con `DB_USER`, un usuario que **no puede borrar** (ver `db/README.md`); por eso la página no tiene botón de borrar.
- `Dockerfile`: Construcción de la imagen PHP + Apache instalando extensiones de PostgreSQL.
- `huesca.conf`: Configuración de VirtualHosts (`www` e `intranet`).
- El `.htpasswd` de la intranet lo genera `instalar.sh` en `secretos/` a partir de `.env`.
- `www/`: Código PHP del portal público. `www/estado.php` es la página de estado: responde `ESTADO: OK` y el número de filas de la base (`curl -H "Host: www.huesca.empresa.lan" http://localhost/estado.php`).
- `intranet/`: Código PHP de la intranet privada.

---

## 🚀 Arranque del Servidor Web en un solo comando

Ejecuta desde la raíz del repositorio:

```bash
sudo ./instalar.sh web
```


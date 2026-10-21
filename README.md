# Sede <huesca> · <huesca>.empresa.lan

Plantilla común del [encargo 5](../encargos/despliegue.md). Copiadla a la carpeta de vuestra sede,
rellenad todo lo que va entre `< >` y borrad las líneas de ayuda que empiezan por «Plantilla:».

## Despliegue

En un Ubuntu Server 24.04 recién instalado, con la IP de la sede y OpenSSH:

```bash
git clone <repositorio> && cd <carpeta>
cp .env.example .env && nano .env
sudo ./instalar.sh
```

Una sola fase: `sudo ./instalar.sh <fase>`. Se puede repetir sin romper nada.

## Fases

Plantilla: una fila por fase, en el orden en que se ejecutan. La última columna justifica el orden
(DS9): por qué esta fase va aquí y por qué no deja el servidor sin acceso.

| Fase | Módulo | Qué hace | Por qué en este lugar |
|---|---|---|---|
| `comprobar` | — | <qué comprueba antes de tocar nada> | Siempre la primera |
| `<fase>` | <módulo> | <qué hace> | <por qué aquí> |
| `verificar` | Todos | <qué pruebas del encargo comprueba> | Siempre la última |

## Carpetas

| Carpeta | Módulo | Responsable | Contenido |
|---|---|---|---|
| `sistema/` | ASO | <nombre> | <qué hay> |
| `red/` | SRI · ASO | <nombre> | <qué hay> |
| `dns/` | SRI | <nombre> | <qué hay> |
| `web/` | IAW | <nombre> | <qué hay> |
| `db/` | ASGBD | <nombre> | <qué hay> |
| `gns3/` | SRI | <nombre> | <qué hay> |
| `docs/` | Todos | <nombre> | Cuaderno, investigaciones, documentación final |

## Datos y claves

- Datos de la sede (IP, interfaz, red interna, dominio, resolutor): `sede.env`. Van en Git.
- Claves: `.env`, que no va en Git. Las que hacen falta están en `.env.example`.

## Última prueba en limpio

Plantilla: fecha, máquina, quién la hizo (de otra sede, prueba A7) y salida de la fase
`verificar`. El enlace a la PR donde está la salida completa.

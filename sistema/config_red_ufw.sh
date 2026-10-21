#!/bin/bash
# Cortafuegos UFW. (Las redes de Docker las crea compose.yaml: aquí ya no hace falta crearlas.)
echo "=== Aplicando UFW ==="
ufw default deny incoming  2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw allow 22/tcp   2>/dev/null || true   # SSH del servidor
ufw allow 80/tcp   2>/dev/null || true   # web
ufw allow 53/tcp   2>/dev/null || true   # DNS (transferencias y respuestas grandes)
ufw allow 53/udp   2>/dev/null || true   # DNS
ufw allow 3000/tcp 2>/dev/null || true   # Forgejo web
ufw allow 2222/tcp 2>/dev/null || true   # Forgejo SSH

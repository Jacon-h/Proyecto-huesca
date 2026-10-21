#!/bin/bash
set -e
source /etc/sede/sede.env

# Añade la regla solo si no existe (así se puede repetir)
iptables -N DOCKER-USER 2>/dev/null || true

# NAT: la red interna sale al aula con la IP del servidor
iptables -t nat -C POSTROUTING -s "$RED_INTERNA" -o "$INTERFAZ_AULA" -j MASQUERADE 2>/dev/null ||
  iptables -t nat -A POSTROUTING -s "$RED_INTERNA" -o "$INTERFAZ_AULA" -j MASQUERADE

# Docker no debe cortar el reenvío: interna -> aula, y las respuestas de vuelta
iptables -C DOCKER-USER -i "$BRIDGE_INTERNA" -o "$INTERFAZ_AULA" -j ACCEPT 2>/dev/null ||
  iptables -I DOCKER-USER 1 -i "$BRIDGE_INTERNA" -o "$INTERFAZ_AULA" -j ACCEPT
iptables -C DOCKER-USER -i "$INTERFAZ_AULA" -o "$BRIDGE_INTERNA" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null ||
  iptables -I DOCKER-USER 2 -i "$INTERFAZ_AULA" -o "$BRIDGE_INTERNA" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
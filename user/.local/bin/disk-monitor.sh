#!/bin/bash

# configuração
THRESHOLD=90
PARTITION="/home"

# Obtém a porcentagem de uso (apenas o número)
USAGE=$(df "$PARTITION" --output=pcent | tail -1 | tr -dc '0-9')

if [ "$USAGE" -ge "$THRESHOLD" ]; then
  # Envia notificação crítica (permanece na tela até ser fechada)
  notify-send -u critical \
    -i drive-harddisk-system \
    "⚠ Alerta Crítico de Disco" \
    "O uso da partição $PARTITION atingiu ${USAGE}%. Limpe arquivos imediatamente."
fi

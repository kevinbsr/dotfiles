#!/usr/bin/env bash

brightnessctl set "$1" --quiet

CURRENT=$(brightnessctl get)
MAX=$(brightnessctl max)
PERCENT=$((100 * CURRENT / MAX))

# OSD. O Omarchy 4 trocou o swayosd pelo OSD proprio do shell, e este script,
# por substituir o omarchy-brightness-display via hl.unbind() no bindings.lua,
# herdou a tecla mas nao a notificacao -- era por isso que volume e brilho do
# teclado mostravam o toast e o brilho da tela nao.
# O empacotado faz o equivalente na linha 87/121: omarchy-osd -i brightness -p N
omarchy-osd -i brightness -p "$PERCENT" 2>/dev/null || true

pkill -f "ddcutil.*setvcp 10" 2>/dev/null

ddcutil --display 1 setvcp 10 $PERCENT &
ddcutil --display 2 setvcp 10 $PERCENT &
ddcutil --display 3 setvcp 10 $PERCENT &

# LOCKFILE="tmp/brightness_change.lock"
# [ -f "$LOCKFILE" ] && exit 0
# touch "$LOCKFILE"
#
# step=10
#
# case "$1" in
#   up)
#     brightnessctl set ${step}%+
#     ddcutil setvcp 10 + ${step} --bus 1 &
#     ddcutil setvcp 10 + ${step} --bus 2 &
#     ddcutil setvcp 10 + ${step} --bus 3 &
#     ;;
#   down)
#     brightnessctl set ${step}%-
#     ddcutil setvcp 10 - ${step} --bus 1 &
#     ddcutil setvcp 10 - ${step} --bus 2 &
#     ddcutil setvcp 10 + ${step} --bus 3 &
#     ;;
# esac
#
# sleep 0.1
# rm "$LOCKFILE"

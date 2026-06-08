#!/bin/bash

VOLUME=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk '{printf "%.0f", $2 * 100}')

if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
  echo "{\"text\": \"󰍭\", \"class\": \"muted\", \"tooltip\": \"Mic muted at ${VOLUME}%\"}"
else
  echo "{\"text\": \"󰍬\", \"class\": \"active\", \"tooltip\": \"Mic volume at ${VOLUME}%\"}"
fi

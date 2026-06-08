#!/bin/bash

if fuser /dev/video* 2>/dev/null | grep -q .; then
  echo '{"text": "󰄀", "class": "active", "tooltip": "Webcam in use"}'
else
  echo '{"text": "", "class": "hidden"}'
fi

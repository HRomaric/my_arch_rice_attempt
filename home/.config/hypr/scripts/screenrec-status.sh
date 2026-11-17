#!/usr/bin/env bash
# Waybar module: red dot + elapsed time while wf-recorder runs, nothing otherwise.
pid=$(pgrep -xo wf-recorder) || { echo; exit 0; }
s=$(ps -o etimes= -p "$pid" | tr -d ' ')
printf '{"text":"● %02d:%02d","class":"recording","tooltip":"Recording — click to stop"}\n' $((s / 60)) $((s % 60))

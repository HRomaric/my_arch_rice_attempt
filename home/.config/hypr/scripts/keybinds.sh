#!/usr/bin/env bash
# Keybind cheatsheet: lists every Hyprland bind that has a description, in rofi.
# Descriptions come from the { description = "..." } option in hyprland.lua.
pkill -x rofi && exit 0

hyprctl binds -j | jq -r '
  .[] | select(.has_description)
  | . as $b
  | ([ [64,"SUPER"],[4,"CTRL"],[8,"ALT"],[1,"SHIFT"] ]
      | map(select(($b.modmask / .[0] | floor) % 2 == 1) | .[1])) as $m
  | ($b.key
      | if . == "mouse:272" then "Left drag"
        elif . == "mouse:273" then "Right drag"
        elif . == "mouse_down" then "Scroll down"
        elif . == "mouse_up" then "Scroll up"
        elif . == "RETURN" then "Enter"
        elif startswith("XF86") then ltrimstr("XF86")
        else . end) as $k
  | "\(($m + [$k]) | join(" + "))\t\($b.description)"
' | awk -F'\t' '{ printf "%-28s  %s\n", $1, $2 }' \
  | rofi -dmenu -i -p "keybinds" -no-custom \
      -theme-str 'window { width: 720px; } element-text { font: "CaskaydiaCove Nerd Font Mono 11"; }' >/dev/null

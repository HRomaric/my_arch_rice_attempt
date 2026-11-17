#!/usr/bin/env bash
# Screen recorder toggle (wf-recorder).
# First press: pick a mode in rofi, then a region/window/screen. Second press: stop and save.
# Recordings go to ~/Videos/Recordings; the path is copied to the clipboard.

dir=~/Videos/Recordings
mkdir -p "$dir"

# Already recording -> stop it (SIGINT lets wf-recorder finalize the file)
if pgrep -x wf-recorder >/dev/null; then
    pkill -INT -x wf-recorder
    exit 0
fi

choice=$(printf '%s\n' \
    "󰩭  Region / window" \
    "󰩭  Region / window + audio" \
    "󰍹  Full screen" \
    "󰍹  Full screen + audio" \
    | rofi -dmenu -i -p "Record")
[ -z "$choice" ] && exit 0

args=()
case "$choice" in
    *Region*)
        # Window boxes of the visible workspaces: click a window, or drag a region
        ws=$(hyprctl monitors -j | jq -r '[.[].activeWorkspace.id] | join(",")')
        geom=$(hyprctl clients -j \
            | jq -r --arg ws "$ws" '($ws | split(",") | map(tonumber)) as $w
                | .[] | select(.workspace.id as $id | $w | index($id))
                | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' \
            | slurp -d) || exit 0
        args+=(-g "$geom")
        ;;
    *)
        args+=(-o "$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')")
        ;;
esac
# Desktop audio (what you hear), not the microphone
[[ "$choice" == *audio* ]] && args+=("--audio=$(pactl get-default-sink).monitor")

f="$dir/$(date +%F_%H-%M-%S).mp4"
(sleep 0.3; pkill -RTMIN+8 waybar) &
notify-send -t 2000 "Recording started" "Press the same shortcut again to stop"
wf-recorder "${args[@]}" -f "$f"
pkill -RTMIN+8 waybar
[ -s "$f" ] && {
    printf '%s' "$f" | wl-copy
    notify-send "Recording saved" "$f"
}

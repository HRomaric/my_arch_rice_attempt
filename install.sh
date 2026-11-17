#!/usr/bin/env bash
# Rice installer: Hyprland (Lua config) + Waybar + rofi + dunst + kitty + hyprlock/hypridle
# + awww/waypaper/matugen, zsh + oh-my-zsh + Powerlevel10k, GRUB (Sidonia) + Plymouth (black_hud) + Ly.
#
# Usage:  ./install.sh [--no-desktop] [--no-shell] [--no-boot] [--copy] [-y]
#   --no-desktop  skip Hyprland & friends (packages + configs)
#   --no-shell    skip zsh / oh-my-zsh / Powerlevel10k
#   --no-boot     skip GRUB theme, kernel params, Plymouth, Ly (no root changes to boot chain)
#   --copy        copy configs into ~/.config instead of symlinking them to this repo
#   -y            don't ask for confirmation
#
# Run as your normal user (NOT with sudo); it calls sudo itself when needed.
set -Eeuo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES

DO_DESKTOP=1 DO_SHELL=1 DO_BOOT=1 LINK_MODE=symlink ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --no-desktop) DO_DESKTOP=0 ;;
        --no-shell)   DO_SHELL=0 ;;
        --no-boot)    DO_BOOT=0 ;;
        --copy)       LINK_MODE=copy ;;
        -y|--yes)     ASSUME_YES=1 ;;
        -h|--help)    sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done
export DO_DESKTOP DO_SHELL DO_BOOT LINK_MODE ASSUME_YES

# shellcheck source=lib/common.sh
source "$DOTFILES/lib/common.sh"

[[ $EUID -ne 0 ]] || die "Run as your normal user, not root (sudo is used when needed)."

# ---- Distro detection -------------------------------------------------------
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
    *" arch "*)   DISTRO=arch ;;
    *" debian "*) DISTRO=debian ;;
    *) die "Unsupported distro: ${PRETTY_NAME:-unknown} (only Arch and Debian)." ;;
esac
export DISTRO
# shellcheck source=distro/arch.sh
source "$DOTFILES/distro/$DISTRO.sh"

GPU="$(detect_gpu)"; export GPU

info "Distro : ${PRETTY_NAME}"
info "GPU    : ${GPU}"
info "Steps  : desktop=$DO_DESKTOP shell=$DO_SHELL boot=$DO_BOOT (configs: $LINK_MODE)"
[[ $DISTRO == debian && $DO_DESKTOP == 1 ]] && \
    warn "Debian: Hyprland & co. are compiled from source. Expect 30-60 min and a C++26 compiler (g++ >= 15)."
confirm "Continue?" || exit 0

sudo -v
# keep sudo alive while we run
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &

LOG="$HOME/.cache/rice-install-$(date +%F_%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
info "Logging to $LOG"

distro_prepare                       # repos, AUR helper, base tools

if [[ $DO_DESKTOP == 1 ]]; then
    distro_install_desktop           # packages / source builds
    install_fonts
    install_gtk_theme
    deploy_configs
    setup_monitors
    generate_colors
fi

if [[ $DO_SHELL == 1 ]]; then
    distro_install_shell
    setup_shell
fi

if [[ $DO_BOOT == 1 ]]; then
    distro_install_boot              # grub/plymouth/ly packages or builds
    setup_plymouth_theme
    setup_ly
    distro_initramfs                 # early KMS + plymouth hook, regenerate initramfs
    setup_grub                       # kernel params + Sidonia theme + regenerate grub.cfg
    sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
fi

ok "All done. Log: $LOG"
[[ $DO_BOOT == 1 ]] && info "Reboot to get GRUB → Plymouth → Ly → Hyprland."
info "Wallpaper picker: SUPER+SHIFT+W (waypaper runs matugen to recolor everything)."
info "Monitors: run 'nwg-displays' once to write ~/.config/hypr/monitors.lua for this machine."

# shellcheck shell=bash
# Shared helpers + distro-independent steps. Sourced by install.sh.

# ---- Pinned upstream sources ------------------------------------------------
SIDONIA_REPO="https://github.com/Aleph1-9012/Sidonia.git"
SIDONIA_COMMIT="5b5725a7f41df8be85b1ef89a55175ffc612b6ff"
SIDONIA_THEME="${SIDONIA_THEME:-T1}"          # T1..T5
SIDONIA_PROFILE="${SIDONIA_PROFILE:-1080p}"   # 720p | 1080p | 1440p
PLYMOUTH_THEMES_REPO="https://github.com/adi1090x/plymouth-themes.git"
PLYMOUTH_THEME="black_hud"
NORDZY_REPO="https://github.com/MolassesLover/Nordzy-icon.git"
BIBATA_URL="https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Ice.tar.xz"
NERDFONTS_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

SRC_DIR="${SRC_DIR:-$HOME/.cache/rice-src}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# ---- Logging / prompts ------------------------------------------------------
if [[ -t 1 ]]; then C_B=$'\e[1;34m' C_G=$'\e[1;32m' C_Y=$'\e[1;33m' C_R=$'\e[1;31m' C_0=$'\e[0m'
else C_B='' C_G='' C_Y='' C_R='' C_0=''; fi
info() { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s ✓ %s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s !! %s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%s xx %s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
confirm() {
    [[ ${ASSUME_YES:-0} == 1 ]] && return 0
    local a; read -r -p "$1 [Y/n] " a; [[ -z $a || $a =~ ^[Yy] ]]
}
have() { command -v "$1" >/dev/null 2>&1; }
trap 'warn "Failed at line $LINENO: $BASH_COMMAND"' ERR

# Clone (or update) a git repo at a given ref into $SRC_DIR/<name>. Echoes the path.
git_fetch() {   # git_fetch <url> <name> [ref] [--recursive]
    local url=$1 name=$2 ref=${3:-} rec=${4:-} dir="$SRC_DIR/$2"
    mkdir -p "$SRC_DIR"
    if [[ ! -d $dir/.git ]]; then
        git clone ${rec:+--recursive} "$url" "$dir" >&2
    else
        git -C "$dir" fetch --tags --force origin >&2
    fi
    if [[ -n $ref ]]; then
        git -C "$dir" checkout --force "$ref" >&2
        [[ -n $rec ]] && git -C "$dir" submodule update --init --recursive >&2
    else
        git -C "$dir" pull --ff-only >&2 || true
    fi
    printf '%s\n' "$dir"
}

# ---- Hardware ----------------------------------------------------------------
# Prints the kernel DRM modules to load early (e.g. "i915", "amdgpu", "i915 nvidia ...").
detect_gpu() {
    local mods=() d drv vendor
    for d in /sys/class/drm/card[0-9]*/device; do
        [[ -e $d ]] || continue
        drv=""; [[ -L $d/driver ]] && drv=$(basename "$(readlink -f "$d/driver")")
        vendor=$(cat "$d/vendor" 2>/dev/null || true)
        case "$drv" in
            i915|xe|amdgpu|radeon|nouveau) mods+=("$drv") ;;
            nvidia) mods+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm) ;;
            "") case "$vendor" in
                    0x8086) mods+=(i915) ;;
                    0x1002) mods+=(amdgpu) ;;
                    0x10de) warn "NVIDIA GPU without a loaded driver: install the driver first for early KMS." ;;
                esac ;;
        esac
    done
    # de-duplicate, keep order
    printf '%s\n' "${mods[@]:-}" | awk 'NF && !seen[$0]++' | xargs
}
has_nvidia() { [[ " $GPU " == *" nvidia_drm "* ]]; }

# ---- Config deployment -------------------------------------------------------
# link_item <repo path> <target path>: symlink (or copy) with a timestamped backup.
link_item() {
    local src=$1 dst=$2
    mkdir -p "$(dirname "$dst")"
    if [[ -L $dst && $(readlink -f "$dst") == "$(readlink -f "$src")" ]]; then
        return 0
    fi
    if [[ -e $dst || -L $dst ]]; then
        mv "$dst" "$dst.bak-rice-$STAMP"
        info "Backed up $dst → $dst.bak-rice-$STAMP"
    fi
    if [[ $LINK_MODE == copy ]]; then cp -a "$src" "$dst"; else ln -s "$src" "$dst"; fi
}

deploy_configs() {
    info "Deploying configs ($LINK_MODE)"
    local d
    for d in "$DOTFILES"/home/.config/*/; do
        d=${d%/}; link_item "$d" "$HOME/.config/$(basename "$d")"
    done
    link_item "$DOTFILES/home/.gtkrc-2.0" "$HOME/.gtkrc-2.0"
    link_item "$DOTFILES/home/.icons/default" "$HOME/.icons/default"
    chmod +x "$HOME"/.config/hypr/scripts/*.sh
    mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Videos/Recordings"
    # GTK4 apps follow the same prefs
    mkdir -p "$HOME/.config/gtk-4.0"
    [[ -e $HOME/.config/gtk-4.0/settings.ini ]] || cp "$DOTFILES/home/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
    have gsettings && {
        gsettings set org.gnome.desktop.interface gtk-theme 'Nordic-Blue' || true
        gsettings set org.gnome.desktop.interface icon-theme 'Nordzy' || true
        gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice' || true
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    } 2>/dev/null
    ok "Configs deployed"
}

# monitors.lua is per-machine (gitignored). Hyprland.lua already has a generic
# `preferred/auto` fallback, so a stub is enough until nwg-displays writes the real one.
setup_monitors() {
    local f="$HOME/.config/hypr/monitors.lua"
    [[ -e $f ]] && { info "Keeping existing $f"; return; }
    cat > "$f" <<'EOF'
-- Per-machine monitor layout (not tracked in git).
-- Generic for now: every output uses its preferred mode, placed automatically
-- (see the fallback rule in hyprland.lua). Run `nwg-displays` to generate a real layout.
--
-- Example:
-- hl.monitor({ output = "eDP-1", mode = "1920x1080@60.0", position = "0x0", scale = 1.0 })
EOF
    ok "Wrote generic $f"
}

# Run matugen on the default wallpaper; fall back to the committed palette.
generate_colors() {
    local wp
    wp=$(awk -F' = ' '/^wallpaper =/{print $2}' "$HOME/.config/waypaper/config.ini" 2>/dev/null)
    wp=${wp/#\~/$HOME}
    [[ -f $wp ]] || wp=$(find "$HOME/.config/hypr/wallpapers" -maxdepth 1 -type f ! -name 'porsche-lock*' | head -n1)
    if have matugen && [[ -f $wp ]] && matugen image --prefer saturation "$wp" >/dev/null 2>&1; then
        ok "matugen colors generated from $(basename "$wp")"
    else
        warn "matugen run failed, using the committed fallback palette"
    fi
    local pair src dst
    for pair in hypr/colors.lua waybar/colors.css kitty/colors.conf rofi/colors.rasi dunst/50-matugen.conf; do
        src="$DOTFILES/fallback-colors/$pair"
        case $pair in dunst/*) dst="$HOME/.config/dunst/dunstrc.d/50-matugen.conf" ;; *) dst="$HOME/.config/$pair" ;; esac
        mkdir -p "$(dirname "$dst")"
        [[ -s $dst ]] || cp "$src" "$dst"
    done
}

# ---- Fonts / themes (same on both distros; only fetched if missing) -----------
install_fonts() {
    local fontdir="$HOME/.local/share/fonts" got=0 name file
    mkdir -p "$fontdir"
    for pair in "CaskaydiaCove Nerd Font:CascadiaCode" "JetBrainsMono Nerd Font:JetBrainsMono" "MesloLGS Nerd Font:Meslo"; do
        name=${pair%%:*} file=${pair##*:}
        if fc-list | grep -qi "$name"; then continue; fi
        info "Downloading Nerd Font: $file"
        mkdir -p "$fontdir/$file"
        curl -fsSL "$NERDFONTS_URL/$file.tar.xz" | tar -xJ -C "$fontdir/$file"
        got=1
    done
    [[ $got == 1 ]] && fc-cache -f >/dev/null
    ok "Fonts OK"
}

install_gtk_theme() {
    local themes="$HOME/.local/share/themes" icons="$HOME/.local/share/icons"
    mkdir -p "$themes" "$icons"
    if [[ ! -d $themes/Nordic-Blue ]]; then
        tar -xzf "$DOTFILES/assets/themes/Nordic-Blue.tar.gz" -C "$themes"
        ok "GTK theme Nordic-Blue installed"
    fi
    if [[ ! -d $icons/Nordzy && ! -d /usr/share/icons/Nordzy ]]; then
        info "Installing Nordzy icons"
        local d; d=$(git_fetch "$NORDZY_REPO" Nordzy-icon)
        (cd "$d" && ./install.sh -d "$icons") || warn "Nordzy install failed (icons will fall back)"
    fi
    if [[ ! -d $icons/Bibata-Modern-Ice && ! -d /usr/share/icons/Bibata-Modern-Ice ]]; then
        info "Installing Bibata-Modern-Ice cursor"
        curl -fsSL "$BIBATA_URL" | tar -xJ -C "$icons" || warn "Bibata download failed"
    fi
    ok "Themes OK"
}

# ---- Shell -------------------------------------------------------------------
setup_shell() {
    if [[ ! -d $HOME/.oh-my-zsh ]]; then
        info "Installing oh-my-zsh"
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
            "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    [[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]] \
        || warn "Powerlevel10k not found in /usr/share/zsh-theme-powerlevel10k"
    link_item "$DOTFILES/home/.zshrc"    "$HOME/.zshrc"
    link_item "$DOTFILES/home/.p10k.zsh" "$HOME/.p10k.zsh"
    if [[ $(getent passwd "$USER" | cut -d: -f7) != */zsh ]]; then
        sudo chsh -s "$(command -v zsh)" "$USER" && ok "Login shell set to zsh"
    fi
    ok "Shell OK"
}

# ---- Boot chain (distro hooks: grub_set, grub_regen) ---------------------------
setup_plymouth_theme() {
    local dst="/usr/share/plymouth/themes/$PLYMOUTH_THEME"
    if [[ ! -d $dst ]]; then
        info "Fetching Plymouth theme $PLYMOUTH_THEME"
        local d src; d=$(git_fetch "$PLYMOUTH_THEMES_REPO" plymouth-themes)
        src=$(find "$d" -mindepth 2 -maxdepth 3 -type d -name "$PLYMOUTH_THEME" | head -n1)
        [[ -n $src ]] || die "Theme $PLYMOUTH_THEME not found in $PLYMOUTH_THEMES_REPO"
        sudo cp -r "$src" "$dst"
    fi
    sudo install -d /etc/plymouth
    [[ -f /etc/plymouth/plymouthd.conf ]] && sudo cp /etc/plymouth/plymouthd.conf "/etc/plymouth/plymouthd.conf.bak-rice-$STAMP"
    printf '[Daemon]\nTheme=%s\nShowDelay=0\n' "$PLYMOUTH_THEME" | sudo tee /etc/plymouth/plymouthd.conf >/dev/null
    ok "Plymouth theme set to $PLYMOUTH_THEME (initramfs rebuilt later)"
}

setup_ly() {
    have ly || [[ -x /usr/bin/ly || -x /usr/local/bin/ly ]] || die "Ly is not installed"
    sudo install -d /etc/ly
    [[ -f /etc/ly/config.ini ]] && sudo cp /etc/ly/config.ini "/etc/ly/config.ini.bak-rice-$STAMP"
    sudo install -m644 "$DOTFILES/system/ly/config.ini"   /etc/ly/config.ini
    sudo install -m644 "$DOTFILES/system/ly/blackhole.dur" /etc/ly/blackhole.dur
    # brightnessctl may live elsewhere; fix the absolute paths in the config
    local bc; bc=$(command -v brightnessctl || echo /usr/bin/brightnessctl)
    sudo sed -i "s#/usr/bin/brightnessctl#$bc#g" /etc/ly/config.ini

    # Disable any other display manager
    local dm
    for dm in sddm gdm gdm3 lightdm lxdm greetd; do
        systemctl is-enabled "$dm.service" >/dev/null 2>&1 && { sudo systemctl disable "$dm.service"; info "Disabled $dm"; }
    done
    sudo rm -f /etc/systemd/system/display-manager.service

    if systemctl cat ly@.service >/dev/null 2>&1; then
        sudo install -d /etc/systemd/system/ly@tty2.service.d
        sudo install -m644 "$DOTFILES/system/systemd/ly@tty2.service.d/fast-start.conf" \
            /etc/systemd/system/ly@tty2.service.d/fast-start.conf
        sudo systemctl daemon-reload
        sudo systemctl disable getty@tty2.service 2>/dev/null || true
        sudo systemctl enable ly@tty2.service
        ok "Ly enabled on tty2"
    else
        sudo systemctl daemon-reload
        sudo systemctl disable getty@tty2.service 2>/dev/null || true
        sudo systemctl enable ly.service
        ok "Ly enabled (ly.service)"
    fi
}

setup_grub() {
    if ! have grub-mkconfig || [[ ! -d /boot/grub ]]; then
        warn "GRUB not found (systemd-boot/other?). Skipping GRUB theme and kernel params."
        return
    fi
    # Current cmdline (after Debian drop-ins too), then add ours if missing
    local cur p want
    cur=$(bash -c 'source /etc/default/grub >/dev/null 2>&1; for f in /etc/default/grub.d/*.cfg; do [[ -e $f ]] && source "$f"; done; printf %s "$GRUB_CMDLINE_LINUX_DEFAULT"')
    want="quiet splash loglevel=3 vt.global_cursor_default=0 fbcon=nodefer plymouth.use-simpledrm"
    has_nvidia && want+=" nvidia_drm.modeset=1"
    for p in $want; do [[ " $cur " == *" ${p%%=*}"[=\ ]* || " $cur " == *" $p "* ]] || cur+=" $p"; done
    cur=$(xargs <<<"$cur")

    grub_set GRUB_CMDLINE_LINUX_DEFAULT "\"$cur\""
    grub_set GRUB_TIMEOUT 2
    grub_set GRUB_TIMEOUT_STYLE menu
    grub_set GRUB_GFXPAYLOAD_LINUX keep
    distro_grub_extra

    info "Installing GRUB theme Sidonia $SIDONIA_THEME-$SIDONIA_PROFILE"
    local d; d=$(git_fetch "$SIDONIA_REPO" Sidonia "$SIDONIA_COMMIT")
    (cd "$d" && sudo ./install.sh "$SIDONIA_THEME" "$SIDONIA_PROFILE") || warn "Sidonia installer failed"
    grub_regen
    ok "GRUB configured"
}

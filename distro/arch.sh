# shellcheck shell=bash
# Arch Linux specifics. Sourced by install.sh after lib/common.sh.

PAC=(sudo pacman -S --needed --noconfirm)

aur() {   # install AUR packages with yay (bootstrapped if missing)
    have yay || have paru || {
        info "Bootstrapping yay-bin"
        local d="$SRC_DIR/yay-bin"
        rm -rf "$d"; git clone https://aur.archlinux.org/yay-bin.git "$d"
        (cd "$d" && makepkg -si --noconfirm)
    }
    if have yay; then yay -S --needed --noconfirm "$@"; else paru -S --needed --noconfirm "$@"; fi
}

distro_prepare() {
    info "Updating system"
    sudo pacman -Syu --noconfirm
    "${PAC[@]}" base-devel git curl wget unzip xz tar fontconfig
}

distro_install_desktop() {
    info "Installing desktop packages"
    local pkgs=(
        # compositor & hypr ecosystem
        hyprland hyprlock hypridle hyprpicker hyprpolkitagent hyprsunset
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk uwsm
        # bar / launcher / notifications / terminal
        waybar rofi rofi-calc dunst libnotify kitty
        # wallpaper + theming
        awww matugen imagemagick
        # utilities used by binds & waybar
        grim slurp wl-clipboard cliphist wl-clip-persist wf-recorder jq
        brightnessctl playerctl pavucontrol network-manager-applet blueman
        htop btop fastfetch power-profiles-daemon
        pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber gst-plugin-pipewire
        # look & feel
        nwg-look nwg-displays qt6ct kvantum
        ttf-cascadia-code-nerd ttf-jetbrains-mono-nerd ttf-meslo-nerd noto-fonts noto-fonts-emoji cantarell-fonts
        # default apps from hyprland.lua (edit to taste)
        dolphin firefox
    )
    "${PAC[@]}" "${pkgs[@]}"
    aur waypaper wlogout
    sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
    ok "Desktop packages installed"
}

distro_install_shell() {
    "${PAC[@]}" zsh
    aur zsh-theme-powerlevel10k-git
}

distro_install_boot() {
    "${PAC[@]}" grub plymouth ly
    aur plymouth-theme-black-hud-git || warn "AUR theme failed, will fetch from git instead"
}

# Early KMS + plymouth hook in mkinitcpio, then rebuild.
distro_initramfs() {
    local conf=/etc/mkinitcpio.conf
    sudo cp "$conf" "$conf.bak-rice-$STAMP"
    if [[ -n $GPU ]]; then
        local m mods
        mods=$(sed -n 's/^MODULES=(\(.*\))/\1/p' "$conf")
        for m in $GPU; do [[ " $mods " == *" $m "* ]] || mods+=" $m"; done
        sudo sed -i "s/^MODULES=(.*)/MODULES=($(xargs <<<"$mods"))/" "$conf"
    fi
    if ! grep -qE '^HOOKS=\(.*\bplymouth\b' "$conf"; then
        # plymouth goes right after udev (or systemd if that's used)
        if grep -qE '^HOOKS=\(.*\bsystemd\b' "$conf"; then
            sudo sed -i -E '/^HOOKS=/ s/\bsystemd\b/systemd plymouth/' "$conf"
        else
            sudo sed -i -E '/^HOOKS=/ s/\budev\b/udev plymouth/' "$conf"
        fi
    fi
    grep -qE '^HOOKS=\(.*\bkms\b' "$conf" || warn "No 'kms' hook in $conf: add it for early KMS."
    info "$(grep -E '^(MODULES|HOOKS)=' "$conf" | tr '\n' ' ')"
    sudo mkinitcpio -P
    ok "initramfs rebuilt"
}

# Arch has no /etc/default/grub.d: edit /etc/default/grub in place (backed up once).
grub_set() {   # grub_set KEY VALUE   (VALUE already quoted if needed)
    local f=/etc/default/grub
    [[ -f $f.bak-rice-$STAMP ]] || sudo cp "$f" "$f.bak-rice-$STAMP"
    if grep -qE "^#?\s*$1=" "$f"; then
        sudo sed -i -E "s|^#?\s*$1=.*|$1=$2|" "$f"
    else
        echo "$1=$2" | sudo tee -a "$f" >/dev/null
    fi
}
distro_grub_extra() {
    # microcode is already embedded by the mkinitcpio 'microcode' hook
    grep -qE '^HOOKS=\(.*\bmicrocode\b' /etc/mkinitcpio.conf && grub_set GRUB_EARLY_INITRD_LINUX_STOCK '""'
    return 0
}
grub_regen() { sudo grub-mkconfig -o /boot/grub/grub.cfg; }

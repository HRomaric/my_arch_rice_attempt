# shellcheck shell=bash
# Debian (13 "trixie" or newer) specifics. Sourced by install.sh after lib/common.sh.
#
# Debian doesn't ship a Hyprland with the Lua config (>= 0.56), so the whole hypr stack is
# built from source into /usr/local, pinned to the versions running on the Arch machine.
# Override any pin with an env var, e.g.  HYPRLAND_TAG=v0.58.0 ./install.sh

: "${HYPRWAYLAND_SCANNER_TAG:=v0.4.6}"
: "${HYPRUTILS_TAG:=v0.14.3}"
: "${HYPRLANG_TAG:=v0.6.8}"
: "${HYPRCURSOR_TAG:=v0.1.14}"
: "${HYPRGRAPHICS_TAG:=v0.6.0}"
: "${HYPRWIRE_TAG:=v0.3.1}"
: "${AQUAMARINE_TAG:=v0.16.0}"
: "${HYPRLAND_PROTOCOLS_TAG:=}"          # empty = latest
: "${HYPRLAND_TAG:=v0.57.2}"
: "${HYPRLOCK_TAG:=v0.9.7}"
: "${HYPRIDLE_TAG:=v0.1.8}"
: "${HYPRPICKER_TAG:=v0.4.8}"
: "${HYPRLAND_QT_SUPPORT_TAG:=v0.1.0}"
: "${HYPRPOLKITAGENT_TAG:=v0.2.0}"
: "${XDPH_TAG:=v1.5.0}"
: "${AWWW_TAG:=v0.12.1}"
: "${MATUGEN_VERSION:=4.2.0}"
: "${ROFI_TAG:=2.0.0}"
: "${LY_TAG:=v1.4.1}"

export DEBIAN_FRONTEND=noninteractive
export CMAKE_PREFIX_PATH=/usr/local
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/$(uname -m)-linux-gnu/pkgconfig:/usr/local/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PATH="/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
JOBS=$(nproc)

# Install the packages that exist in the configured repos; warn about the others
apt_try() {
    local p ok=() miss=()
    for p in "$@"; do
        if apt-cache show "$p" >/dev/null 2>&1; then ok+=("$p"); else miss+=("$p"); fi
    done
    ((${#miss[@]})) && warn "Not in apt, skipped: ${miss[*]}"
    ((${#ok[@]})) && sudo apt-get install -y --no-install-recommends "${ok[@]}"
    return 0
}
apt_has_version() {   # apt_has_version <pkg> <min>  → candidate >= min ?
    local v; v=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')
    [[ -n $v && $v != "(none)" ]] && dpkg --compare-versions "$v" ge "$2"
}

# checkout a tag, accepting both "vX.Y.Z" and "X.Y.Z"
checkout_tag() {   # checkout_tag <dir> <tag>
    [[ -z $2 ]] && return 0
    git -C "$1" checkout --force "$2" 2>/dev/null \
        || git -C "$1" checkout --force "${2#v}" 2>/dev/null \
        || git -C "$1" checkout --force "v$2" \
        || die "Tag $2 not found in $1"
    git -C "$1" submodule update --init --recursive >&2
}

built() { [[ -f "$SRC_DIR/.built-$1-$2" ]]; }
mark_built() { touch "$SRC_DIR/.built-$1-$2"; }

build_cmake() {   # build_cmake <name> <git url> <tag> [cmake args...]
    local name=$1 url=$2 tag=$3; shift 3
    built "$name" "$tag" && { info "$name $tag already built"; return; }
    info "Building $name $tag"
    local d; d=$(git_fetch "$url" "$name" "" --recursive); checkout_tag "$d" "$tag"
    rm -rf "$d/build"
    cmake -S "$d" -B "$d/build" -G Ninja --no-warn-unused-cli \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib "$@" \
        && cmake --build "$d/build" -j"$JOBS" \
        && sudo cmake --install "$d/build" \
        || { warn "$name build failed"; return 1; }
    sudo ldconfig
    mark_built "$name" "$tag"; ok "$name $tag installed"
}

build_meson() {   # build_meson <name> <git url> <tag> [meson args...]
    local name=$1 url=$2 tag=$3; shift 3
    built "$name" "${tag:-head}" && { info "$name already built"; return; }
    info "Building $name ${tag:-latest}"
    local d; d=$(git_fetch "$url" "$name" "" --recursive)
    if [[ -n $tag ]]; then checkout_tag "$d" "$tag"
    else checkout_tag "$d" "$(git -C "$d" describe --tags "$(git -C "$d" rev-list --tags --max-count=1)")"; fi
    rm -rf "$d/build"
    meson setup "$d/build" "$d" --prefix=/usr/local --libdir=lib --buildtype=release "$@" \
        && ninja -C "$d/build" \
        && sudo ninja -C "$d/build" install \
        || { warn "$name build failed"; return 1; }
    sudo ldconfig
    mark_built "$name" "${tag:-head}"; ok "$name installed"
}

# Hyprland needs C++26 (g++ >= 15). Use g++-15 from the repos if the default is older.
ensure_cxx26() {
    local v; v=$(g++ -dumpversion 2>/dev/null | cut -d. -f1)
    [[ ${v:-0} -ge 15 ]] && return 0
    if apt-cache show g++-15 >/dev/null 2>&1; then
        sudo apt-get install -y g++-15 gcc-15
        export CC=gcc-15 CXX=g++-15
        ok "Using g++-15 for the Hyprland build"
    else
        die "g++ ${v:-?} is too old for Hyprland ${HYPRLAND_TAG} (needs C++26 / g++ >= 15) and g++-15 isn't available.
    Options: enable trixie-backports or move to Debian testing (forky), then re-run;
    or re-run with --no-desktop to install only the shell + boot parts."
    fi
}

ensure_rust() {
    if ! have cargo || ! have rustup; then
        info "Installing Rust (rustup, user-local)"
        curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
    fi
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
    rustup update stable >/dev/null
}

# ------------------------------------------------------------------------------
distro_prepare() {
    info "Updating apt"
    sudo apt-get update
    sudo apt-get -y upgrade
    sudo apt-get install -y build-essential git curl wget ca-certificates unzip xz-utils tar \
        fontconfig cmake meson ninja-build pkg-config gettext python3 pipx
}

hypr_build_deps() {
    apt_try \
        libwayland-dev libwayland-bin wayland-protocols libxkbcommon-dev libxkbcommon-x11-dev \
        libegl-dev libgles-dev libegl1-mesa-dev libgbm-dev libdrm-dev mesa-common-dev \
        libinput-dev libudev-dev libseat-dev libdisplay-info-dev libliftoff-dev hwdata \
        libpixman-1-dev libcairo2-dev libpango1.0-dev libglib2.0-dev libffi-dev \
        libpugixml-dev libtomlplusplus-dev libzip-dev librsvg2-dev libjxl-dev libwebp-dev \
        libjpeg-dev libspng-dev libpng-dev libmagic-dev libheif-dev \
        libmuparser-dev libre2-dev libsdbus-c++-dev libsystemd-dev libglaze-dev \
        libxcb1-dev libxcb-composite0-dev libxcb-xfixes0-dev libxcb-icccm4-dev libxcb-res0-dev \
        libxcb-ewmh-dev libxcb-render-util0-dev libxcb-errors-dev libxcb-util-dev libxcb-xinput-dev \
        libxcb-image0-dev libxcb-keysyms1-dev libxcb-randr0-dev libxcb-xkb-dev libxcb-cursor-dev \
        libxcursor-dev libx11-xcb-dev xwayland \
        glslang-dev glslang-tools libei-dev libcanberra-dev liblcms2-dev uuid-dev libreadline-dev \
        liblua5.4-dev lua5.4 libpam0g-dev \
        qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-wayland-dev libpolkit-qt6-1-dev \
        qml6-module-qtquick-controls qml6-module-qtquick-layouts
}

build_hypr_stack() {
    ensure_cxx26
    local gh=https://github.com/hyprwm
    build_cmake hyprwayland-scanner "$gh/hyprwayland-scanner.git" "$HYPRWAYLAND_SCANNER_TAG"
    build_cmake hyprutils           "$gh/hyprutils.git"           "$HYPRUTILS_TAG"
    build_cmake hyprlang            "$gh/hyprlang.git"            "$HYPRLANG_TAG"
    build_cmake hyprcursor          "$gh/hyprcursor.git"          "$HYPRCURSOR_TAG"
    build_cmake hyprgraphics        "$gh/hyprgraphics.git"        "$HYPRGRAPHICS_TAG"
    build_cmake hyprwire            "$gh/hyprwire.git"            "$HYPRWIRE_TAG"
    build_cmake aquamarine          "$gh/aquamarine.git"          "$AQUAMARINE_TAG"
    build_meson hyprland-protocols  "$gh/hyprland-protocols.git"  "$HYPRLAND_PROTOCOLS_TAG"
    build_cmake Hyprland            "$gh/Hyprland.git"            "$HYPRLAND_TAG" \
        || die "Hyprland build failed – see the log above"
    build_cmake hyprlock            "$gh/hyprlock.git"            "$HYPRLOCK_TAG"
    build_cmake hypridle            "$gh/hypridle.git"            "$HYPRIDLE_TAG"
    build_cmake hyprpicker          "$gh/hyprpicker.git"          "$HYPRPICKER_TAG"
    build_cmake hyprland-qt-support "$gh/hyprland-qt-support.git" "$HYPRLAND_QT_SUPPORT_TAG" \
        -DINSTALL_QML_PREFIX=/lib/qt6/qml || warn "hyprland-qt-support failed"
    build_cmake hyprpolkitagent     "$gh/hyprpolkitagent.git"     "$HYPRPOLKITAGENT_TAG" \
        || { warn "hyprpolkitagent failed, installing polkit-kde-agent-1 instead"; apt_try polkit-kde-agent-1; }

    # Ly / other DMs only look in /usr/share/wayland-sessions
    local s
    for s in /usr/local/share/wayland-sessions/*.desktop; do
        [[ -e $s ]] && sudo install -Dm644 "$s" "/usr/share/wayland-sessions/$(basename "$s")"
    done
    # hyprlock needs a PAM service
    [[ -f /etc/pam.d/hyprlock ]] || printf 'auth include login\n' | sudo tee /etc/pam.d/hyprlock >/dev/null
}

build_rofi() {
    if apt_has_version rofi 2.0; then apt_try rofi rofi-calc; return; fi
    apt_try flex bison libstartup-notification0-dev libxcb-xrm-dev libxcb-xinerama0-dev \
        libgdk-pixbuf-2.0-dev libqalculate-dev qalc check
    build_meson rofi https://github.com/davatorium/rofi.git "$ROFI_TAG"
    build_meson rofi-calc https://github.com/svenstaro/rofi-calc.git "" || warn "rofi-calc failed"
}

build_awww() {
    built awww "$AWWW_TAG" && return
    ensure_rust
    apt_try liblz4-dev
    local d; d=$(git_fetch https://codeberg.org/LGFae/awww.git awww); checkout_tag "$d" "$AWWW_TAG"
    (cd "$d" && cargo build --release)
    sudo install -m755 "$d/target/release/awww" "$d/target/release/awww-daemon" /usr/local/bin/
    mark_built awww "$AWWW_TAG"; ok "awww installed"
}

build_matugen() {
    have matugen && matugen --version 2>/dev/null | grep -q "$MATUGEN_VERSION" && return
    ensure_rust
    cargo install --locked matugen --version "$MATUGEN_VERSION" || cargo install --locked matugen
    sudo install -m755 "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen
    ok "matugen installed"
}

install_waypaper() {
    apt_try python3-gi gir1.2-gtk-3.0 python3-imageio python3-platformdirs python3-screeninfo
    pipx install --system-site-packages --force waypaper
    sudo ln -sf "$HOME/.local/bin/waypaper" /usr/local/bin/waypaper
    ok "waypaper installed"
}

distro_install_desktop() {
    info "Installing desktop runtime packages"
    apt_try \
        waybar dunst libnotify-bin kitty \
        grim slurp wl-clipboard cliphist wf-recorder jq imagemagick \
        brightnessctl playerctl pavucontrol network-manager-gnome blueman \
        htop btop fastfetch power-profiles-daemon \
        pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber gstreamer1.0-pipewire \
        xdg-desktop-portal-gtk xdg-desktop-portal-wlr wlogout \
        nwg-look nwg-displays qt6ct qt-style-kvantum \
        fonts-noto fonts-noto-color-emoji fonts-cantarell \
        dolphin firefox-esr libgtk-3-bin
    info "Installing build dependencies"
    hypr_build_deps
    build_hypr_stack
    build_rofi
    build_awww
    build_matugen
    install_waypaper
    # Hyprland's own portal (screen sharing) – optional, needs extra Qt deps
    build_cmake xdg-desktop-portal-hyprland https://github.com/hyprwm/xdg-desktop-portal-hyprland.git "$XDPH_TAG" \
        || warn "xdg-desktop-portal-hyprland failed (screen sharing falls back to wlr portal)"
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
    ok "Desktop stack installed"
}

distro_install_shell() {
    apt_try zsh
    local p10k=/usr/share/zsh-theme-powerlevel10k
    if [[ ! -d $p10k ]]; then
        sudo git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k"
    else
        sudo git -C "$p10k" pull --ff-only || true
    fi
}

# Ly isn't packaged on Debian: build it with the Zig version it asks for.
build_ly() {
    built ly "$LY_TAG" && return
    apt_try libpam0g-dev libxcb-xkb-dev xauth
    local d zv arch zdir
    d=$(git_fetch https://codeberg.org/fairyglade/ly.git ly); checkout_tag "$d" "$LY_TAG"
    zv=$(sed -nE 's/.*minimum_zig_version *= *"([^"]+)".*/\1/p' "$d/build.zig.zon")
    [[ -n $zv ]] || die "Couldn't read minimum_zig_version from Ly's build.zig.zon"
    arch=$(uname -m)
    zdir="$SRC_DIR/zig-$zv"
    if [[ ! -x $zdir/zig ]]; then
        info "Downloading Zig $zv"
        mkdir -p "$zdir"
        curl -fsSL "https://ziglang.org/download/$zv/zig-$arch-linux-$zv.tar.xz" -o "$SRC_DIR/zig.tar.xz" \
          || curl -fsSL "https://ziglang.org/download/$zv/zig-linux-$arch-$zv.tar.xz" -o "$SRC_DIR/zig.tar.xz"
        tar -xJf "$SRC_DIR/zig.tar.xz" -C "$zdir" --strip-components=1
    fi
    (cd "$d" && "$zdir/zig" build -Doptimize=ReleaseSafe && sudo "$zdir/zig" build installexe -Doptimize=ReleaseSafe -Dinit_system=systemd)
    mark_built ly "$LY_TAG"; ok "Ly $LY_TAG installed"
}

distro_install_boot() {
    have grub-mkconfig || warn "GRUB isn't installed; the GRUB part will be skipped."
    apt_try plymouth plymouth-themes
    build_ly
}

distro_initramfs() {
    local f=/etc/initramfs-tools/modules m
    for m in $GPU; do grep -qxF "$m" "$f" || echo "$m" | sudo tee -a "$f" >/dev/null; done
    if has_nvidia; then
        echo 'options nvidia_drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia-kms.conf >/dev/null
    fi
    sudo plymouth-set-default-theme "$PLYMOUTH_THEME" || true
    sudo update-initramfs -u -k all
    ok "initramfs rebuilt"
}

# Debian supports drop-ins: keep /etc/default/grub untouched (except what Sidonia writes).
grub_set() {
    local f=/etc/default/grub.d/99-rice.cfg
    sudo install -d /etc/default/grub.d
    sudo touch "$f"
    sudo sed -i "/^$1=/d" "$f"
    echo "$1=$2" | sudo tee -a "$f" >/dev/null
}
distro_grub_extra() { return 0; }
grub_regen() { sudo update-grub; }

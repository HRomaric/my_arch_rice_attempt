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
: "${HYPRLAND_PROTOCOLS_TAG:=v0.8.0}"
# System libs that trixie ships too old for Hyprland >= 0.57; built into /usr/local only if needed
: "${WAYLAND_SCANNER_TAG:=1.25.0}"      # wayland-protocols 1.49's XML needs scanner >= 1.25
: "${WAYLAND_PROTOCOLS_TAG:=1.49}"
: "${XKBCOMMON_TAG:=xkbcommon-1.11.0}"
: "${LIBINPUT_TAG:=1.29.2}"
: "${LUA_VERSION:=5.5.1}"
: "${HYPRLAND_TAG:=v0.57.2}"
: "${HYPRLOCK_TAG:=v0.9.7}"
: "${HYPRIDLE_TAG:=v0.1.8}"
: "${HYPRPICKER_TAG:=v0.4.8}"
: "${HYPRLAND_QT_SUPPORT_TAG:=v0.1.0}"
: "${HYPRTOOLKIT_TAG:=v0.6.0}"         # GUI toolkit for hyprpolkitagent and XDPH's share picker
: "${HYPRPOLKITAGENT_TAG:=v0.2.0}"
: "${XDPH_TAG:=v1.5.0}"
: "${AWWW_TAG:=v0.12.1}"
: "${MATUGEN_VERSION:=4.2.0}"
: "${ROFI_TAG:=2.0.0}"
: "${LY_TAG:=v1.4.1}"
: "${GCC_VERSION:=15.2.0}"               # built from source if the repos lack g++ >= 15
: "${GCC_PREFIX:=/opt/gcc-15}"

export DEBIAN_FRONTEND=noninteractive
export CMAKE_PREFIX_PATH=/usr/local
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/$(uname -m)-linux-gnu/pkgconfig:/usr/local/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PATH="/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
JOBS=$(nproc)

# Exact-name check. (apt-cache show/policy treat the name as a regex, so "g++-15" would
# match e.g. "clang-15" and look available when it isn't.)
# No `grep -q`: it exits on the first match, apt-cache dies of SIGPIPE, and under
# `set -o pipefail` the whole check fails even though the package exists.
apt_exists() { apt-cache pkgnames "$1" 2>/dev/null | grep -xF -- "$1" >/dev/null; }

# Install the packages that exist in the configured repos; warn about the others
apt_try() {
    local p ok=() miss=()
    for p in "$@"; do
        if apt_exists "$p"; then ok+=("$p"); else miss+=("$p"); fi
    done
    ((${#miss[@]})) && warn "Not in apt, skipped: ${miss[*]}"
    ((${#ok[@]})) && sudo apt-get install -y --no-install-recommends "${ok[@]}"
    return 0
}
apt_has_version() {   # apt_has_version <pkg> <min>  → candidate >= min ?
    local v; v=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')
    [[ -n $v && $v != "(none)" ]] && dpkg --compare-versions "$v" ge "$2"
}
pc_ge() { pkg-config --atleast-version="$2" "$1" 2>/dev/null; }   # pc_ge <module> <min>

# checkout a tag, accepting both "vX.Y.Z" and "X.Y.Z"
checkout_tag() {   # checkout_tag <dir> <tag>
    [[ -z $2 ]] && return 0
    git -C "$1" checkout --force "$2" 2>/dev/null \
        || git -C "$1" checkout --force "${2#v}" 2>/dev/null \
        || git -C "$1" checkout --force "v$2" \
        || die "Tag $2 not found in $1"
    git -C "$1" submodule update --init --recursive >&2
}

# Apply distro/patches/<name>/*.patch after checkout (e.g. to build with GCC 15 where upstream
# already uses GCC 16 library features). A patch that no longer applies (pin bumped) is skipped.
apply_patches() {   # apply_patches <name> <src dir>
    local p
    for p in "$DOTFILES/distro/patches/$1"/*.patch; do
        [[ -f $p ]] || continue
        if git -C "$2" apply --check "$p" 2>/dev/null; then
            git -C "$2" apply "$p" && info "Applied patch $(basename "$p")"
        else
            warn "Patch $(basename "$p") doesn't apply to $1, skipped"
        fi
    done
}

built() { [[ -f "$SRC_DIR/.built-$1-$2" ]]; }
mark_built() { touch "$SRC_DIR/.built-$1-$2"; }

build_cmake() {   # build_cmake <name> <git url> <tag> [cmake args...]
    local name=$1 url=$2 tag=$3; shift 3
    built "$name" "$tag" && { info "$name $tag already built"; return; }
    info "Building $name $tag"
    local d; d=$(git_fetch "$url" "$name" "" --recursive); checkout_tag "$d" "$tag"
    apply_patches "$name" "$d"
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

# Build GCC from source into $GCC_PREFIX (trixie only ships g++ 14). Takes ~30-60 min.
build_gcc() {
    if [[ -x $GCC_PREFIX/bin/g++ ]] && "$GCC_PREFIX/bin/g++" -dumpversion | grep -qx "$GCC_VERSION"; then
        info "GCC $GCC_VERSION already in $GCC_PREFIX"; return 0
    fi
    info "Building GCC $GCC_VERSION into $GCC_PREFIX (one-time, ~30-60 min, ~8 GB temporary disk)"
    apt_try libgmp-dev libmpfr-dev libmpc-dev flex bison zlib1g-dev libzstd-dev
    local d="$SRC_DIR/gcc-$GCC_VERSION" tarball="$SRC_DIR/gcc-$GCC_VERSION.tar.xz"
    mkdir -p "$SRC_DIR"
    if [[ ! -d $d ]]; then
        curl -fL --retry 3 -o "$tarball" "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz" \
            || die "Failed to download GCC $GCC_VERSION"
        tar -xf "$tarball" -C "$SRC_DIR" && rm -f "$tarball"
    fi
    rm -rf "$d/build"; mkdir -p "$d/build"
    ( cd "$d/build" \
        && ../configure --prefix="$GCC_PREFIX" --program-suffix="-${GCC_VERSION%%.*}" \
            --enable-languages=c,c++ --disable-multilib --disable-bootstrap \
            --with-system-zlib --enable-default-pie --enable-linker-build-id \
        && make -j"$JOBS" \
        && sudo make install-strip ) || die "GCC $GCC_VERSION build failed – see the log above"
    # program-suffix gives gcc-15/g++-15; add plain names too
    sudo ln -sf "gcc-${GCC_VERSION%%.*}" "$GCC_PREFIX/bin/gcc"
    sudo ln -sf "g++-${GCC_VERSION%%.*}" "$GCC_PREFIX/bin/g++"
    rm -rf "$d"
    ok "GCC $GCC_VERSION installed in $GCC_PREFIX"
}

# Lua 5.5 (Hyprland's config language) isn't packaged on trixie. Upstream ships no shared
# lib or .pc file, so install a static -fPIC lib + headers under a versioned name (no
# /usr/local/bin/lua, so the system interpreter isn't shadowed) and write a .pc for it.
build_lua() {
    local mm=${LUA_VERSION%.*}
    pc_ge "lua$mm" "$LUA_VERSION" && { info "Lua $LUA_VERSION already installed"; return; }
    info "Building Lua $LUA_VERSION"
    local d="$SRC_DIR/lua-$LUA_VERSION"
    mkdir -p "$SRC_DIR"
    [[ -d $d ]] || curl -fsSL "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" | tar -xz -C "$SRC_DIR" \
        || die "Failed to download Lua $LUA_VERSION"
    make -C "$d" clean >/dev/null
    make -C "$d" linux MYCFLAGS=-fPIC || die "Lua $LUA_VERSION build failed"
    sudo install -Dm644 -t "/usr/local/include/lua$mm" \
        "$d"/src/{lua.h,luaconf.h,lualib.h,lauxlib.h,lua.hpp}
    sudo install -Dm644 "$d/src/liblua.a" "/usr/local/lib/liblua$mm.a"
    sudo install -d /usr/local/lib/pkgconfig
    sudo tee "/usr/local/lib/pkgconfig/lua$mm.pc" >/dev/null <<PC
prefix=/usr/local
libdir=\${prefix}/lib
includedir=\${prefix}/include/lua$mm

Name: Lua
Description: Lua $LUA_VERSION (static, built by the rice installer)
Version: $LUA_VERSION
Libs: -L\${libdir} -llua$mm -lm -ldl
Cflags: -I\${includedir}
PC
    ok "Lua $LUA_VERSION installed"
}

# Hyprland 0.57 wants newer wayland-protocols / xkbcommon / libinput than trixie has.
# They go to /usr/local (ahead of the system libs in ld.so.conf); sonames are unchanged, so
# everything else linked against the distro copies keeps working.
build_newer_system_libs() {
    # Only the scanner is built (-Dlibraries=false): trixie's libwayland 1.23 is new enough for
    # Hyprland, but its wayland-scanner rejects the "frozen" attribute used by wayland-protocols.
    if ! pc_ge wayland-protocols "$WAYLAND_PROTOCOLS_TAG"; then
        apt_try libexpat1-dev
        pc_ge wayland-scanner "$WAYLAND_SCANNER_TAG" \
            || build_meson wayland-scanner https://gitlab.freedesktop.org/wayland/wayland.git \
                "$WAYLAND_SCANNER_TAG" -Dlibraries=false -Dscanner=true -Dtests=false -Ddocumentation=false \
            || die "wayland-scanner build failed"
    fi
    pc_ge wayland-protocols "$WAYLAND_PROTOCOLS_TAG" \
        || build_meson wayland-protocols https://gitlab.freedesktop.org/wayland/wayland-protocols.git \
            "$WAYLAND_PROTOCOLS_TAG" -Dtests=false \
        || die "wayland-protocols build failed"
    pc_ge xkbcommon "${XKBCOMMON_TAG#xkbcommon-}" \
        || build_meson libxkbcommon https://github.com/xkbcommon/libxkbcommon.git "$XKBCOMMON_TAG" \
            -Denable-docs=false -Denable-bash-completion=false \
            -Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale \
        || die "libxkbcommon build failed"
    # udev-dir: keep the rules/helpers out of /usr/lib/udev so libinput-bin's files aren't clobbered
    pc_ge libinput "$LIBINPUT_TAG" \
        || build_meson libinput https://gitlab.freedesktop.org/libinput/libinput.git "$LIBINPUT_TAG" \
            -Ddocumentation=false -Dtests=false -Ddebug-gui=false -Dudev-dir=/usr/local/lib/udev \
        || die "libinput build failed"
    build_lua
}

# Hyprland needs C++26 (g++ >= 15). Use the distro g++ if new enough, else g++-15 from apt,
# else a locally built GCC in /opt. Binaries built with the local GCC get an RPATH to its
# libstdc++, so the system libstdc++6 stays untouched.
ensure_cxx26() {
    local v; v=$(g++ -dumpversion 2>/dev/null | cut -d. -f1)
    [[ ${v:-0} -ge 15 ]] && return 0
    if apt_exists g++-15 && apt_exists gcc-15; then
        sudo apt-get install -y g++-15 gcc-15
        export CC=gcc-15 CXX=g++-15
        ok "Using g++-15 from apt for the Hyprland build"
        return 0
    fi
    build_gcc
    export CC="$GCC_PREFIX/bin/gcc" CXX="$GCC_PREFIX/bin/g++"
    export LDFLAGS="-Wl,-rpath,$GCC_PREFIX/lib64${LDFLAGS:+ $LDFLAGS}"
    ok "Using $CXX ($("$CXX" -dumpversion)) for the Hyprland build"
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
        glslang-dev glslang-tools libei-dev libeis-dev libcanberra-dev liblcms2-dev uuid-dev libreadline-dev \
        liblua5.4-dev lua5.4 libpam0g-dev libiniparser-dev libabsl-dev \
        libpipewire-0.3-dev libspa-0.2-dev \
        bison libxml2-dev libmtdev-dev libevdev-dev libwacom-dev \
        qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-wayland-dev libpolkit-qt6-1-dev \
        qml6-module-qtquick-controls qml6-module-qtquick-layouts
}

build_hypr_stack() {
    ensure_cxx26
    build_newer_system_libs
    local gh=https://github.com/hyprwm
    build_cmake hyprwayland-scanner "$gh/hyprwayland-scanner.git" "$HYPRWAYLAND_SCANNER_TAG"
    build_cmake hyprutils           "$gh/hyprutils.git"           "$HYPRUTILS_TAG"
    build_cmake hyprlang            "$gh/hyprlang.git"            "$HYPRLANG_TAG"
    build_cmake hyprcursor          "$gh/hyprcursor.git"          "$HYPRCURSOR_TAG"
    build_cmake hyprgraphics        "$gh/hyprgraphics.git"        "$HYPRGRAPHICS_TAG"
    build_cmake hyprwire            "$gh/hyprwire.git"            "$HYPRWIRE_TAG"
    build_cmake aquamarine          "$gh/aquamarine.git"          "$AQUAMARINE_TAG"
    build_cmake hyprland-protocols  "$gh/hyprland-protocols.git"  "$HYPRLAND_PROTOCOLS_TAG"
    build_cmake Hyprland            "$gh/Hyprland.git"            "$HYPRLAND_TAG" \
        || die "Hyprland build failed – see the log above"
    build_cmake hyprlock            "$gh/hyprlock.git"            "$HYPRLOCK_TAG"
    build_cmake hypridle            "$gh/hypridle.git"            "$HYPRIDLE_TAG"
    build_cmake hyprpicker          "$gh/hyprpicker.git"          "$HYPRPICKER_TAG"
    build_cmake hyprland-qt-support "$gh/hyprland-qt-support.git" "$HYPRLAND_QT_SUPPORT_TAG" \
        -DINSTALL_QML_PREFIX=/lib/qt6/qml || warn "hyprland-qt-support failed"
    build_cmake hyprtoolkit         "$gh/hyprtoolkit.git"         "$HYPRTOOLKIT_TAG" -DBUILD_TESTING=OFF \
        || warn "hyprtoolkit failed (hyprpolkitagent and XDPH need it)"
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

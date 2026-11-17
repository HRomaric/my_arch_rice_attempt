# Debian 13 (trixie) install log — 2026-11-17

First full run of `./install.sh` on Debian 13 (AMD GPU, GRUB EFI), pinned to
Hyprland v0.57.2. GCC 15.2.0 was already built into `/opt/gcc-15` by an earlier run.
Each problem below stopped (or silently degraded) the install; all are fixed on `main`.

## Problems and fixes

| # | Symptom | Cause | Fix | Commit |
|---|---------|-------|-----|--------|
| 1 | `wayland-protocols build failed` — `No declaration for attribute frozen of element interface` in `color-management-v1.xml` | wayland-protocols 1.49 uses the `frozen` attribute, only known to wayland-scanner ≥ 1.25; trixie ships 1.23.1 and the build runs `--strict` | Build only the scanner from wayland 1.25.0 (`-Dlibraries=false`) into `/usr/local` before wayland-protocols. System libwayland 1.23.1 is kept (Hyprland needs ≥ 1.22.91) | `38d27ac` |
| 2 | Hyprland fails at `MiscFunctions.cpp`: `'starts_with' is not a member of 'std::ranges'`; then `S1.cpp`: `std::string has no member named 'subview'` | Hyprland 0.57.2 uses two C++ library features that only exist in GCC 16's libstdc++ | `distro/patches/Hyprland/0001-build-with-gcc-15.patch` replaces both with GCC 15 equivalents. New `apply_patches` step in `build_cmake` applies `distro/patches/<name>/*.patch` after checkout (skips with a warning if a patch no longer applies). A full `ninja -k 0` build confirmed these were the only two | `0db7c8c` |
| 3 | `hyprpolkitagent` and `xdg-desktop-portal-hyprland` fail: `hyprtoolkit not found` | hyprtoolkit was never built. Worse: the polkit-kde fallback is never started, because `hyprland.lua` only runs `systemctl --user start hyprpolkitagent`, so there was no polkit agent at all | Build hyprtoolkit v0.6.0 before them; add `libiniparser-dev`, `libabsl-dev`, `libpipewire-0.3-dev`, `libspa-0.2-dev`. All three build with GCC 15 unpatched | `16bc9a1` |
| 4 | Re-run dies at `pipx install --force waypaper`: pip tries to build PyGObject 3.58 from source (`Python dependency not found`) | `--force` on an existing venv force-reinstalls the deps too, so pip ignores Debian's `python3-gi` | Skip waypaper if pipx already has it; install without `--force` | `a3b5cf8` |
| 5 | `GRUB isn't installed` / `GRUB not found` although GRUB EFI is installed → no `splash`, so no Plymouth | `grub-mkconfig` is in `/usr/sbin`, which isn't on a normal user's PATH on Debian, so `command -v` failed | Append `/usr/local/sbin:/usr/sbin:/sbin` to the PATH set in `distro/debian.sh` | `158c01c` |

## Final state

Everything installed: wayland-scanner 1.25.0, wayland-protocols 1.49, libxkbcommon 1.11.0,
libinput 1.29.2, Lua 5.5.1, the hypr stack (Hyprland 0.57.2, hyprlock, hypridle, hyprpicker,
hyprland-qt-support, hyprtoolkit, hyprpolkitagent), xdg-desktop-portal-hyprland 1.5.0,
rofi 2.0.0 + rofi-calc, awww, matugen, waypaper, fonts/themes, zsh, Ly on tty2, Plymouth
(black_hud), and the Sidonia GRUB theme.

GRUB settings live in `/etc/default/grub.d/99-rice.cfg` (read after `/etc/default/grub`):
`quiet splash loglevel=3 vt.global_cursor_default=0 fbcon=nodefer plymouth.use-simpledrm`,
timeout 2 s, `GFXPAYLOAD_LINUX=keep`.

## Harmless output seen during the runs

- `Not in apt, skipped: libglaze-dev` — Hyprland fetches glaze itself via FetchContent.
- CMake `libxkbcommon.so.0 ... may be hidden by files in /usr/local/lib` — intended; the newer copy in `/usr/local` should win.
- `systemctl disable gdm` "unit files have no installation config" — gdm is still disabled.
- `os-prober will not be executed` — only matters with other OSes on the disk.

## Not yet verified (after reboot)

- `cat /proc/cmdline` contains `splash`; Plymouth → Ly → Hyprland boots.
- Run `nwg-displays` once to write a real `~/.config/hypr/monitors.lua` (currently generic).
- Polkit prompt appears (e.g. `pkexec true`); screen sharing works through the Hyprland portal.

## Notes for future pin bumps

- Patches in `distro/patches/<name>/` are version-specific; a bump that makes one fail to apply prints a warning and builds unpatched. Once the repos ship GCC ≥ 16 the Hyprland patch can be dropped.
- To test a source build without installing, build with `CMAKE_INSTALL_PREFIX` pointing at a scratch dir and unpack missing `-dev` debs there (`apt-get download` + `dpkg -x`, fixing `prefix=` in their `.pc` files).

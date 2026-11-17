# dotfiles: Hyprland rice (Arch + Debian)

Plain Hyprland (Lua config) · Waybar · rofi · dunst · kitty · hyprlock/hypridle ·
awww + waypaper + matugen (colors follow the wallpaper) · zsh + oh-my-zsh + Powerlevel10k ·
GRUB Sidonia T1 → Plymouth `black_hud` → Ly (blackhole animation).

## Install on a new machine

```bash
git clone git@github.com:HRomaric/my_arch_rice_attempt.git/dotfiles.git ~/dotfiles
cd ~/my_arch_rice_attempt
./install.sh            # as your normal user, it calls sudo itself
```

Options: `--no-desktop`, `--no-shell`, `--no-boot`, `--copy` (copy instead of symlink), `-y`.
A full log is written to `~/.cache/rice-install-*.log`.

| | Arch | Debian 13+ |
|---|---|---|
| Hyprland stack | pacman | **built from source** into `/usr/local`, pinned to the Arch versions (`HYPRLAND_TAG=…` to override). Needs g++ ≥ 15. |
| rofi 2 / awww / matugen / waypaper | pacman / AUR | source / cargo / pipx |
| Ly | pacman | built with the Zig version from Ly's `build.zig.zon` |
| initramfs | mkinitcpio (`plymouth` hook + GPU in `MODULES`) | initramfs-tools (`/etc/initramfs-tools/modules`) |
| GRUB settings | `/etc/default/grub` (backed up) | `/etc/default/grub.d/99-rice.cfg` |

Hardware-specific settings are detected, not copied:
- **GPU** (Intel / AMD / NVIDIA) via `/sys/class/drm` → early KMS modules (+ `nvidia_drm.modeset=1`).
- **Monitors**: a generic `~/.config/hypr/monitors.lua` is created (preferred mode, auto position).
  Run `nwg-displays` once to write the real layout. That file is gitignored.
- `/etc/fstab`, BIOS options and LVM layout are **not touched**.

Sidonia variant: `SIDONIA_THEME=T1 SIDONIA_PROFILE=1440p ./install.sh`.

## Layout

```
install.sh            entry point (detects distro via /etc/os-release)
lib/common.sh         shared steps: configs, fonts, themes, shell, Plymouth, Ly, GRUB
distro/arch.sh        pacman/AUR, mkinitcpio, /etc/default/grub
distro/debian.sh      apt + source builds, initramfs-tools, grub.d drop-in
home/                 symlinked into $HOME (~/.config/hypr, waybar, rofi, …)
system/               Ly config + blackhole.dur, ly@tty2 drop-in
fallback-colors/      palette used if matugen can't run at install time
assets/themes/        Nordic-Blue GTK theme
```

Configs are **symlinked**, so editing `~/.config/hypr/hyprland.lua` edits the repo: commit and push.
Change colors in `home/.config/matugen/templates/`, not in the generated `colors.*` files.

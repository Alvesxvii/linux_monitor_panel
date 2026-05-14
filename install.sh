#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user_config_dir="$HOME/.config"

mkdir -p "$user_config_dir/systemd/user" "$user_config_dir/autostart"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/backgrounds/lmpanel"

if [[ -d "$HOME/.local/share/backgrounds/kodachi" && ! -d "$HOME/.local/share/backgrounds/lmpanel" ]]; then
  mv "$HOME/.local/share/backgrounds/kodachi" "$HOME/.local/share/backgrounds/lmpanel"
fi

if [[ -d "$HOME/.local/lib/kodachi" && ! -d "$HOME/.local/lib/lmpanel" ]]; then
  mv "$HOME/.local/lib/kodachi" "$HOME/.local/lib/lmpanel"
fi

install -m 0644 "$repo_dir/deploy/systemd/user/lmpanel.service" \
  "$user_config_dir/systemd/user/lmpanel.service"
install -m 0644 "$repo_dir/deploy/autostart/lmpanel.desktop" \
  "$user_config_dir/autostart/lmpanel.desktop"
rm -f "$user_config_dir/systemd/user/kodachi-look.service" \
      "$user_config_dir/autostart/kodachi-look.desktop"
install -m 0755 "$repo_dir/deploy/bin/conky" "$HOME/.local/bin/conky"
install -m 0755 "$repo_dir/deploy/bin/lmpanel" "$HOME/.local/bin/lmpanel"

for wallpaper_dir in \
  "$repo_dir/assets/wallpaper" \
  "$repo_dir/usr/share/backgrounds/Kodachi"
do
  if [[ -d "$wallpaper_dir" ]]; then
    find "$wallpaper_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) -print0 |
      while IFS= read -r -d '' wallpaper_file; do
        install -m 0644 "$wallpaper_file" \
          "$HOME/.local/share/backgrounds/lmpanel/$(basename "$wallpaper_file")"
      done
  fi
done

if [[ ! -f "$HOME/.lmpanel/wallpaper-mode" ]]; then
  printf 'custom\n' >"$HOME/.lmpanel/wallpaper-mode"
fi

if [[ ! -f "$HOME/.lmpanel/wallpaper-choice" ]]; then
  printf '243811.png\n' >"$HOME/.lmpanel/wallpaper-choice"
fi

systemctl --user daemon-reload
systemctl --user enable --now lmpanel.service

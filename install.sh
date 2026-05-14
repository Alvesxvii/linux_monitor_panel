#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user_config_dir="$HOME/.config"

mkdir -p "$user_config_dir/systemd/user" "$user_config_dir/autostart"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/backgrounds/kodachi"

install -m 0644 "$repo_dir/deploy/systemd/user/kodachi-look.service" \
  "$user_config_dir/systemd/user/kodachi-look.service"
install -m 0644 "$repo_dir/deploy/autostart/kodachi-look.desktop" \
  "$user_config_dir/autostart/kodachi-look.desktop"
install -m 0755 "$repo_dir/deploy/bin/conky" "$HOME/.local/bin/conky"
install -m 0644 "$repo_dir/assets/wallpaper/243811.png" \
  "$HOME/.local/share/backgrounds/kodachi/243811.png"

systemctl --user daemon-reload
systemctl --user enable --now kodachi-look.service

# Overlay

This repository contains the Linux Monitor Panel desktop overlay setup stored in `~/.lmpanel`.

Tracked assets:
- `lmpanel.sh` orchestration script
- `*.conkyrc*` templates
- `conky_orange.lua`
- static wallpaper and icon assets
- desktop autostart and systemd user unit

Generated at runtime and intentionally ignored:
- `conky-runtime/`
- `lmpanel.log`
- `monitor-signature`
- status files such as `btcprice`, `xmrprice`, `netCurrentStatus`, and the `.eeds-*` files

Quick control:
- `systemctl --user restart lmpanel.service`
- `systemctl --user status lmpanel.service`
- `lmpanel edit`
- `lmpanel save`
- `lmpanel auto`

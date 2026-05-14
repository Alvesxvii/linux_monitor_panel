# Kodachi Overlay

This repository contains the desktop overlay setup extracted from the Kodachi look-and-feel rebuild.

Tracked assets:
- `kodachi-look.sh` orchestration script
- `*.conkyrc*` templates
- `conky_orange.lua`
- static wallpaper and icon assets
- desktop autostart and systemd user unit

Generated at runtime and intentionally ignored:
- `conky-runtime/`
- `kodachi-look.log`
- `monitor-signature`
- status files such as `btcprice`, `xmrprice`, `netCurrentStatus`, and the `.eeds-*` files

Quick control:
- `systemctl --user restart kodachi-look.service`
- `systemctl --user status kodachi-look.service`


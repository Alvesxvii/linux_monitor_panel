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
- `lmpanel set-auto`
- `lmpanel auto`
- `lmpanel profile 1|2|3`
- `lmpanel set-profile 1|2|3`
- `lmpanel save-profile`

Profiles:
- `profile 1|2|3` activates one of the saved layout profiles.
- `set-profile 1|2|3` enters edit mode for that profile.
- `save-profile` stores the edited positions back into the currently targeted profile.

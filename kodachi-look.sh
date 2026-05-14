#!/usr/bin/env bash
set -euo pipefail

BASE="$HOME/.kbase"
BG_DIR="$HOME/.local/share/backgrounds/kodachi"
WALLPAPER="$BG_DIR/243811.png"
LOG_FILE="$BASE/kodachi-look.log"
CONKY_BIN="$HOME/.local/bin/conky"
CONKY_LAYOUT_DIR="$BASE/conky-runtime"
MONITOR_SIG_FILE="$BASE/monitor-signature"
TEMPLATE_SIG_FILE="$BASE/template-signature"
CONKY_RENDERED_CONFIGS=()
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

mkdir -p "$BASE" "$BASE/dns" "$BG_DIR"

log() {
  printf '%s\n' "$*" >>"$LOG_FILE"
}

write_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$*" >"$path"
}

valid_ipv4() {
  [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

default_iface() {
  ip route show default 2>/dev/null | awk 'NR==1 {print $5; exit}'
}

default_gateway() {
  ip route show default 2>/dev/null | awk 'NR==1 {print $3; exit}'
}

connected_monitor_count() {
  if command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xrandr --query 2>/dev/null | awk '/ connected( primary)? / {count++} END {print count+0}'
  else
    printf '1\n'
  fi
}

monitor_signature() {
  if command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xrandr --query 2>/dev/null | awk '/ connected/ {print}' | sha256sum | awk '{print $1}'
  else
    printf 'no-xrandr\n'
  fi
}

template_signature() {
  sha256sum \
    "$BASE/.conkyrc0" \
    "$BASE/.conkyrc1" \
    "$BASE/.conkyrc2" \
    "$BASE/.conkyrc3" \
    "$BASE/.conkyrc4-head1" \
    "$BASE/.conkyrc0-head1" \
    "$BASE/.conkyrc1-head1" \
    "$BASE/.conkyrc2-head1" \
    "$BASE/.conkyrc3-head1" \
    "$BASE/conky_orange.lua" \
    2>/dev/null | sha256sum | awk '{print $1}'
}

monitor_specs() {
  if command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xrandr --query 2>/dev/null | awk '
      / connected/ {
        geom = ($3 == "primary" ? $4 : $3)
        n = split(geom, parts, /[x+]/)
        if (n >= 4) {
          print $1, parts[1], parts[2], parts[3], parts[4]
        }
      }'
  fi
}

calc_pct() {
  awk -v dim="$1" -v ratio="$2" 'BEGIN { printf "%d", (dim * ratio) + 0.5 }'
}

render_conky_config() {
  local src="$1"
  local dst="$2"
  local gap_x="$3"
  local gap_y="$4"
  local head="$5"
  local alignment="${6:-top_left}"

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  perl -0pi -e "s/^gap_x\\s+\\d+/gap_x $gap_x/m; s/^gap_y\\s+\\d+/gap_y $gap_y/m; s/^xinerama_head\\s+\\d+/xinerama_head $head/m; s/^alignment\\s+\\S+/alignment $alignment/m" "$dst"
}

build_conky_layouts() {
  local specs monitor_count idx name width height origin_x origin_y sig monitor_dir
  sig="$(monitor_signature)"
  monitor_count="$(connected_monitor_count)"
  local tmpl_sig
  tmpl_sig="$(template_signature)"

  if [[ -f "$MONITOR_SIG_FILE" && -f "$TEMPLATE_SIG_FILE" && "$(cat "$MONITOR_SIG_FILE" 2>/dev/null)" == "$sig" && "$(cat "$TEMPLATE_SIG_FILE" 2>/dev/null)" == "$tmpl_sig" && "${#CONKY_RENDERED_CONFIGS[@]}" -gt 0 ]]; then
    return 0
  fi

  mkdir -p "$CONKY_LAYOUT_DIR"
  printf '%s\n' "$sig" >"$MONITOR_SIG_FILE"
  printf '%s\n' "$tmpl_sig" >"$TEMPLATE_SIG_FILE"
  rm -rf "$CONKY_LAYOUT_DIR"/*
  CONKY_RENDERED_CONFIGS=()

  mapfile -t specs < <(monitor_specs)
  if [[ "${#specs[@]}" -eq 0 ]]; then
    log "no monitors detected from xrandr; keeping existing conky layout."
    return 0
  fi

  for idx in "${!specs[@]}"; do
    read -r name width height origin_x origin_y <<<"${specs[$idx]}"
    monitor_dir="$CONKY_LAYOUT_DIR/head${idx}"
    mkdir -p "$monitor_dir"

    if [[ "$idx" -eq 0 ]]; then
      render_conky_config "$BASE/.conkyrc0" "$monitor_dir/.conkyrc0" "$(calc_pct "$width" 0.496)" "$(calc_pct "$height" 0.03)" 0 top_left
      render_conky_config "$BASE/.conkyrc1" "$monitor_dir/.conkyrc1" "$(calc_pct "$width" 0.482)" "$(calc_pct "$height" 0.446)" 0 top_left
      render_conky_config "$BASE/.conkyrc2" "$monitor_dir/.conkyrc2" "$(calc_pct "$width" 0.672)" "$(calc_pct "$height" 0.03)" 0 top_left
      render_conky_config "$BASE/.conkyrc3" "$monitor_dir/.conkyrc3" "$(calc_pct "$width" 0.862)" "$(calc_pct "$height" 0.03)" 0 top_left
      CONKY_RENDERED_CONFIGS+=("$monitor_dir/.conkyrc0" "$monitor_dir/.conkyrc1" "$monitor_dir/.conkyrc2" "$monitor_dir/.conkyrc3")
    else
      render_conky_config "$BASE/.conkyrc0-head1" "$monitor_dir/.conkyrc0" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.015)" "$idx" top_left
      render_conky_config "$BASE/.conkyrc1-head1" "$monitor_dir/.conkyrc1" "$(calc_pct "$width" 0.682)" "$(calc_pct "$height" 0.015)" "$idx" top_left
      render_conky_config "$BASE/.conkyrc2-head1" "$monitor_dir/.conkyrc2" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.31)" "$idx" top_left
      render_conky_config "$BASE/.conkyrc3-head1" "$monitor_dir/.conkyrc3" "$(calc_pct "$width" 0.82)" "$(calc_pct "$height" 0.015)" "$idx" top_left
      render_conky_config "$BASE/.conkyrc4-head1" "$monitor_dir/.conkyrc4" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.62)" "$idx" top_left
      CONKY_RENDERED_CONFIGS+=("$monitor_dir/.conkyrc0" "$monitor_dir/.conkyrc1" "$monitor_dir/.conkyrc2" "$monitor_dir/.conkyrc3" "$monitor_dir/.conkyrc4")
    fi
  done

  log "rendered conky layout for ${#specs[@]} monitor(s)."
}

start_rendered_conky() {
  if [[ "${#CONKY_RENDERED_CONFIGS[@]}" -eq 0 ]]; then
    return 0
  fi

  pkill -f "$CONKY_LAYOUT_DIR" >/dev/null 2>&1 || true
  pkill -f "$BASE/.conkyrc[0-4]" >/dev/null 2>&1 || true
  sleep 1

  local cfg
  for cfg in "${CONKY_RENDERED_CONFIGS[@]}"; do
    "$CONKY_BIN" -d -c "$cfg" >/dev/null 2>&1 || true
  done
}

local_ip_for_iface() {
  local iface="$1"
  [[ -n "$iface" ]] || return 0
  ip -4 -o addr show dev "$iface" 2>/dev/null | awk 'NR==1 {sub(/\/.*/, "", $4); print $4}'
}

public_ip() {
  curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true
}

coingecko_prices() {
  curl -fsS --max-time 12 \
    'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,monero&vs_currencies=usd' \
    2>/dev/null || true
}

set_wallpaper() {
  if command -v gsettings >/dev/null 2>&1 && [[ -f "$WALLPAPER" ]]; then
    local uri="file://$WALLPAPER"
    gsettings set org.gnome.desktop.background picture-uri "$uri" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.background picture-uri-dark "$uri" >/dev/null 2>&1 || true
  fi
}

update_snapshot() {
  local iface gateway lip pip json btc xmr dns1 dns2 mem_used mem_total openfiles hwid machine_id kernel boot_mode ipv6_state cups_state
  local tor_status vpn_status public_state country

  iface="$(default_iface)"
  gateway="$(default_gateway)"
  lip="$(local_ip_for_iface "$iface")"
  pip="$(public_ip)"
  json="$(coingecko_prices)"

  btc="$(printf '%s' "$json" | sed -n 's/.*"bitcoin":{"usd":\([0-9.]*\)}.*/\1/p')"
  xmr="$(printf '%s' "$json" | sed -n 's/.*"monero":{"usd":\([0-9.]*\)}.*/\1/p')"

  dns1="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  dns2="$(awk '/^nameserver/ {print $2; exit 1}' /etc/resolv.conf 2>/dev/null || true)"

  mem_used="$(free -h | awk '/Mem:/ {print $3 " / " $2}')"
  openfiles="$(lsof -u "$USER" 2>/dev/null | wc -l | tr -d ' ' || printf '0')"
  machine_id="$(cat /etc/machine-id 2>/dev/null || hostname)"
  kernel="$(uname -r)"
  hwid="$(printf '%s' "${machine_id}:${HOSTNAME:-$(hostname)}:${kernel}" | sha256sum | awk '{print substr($1,1,21)}')"

  boot_mode="Installed"
  ipv6_state="Disabled"
  if ip -6 addr show scope global 2>/dev/null | grep -q 'inet6'; then
    ipv6_state="Enabled"
  fi

  cups_state="Stopped"
  if systemctl is-active --quiet cups 2>/dev/null; then
    cups_state="Running"
  fi

  if valid_ipv4 "$pip"; then
    public_state="Connected"
    country="N/A"
  else
    public_state="Offline"
    pip="-"
    country="-"
  fi

  if [[ -n "$iface" ]]; then
    write_file "$BASE/intfused" "$iface"
  else
    write_file "$BASE/intfused" "none"
  fi

  if [[ -n "$pip" && "$pip" != "-" ]]; then
    write_file "$BASE/.eeds-ipinfo" "${pip}:[${public_state}]:${country}"
    write_file "$BASE/.eeds-oipinfo" "$pip"
    write_file "$BASE/.eeds-ocipinfo" "ISP"
  else
    write_file "$BASE/.eeds-ipinfo" "-:[Offline]:-"
    write_file "$BASE/.eeds-oipinfo" "-"
    write_file "$BASE/.eeds-ocipinfo" "-"
  fi

  write_file "$BASE/.eeds-tipinfo" "-:Disabled"
  write_file "$BASE/.countfile" "1"
  write_file "$BASE/.eeds-ipinfo" "${pip}:[${public_state}]:${country}"
  write_file "$BASE/netCurrentStatus" "$public_state"
  write_file "$BASE/iptypeletter" "${public_state}"
  write_file "$BASE/randomDomain" "api.coingecko.com"
  write_file "$BASE/btcprice" "${btc:-N/A}"
  write_file "$BASE/xmrprice" "${xmr:-N/A}"
  write_file "$BASE/btcdonation" "--"
  write_file "$BASE/BandSatus" "Custom overlay active"
  write_file "$BASE/version" "custom"
  write_file "$BASE/newversionalert" ""
  write_file "$BASE/boottype" "$boot_mode"
  write_file "$BASE/persistent" "No"
  write_file "$BASE/hddencrypted" "Unknown"
  write_file "$BASE/nuked" "No"
  write_file "$BASE/vpnufwstatus" "N/A"
  write_file "$BASE/ipv6status" "$ipv6_state"
  write_file "$BASE/autologinstatus" "No"
  write_file "$BASE/cupsstatus" "$cups_state"
  write_file "$BASE/swapcrypt" "No"
  write_file "$BASE/totalswaps" "$(swapon --show 2>/dev/null | tail -n +2 | wc -l | tr -d ' ' || printf '0')"
  write_file "$BASE/forcefonts" "0"
  write_file "$BASE/healthsactionstatus" "OK"
  write_file "$BASE/securityscore" "72"
  write_file "$BASE/securitymodel" "Custom desktop overlay"
  write_file "$BASE/vpntype" "None"
  write_file "$BASE/vpnattributes" $'port=0\nprotocolu=none\ntheProfile=none'
  write_file "$BASE/tvpnbandwidth" "0"
  write_file "$BASE/forcetempdns" "${dns1:-1.1.1.1}"
  write_file "$BASE/toronvpn" "No"
  write_file "$BASE/torifysystemstatus" "No"
  write_file "$BASE/torblock14" "0"
  write_file "$BASE/.eeds-oipinfo" "${pip:- -}"
  write_file "$BASE/.eeds-ocipinfo" "ISP"
  write_file "$BASE/HWID" "$hwid"
  write_file "$BASE/Memused" "${mem_used:-N/A}"
  write_file "$BASE/openfiles" "${openfiles:-0}"
  write_file "$BASE/Globalconfig" $'#!/bin/bash\nKodachi_version=custom;\nMyhome_path="${HOME}";\nMykodachi_path="${HOME}/.kbase";'
  write_file "$BASE/dns/autodnscrypt" "0"
  write_file "$BASE/dns/dns1" "${dns1:-1.1.1.1}"
  write_file "$BASE/dns/dns4" "${dns2:-1.0.0.1}"
}

refresh_conky_layouts() {
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    log "no graphical display detected; skipping conky launch."
    return 0
  fi

  if [[ ! -x "$CONKY_BIN" ]]; then
    log "local conky binary is missing; updated files only."
    return 0
  fi

  local current_sig
  current_sig="$(monitor_signature)"
  local current_tmpl_sig
  current_tmpl_sig="$(template_signature)"
  if [[ -f "$MONITOR_SIG_FILE" && -f "$TEMPLATE_SIG_FILE" && "$(cat "$MONITOR_SIG_FILE" 2>/dev/null)" == "$current_sig" && "$(cat "$TEMPLATE_SIG_FILE" 2>/dev/null)" == "$current_tmpl_sig" && "${#CONKY_RENDERED_CONFIGS[@]}" -gt 0 ]]; then
    return 0
  fi

  build_conky_layouts
  start_rendered_conky
}

daemon_loop() {
  local last_sig current_sig tick
  last_sig=""
  tick=0
  while true; do
    current_sig="$(monitor_signature 2>/dev/null || printf 'no-xrandr')"
    if [[ "$current_sig" != "$last_sig" ]]; then
      log "monitor signature changed; rebuilding conky layout."
      refresh_conky_layouts
      last_sig="$current_sig"
    fi

    if (( tick % 150 == 0 )); then
      update_snapshot || log "snapshot refresh failed; keeping previous state."
    fi

    tick=$((tick + 1))
    sleep 1
  done
}

ensure_daemon_running() {
  if pgrep -af -- "$SCRIPT_PATH --daemon" >/dev/null 2>&1; then
    return 0
  fi

  nohup "$SCRIPT_PATH" --daemon >/dev/null 2>&1 &
}

case "${1:-}" in
  --daemon)
    daemon_loop
    ;;
  *)
    update_snapshot
    set_wallpaper
    refresh_conky_layouts
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
      ensure_daemon_running
    fi
    ;;
esac

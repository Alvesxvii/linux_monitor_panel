#!/usr/bin/env bash
set -euo pipefail

BASE="$HOME/.lmpanel"
BG_DIR="$HOME/.local/share/backgrounds/lmpanel"
WALLPAPER="$BG_DIR/243811.png"
LOG_FILE="$BASE/lmpanel.log"
CONKY_BIN="$HOME/.local/bin/conky"
CONKY_LAYOUT_DIR="$BASE/conky-runtime"
EDIT_LAYOUT_DIR="$BASE/conky-edit-runtime"
MANUAL_LAYOUT_DIR="$BASE/conky-manual-layout"
MANUAL_GEOM_FILE="$BASE/manual-layout.tsv"
AUTO_GEOM_FILE="$BASE/auto-layout.tsv"
MONITOR_SIG_FILE="$BASE/monitor-signature"
TEMPLATE_SIG_FILE="$BASE/template-signature"
MANUAL_LAYOUT_SIG_FILE="$BASE/manual-layout-signature"
AUTO_LAYOUT_SIG_FILE="$BASE/auto-layout-signature"
LAYOUT_MODE_FILE="$BASE/layout-mode"
EDIT_PID_FILE="$BASE/edit-mode.pid"
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

manual_layout_signature() {
  if [[ ! -f "$MANUAL_GEOM_FILE" ]]; then
    printf 'no-manual-layout\n'
    return 0
  fi

  sha256sum "$MANUAL_GEOM_FILE" 2>/dev/null | awk '{print $1}'
}

layout_signature() {
  local geom_file="$1"
  local tmpl_sig="$2"

  if [[ ! -f "$geom_file" ]]; then
    printf 'no-layout\n'
    return 0
  fi

  {
    sha256sum "$geom_file" 2>/dev/null
    printf '%s\n' "$tmpl_sig"
  } | sha256sum | awk '{print $1}'
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

window_title_for_path() {
  local path="$1"
  local parent base
  parent="$(basename "$(dirname "$path")")"
  base="$(basename "$path")"
  base="${base#.}"
  printf 'lmpanel-%s-%s' "$parent" "$base"
}

render_conky_config() {
  local src="$1"
  local dst="$2"
  local gap_x="$3"
  local gap_y="$4"
  local head="$5"
  local alignment="${6:-top_left}"
  local window_type="${7:-desktop}"
  local window_hints="${8:-}"
  local title

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  title="$(window_title_for_path "$dst")"
  perl -0pi -e "s/^gap_x\\s+\\d+/gap_x $gap_x/m; s/^gap_y\\s+\\d+/gap_y $gap_y/m; s/^xinerama_head\\s+\\d+/xinerama_head $head/m; s/^alignment\\s+\\S+/alignment $alignment/m; s/^own_window_type\\s+\\S+/own_window_type $window_type/m; s/^own_window_hints\\s+.+\$/own_window_hints $window_hints/m if length(q{$window_hints}); s/^own_window_colour\\s+black/own_window_colour black\\nown_window_title $title/m; s/^own_window_title\\s+.+$/own_window_title $title/m" "$dst"
}

render_saved_layout() {
  local geom_file="$1"
  local sig_file="$2"
  local label="$3"
  local window_type="$4"
  local window_hints="$5"
  local tmpl_sig="$6"
  local layout_sig rel x y head source

  layout_sig="$(layout_signature "$geom_file" "$tmpl_sig")"
  if [[ -f "$sig_file" && "$(cat "$sig_file" 2>/dev/null)" == "$layout_sig" && "${#CONKY_RENDERED_CONFIGS[@]}" -gt 0 ]]; then
    return 0
  fi

  mkdir -p "$CONKY_LAYOUT_DIR"
  rm -rf "$CONKY_LAYOUT_DIR"/*
  CONKY_RENDERED_CONFIGS=()

  if [[ ! -f "$geom_file" ]]; then
    log "$label layout mode requested but no layout file exists."
    return 0
  fi

  while IFS=$'\t' read -r rel x y head source; do
    [[ -n "${rel:-}" ]] || continue
    mkdir -p "$CONKY_LAYOUT_DIR/$(dirname "$rel")"
    render_conky_config "$source" "$CONKY_LAYOUT_DIR/$rel" "$x" "$y" "$head" top_left "$window_type" "$window_hints"
    CONKY_RENDERED_CONFIGS+=("$CONKY_LAYOUT_DIR/$rel")
  done <"$geom_file"

  printf '%s\n' "$layout_sig" >"$sig_file"
  log "rendered $label conky layout."
}

capture_current_layouts() {
  local output_file="$1"
  local sig_file="$2"
  local label="$3"
  local source rel geom x y head
  declare -A geom_by_title=()
  declare -A monitor_origin_x=()
  declare -A monitor_origin_y=()

  local idx name width height origin_x origin_y
  mapfile -t specs < <(monitor_specs)
  for idx in "${!specs[@]}"; do
    read -r name width height origin_x origin_y <<<"${specs[$idx]}"
    monitor_origin_x["$idx"]="$origin_x"
    monitor_origin_y["$idx"]="$origin_y"
  done

  while IFS=$'\t' read -r title x y; do
    geom_by_title["$title"]="$x $y"
  done < <(
    python3 - <<'PY'
import re, subprocess
tree = subprocess.check_output(["xwininfo", "-root", "-tree"], text=True, stderr=subprocess.DEVNULL)
pattern = re.compile(
    r'"(?P<title>lmpanel-[^"]+)".*?'
    r'(?P<w>\d+)x(?P<h>\d+)\+(?P<relx>-?\d+)\+(?P<rely>-?\d+)\s+\+'
    r'(?P<x>-?\d+)\+(?P<y>-?\d+)$',
    re.M,
)
for m in pattern.finditer(tree):
    print(f"{m.group('title')}\t{m.group('x')}\t{m.group('y')}")
PY
  )

  : >"$output_file"

  local entries=(
    "head0/.conkyrc0:$BASE/.conkyrc0:0"
    "head0/.conkyrc1:$BASE/.conkyrc1:0"
    "head0/.conkyrc2:$BASE/.conkyrc2:0"
    "head0/.conkyrc3:$BASE/.conkyrc3:0"
    "head1/.conkyrc0:$BASE/.conkyrc0-head1:1"
    "head1/.conkyrc1:$BASE/.conkyrc1-head1:1"
    "head1/.conkyrc2:$BASE/.conkyrc2-head1:1"
    "head1/.conkyrc3:$BASE/.conkyrc3-head1:1"
    "head1/.conkyrc4:$BASE/.conkyrc4-head1:1"
  )

  local entry dest title
  for entry in "${entries[@]}"; do
    IFS=':' read -r rel source head <<<"$entry"
    dest="$BASE/$rel"
    title="$(window_title_for_path "$dest")"
    geom="${geom_by_title[$title]:-}"
    if [[ -z "$geom" ]]; then
      log "could not find window for $title"
      continue
    fi
    read -r x y <<<"$geom"
    x=$((x - ${monitor_origin_x[$head]:-0}))
    y=$((y - ${monitor_origin_y[$head]:-0}))
    printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$x" "$y" "$head" "$source" >>"$output_file"
  done

  printf '%s\n' "$(layout_signature "$output_file" "$(template_signature)")" >"$sig_file"
  log "captured $label layout."
}

build_conky_layouts() {
  local specs monitor_count idx name width height origin_x origin_y sig monitor_dir layout_mode tmpl_sig window_type
  local window_hints
  sig="$(monitor_signature)"
  monitor_count="$(connected_monitor_count)"
  tmpl_sig="$(template_signature)"
  layout_mode="$(cat "$LAYOUT_MODE_FILE" 2>/dev/null || printf 'auto')"
  window_type="desktop"
  window_hints="undecorated,below,sticky,skip_taskbar,skip_pager"
  if [[ "$layout_mode" == "edit" ]]; then
    window_type="normal"
    window_hints="skip_taskbar,skip_pager"
  fi

  if [[ "$layout_mode" == "manual" && -s "$MANUAL_GEOM_FILE" ]]; then
    render_saved_layout "$MANUAL_GEOM_FILE" "$MANUAL_LAYOUT_SIG_FILE" "manual" "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager" "$tmpl_sig"
    return 0
  fi

  if [[ "$layout_mode" == "auto" && -s "$AUTO_GEOM_FILE" ]]; then
    render_saved_layout "$AUTO_GEOM_FILE" "$AUTO_LAYOUT_SIG_FILE" "auto" "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager" "$tmpl_sig"
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
      render_conky_config "$BASE/.conkyrc0" "$monitor_dir/.conkyrc0" "$(calc_pct "$width" 0.345)" "$(calc_pct "$height" 0.075)" 0 top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc1" "$monitor_dir/.conkyrc1" "$(calc_pct "$width" 0.482)" "$(calc_pct "$height" 0.446)" 0 top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc2" "$monitor_dir/.conkyrc2" "$(calc_pct "$width" 0.555)" "$(calc_pct "$height" 0.075)" 0 top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc3" "$monitor_dir/.conkyrc3" "$(calc_pct "$width" 0.735)" "$(calc_pct "$height" 0.075)" 0 top_left "$window_type" "$window_hints"
      CONKY_RENDERED_CONFIGS+=("$monitor_dir/.conkyrc0" "$monitor_dir/.conkyrc1" "$monitor_dir/.conkyrc2" "$monitor_dir/.conkyrc3")
    else
      render_conky_config "$BASE/.conkyrc0-head1" "$monitor_dir/.conkyrc0" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.055)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc1-head1" "$monitor_dir/.conkyrc1" "$(calc_pct "$width" 0.682)" "$(calc_pct "$height" 0.055)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc2-head1" "$monitor_dir/.conkyrc2" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.31)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc3-head1" "$monitor_dir/.conkyrc3" "$(calc_pct "$width" 0.82)" "$(calc_pct "$height" 0.055)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc4-head1" "$monitor_dir/.conkyrc4" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.62)" "$idx" top_left "$window_type" "$window_hints"
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
  write_file "$BASE/Globalconfig" $'#!/bin/bash\nLmpanel_version=custom;\nMyhome_path="${HOME}";\nMylmpanel_path="${HOME}/.lmpanel";'
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

save_current_layouts() {
  capture_current_layouts "$MANUAL_GEOM_FILE" "$MANUAL_LAYOUT_SIG_FILE" "manual"
  printf 'manual\n' >"$LAYOUT_MODE_FILE"
  log "saved manual conky layout."
}

set_auto_layout_mode() {
  local edit_pid
  capture_current_layouts "$AUTO_GEOM_FILE" "$AUTO_LAYOUT_SIG_FILE" "auto"
  edit_pid="$(cat "$EDIT_PID_FILE" 2>/dev/null || true)"
  rm -f "$EDIT_PID_FILE"
  if [[ -n "${edit_pid:-}" ]]; then
    kill "$edit_pid" >/dev/null 2>&1 || true
  fi
  pkill -f "$CONKY_LAYOUT_DIR" >/dev/null 2>&1 || true
  pkill -f "$BASE/.conkyrc[0-4]" >/dev/null 2>&1 || true
  printf 'auto\n' >"$LAYOUT_MODE_FILE"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user restart lmpanel.service >/dev/null 2>&1 || systemctl --user start lmpanel.service >/dev/null 2>&1 || true
}

edit_loop() {
  printf '%s\n' "$$" >"$EDIT_PID_FILE"
  printf 'edit\n' >"$LAYOUT_MODE_FILE"
  systemctl --user stop lmpanel.service >/dev/null 2>&1 || true
  update_snapshot || true
  set_wallpaper
  build_conky_layouts
  start_rendered_conky
  log "edit mode active; move the cards, then run --save-layout."
  while [[ -f "$EDIT_PID_FILE" ]]; do
    sleep 1
  done
}

save_layout_mode() {
  local edit_pid
  save_current_layouts
  edit_pid="$(cat "$EDIT_PID_FILE" 2>/dev/null || true)"
  rm -f "$EDIT_PID_FILE"
  if [[ -n "${edit_pid:-}" ]]; then
    kill "$edit_pid" >/dev/null 2>&1 || true
  fi
  pkill -f "$CONKY_LAYOUT_DIR" >/dev/null 2>&1 || true
  pkill -f "$BASE/.conkyrc[0-4]" >/dev/null 2>&1 || true
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user restart lmpanel.service >/dev/null 2>&1 || systemctl --user start lmpanel.service >/dev/null 2>&1 || true
}

auto_layout_mode() {
  rm -f "$EDIT_PID_FILE"
  printf 'auto\n' >"$LAYOUT_MODE_FILE"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user restart lmpanel.service >/dev/null 2>&1 || systemctl --user start lmpanel.service >/dev/null 2>&1 || true
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
  --edit)
    edit_loop
    ;;
  --save-layout)
    save_layout_mode
    ;;
  --set-auto-layout)
    set_auto_layout_mode
    ;;
  --auto-layout)
    auto_layout_mode
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

#!/usr/bin/env bash
set -euo pipefail

BASE="$HOME/.lmpanel"
BG_DIR="$HOME/.local/share/backgrounds/lmpanel"
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
PROFILE_GEOM_FILE_PREFIX="$BASE/profile-"
PROFILE_LAYOUT_SIG_PREFIX="$BASE/profile-"
LAYOUT_MODE_FILE="$BASE/layout-mode"
EDIT_TARGET_FILE="$BASE/edit-target"
EDIT_PID_FILE="$BASE/edit-mode.pid"
WALLPAPER_MODE_FILE="$BASE/wallpaper-mode"
WALLPAPER_CHOICE_FILE="$BASE/wallpaper-choice"
WALLPAPER_BACKUP_URI_FILE="$BASE/system-wallpaper-uri"
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

current_ping_ms() {
  local target="${1:-8.8.8.8}"
  local output value

  output="$(ping -n -c 1 -W 2 "$target" 2>/dev/null)" || {
    printf 'N/A\n'
    return 0
  }

  value="$(
    awk -F'/' '
      /^rtt|^round-trip/ {
        if ($5 ~ /^[0-9.]+$/) {
          printf "%.1f\n", $5
          exit
        }
      }
      /time=/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^time=/) {
            sub(/^time=/, "", $i)
            if ($i ~ /^[0-9.]+$/) {
              printf "%.1f\n", $i
              exit
            }
          }
        }
      }
    ' <<<"$output"
  )"

  if [[ -z "${value:-}" ]]; then
    printf 'N/A\n'
  else
    printf '%s\n' "$value"
  fi
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
    "$BASE/.conkyrc4" \
    "$BASE/.conkyrc4-head1" \
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
  local render_sig="${3:-desktop:undecorated,below,sticky,skip_taskbar,skip_pager}"

  if [[ ! -f "$geom_file" ]]; then
    printf 'no-layout\n'
    return 0
  fi

  {
    sha256sum "$geom_file" 2>/dev/null
    printf '%s\n%s\n' "$tmpl_sig" "$render_sig"
  } | sha256sum | awk '{print $1}'
}

profile_geom_file() {
  printf '%s\n' "${PROFILE_GEOM_FILE_PREFIX}${1}.tsv"
}

profile_sig_file() {
  printf '%s\n' "${PROFILE_LAYOUT_SIG_PREFIX}${1}-signature"
}

layout_file_for_target() {
  case "$1" in
    manual) printf '%s\n' "$MANUAL_GEOM_FILE" ;;
    auto) printf '%s\n' "$AUTO_GEOM_FILE" ;;
    profile-1|profile-2|profile-3) profile_geom_file "${1#profile-}" ;;
    *) printf '%s\n' "$MANUAL_GEOM_FILE" ;;
  esac
}

layout_sig_file_for_target() {
  case "$1" in
    manual) printf '%s\n' "$MANUAL_LAYOUT_SIG_FILE" ;;
    auto) printf '%s\n' "$AUTO_LAYOUT_SIG_FILE" ;;
    profile-1|profile-2|profile-3) profile_sig_file "${1#profile-}" ;;
    *) printf '%s\n' "$MANUAL_LAYOUT_SIG_FILE" ;;
  esac
}

normalize_edit_target() {
  case "$1" in
    profile-1|profile-2|profile-3|manual)
      printf '%s\n' "$1"
      ;;
    *)
      printf 'manual\n'
      ;;
  esac
}

current_edit_target() {
  normalize_edit_target "$(cat "$EDIT_TARGET_FILE" 2>/dev/null || printf 'manual')"
}

current_wallpaper_mode() {
  local mode
  mode="$(cat "$WALLPAPER_MODE_FILE" 2>/dev/null || printf 'custom')"
  case "$mode" in
    custom|system) printf '%s\n' "$mode" ;;
    *) printf 'custom\n' ;;
  esac
}

current_wallpaper_choice() {
  local choice
  choice="$(cat "$WALLPAPER_CHOICE_FILE" 2>/dev/null || printf '243811.png')"
  if [[ "$choice" == /* ]]; then
    printf '%s\n' "$choice"
  else
    printf '%s\n' "$BG_DIR/$choice"
  fi
}

wallpaper_list() {
  find "$BG_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
    -printf '%f\n' 2>/dev/null | sort
}

wallpaper_cycle() {
  local step="${1:-1}"
  local current basename current_index index next_index
  local -a wallpapers=()

  mapfile -t wallpapers < <(wallpaper_list)
  if [[ "${#wallpapers[@]}" -eq 0 ]]; then
    printf 'nenhum wallpaper encontrado em %s\n' "$BG_DIR" >&2
    return 1
  fi

  basename="$(basename "$(current_wallpaper_choice)")"
  current_index=-1
  for index in "${!wallpapers[@]}"; do
    if [[ "${wallpapers[$index]}" == "$basename" ]]; then
      current_index="$index"
      break
    fi
  done

  if [[ "$current_index" -lt 0 ]]; then
    current_index=0
  fi

  next_index=$(( (current_index + step + ${#wallpapers[@]}) % ${#wallpapers[@]} ))
  printf '%s\n' "${wallpapers[$next_index]}"
}

wallpaper_uri_from_path() {
  local path="$1"
  printf 'file://%s\n' "$path"
}

capture_system_wallpaper_backup() {
  local uri uri_dark
  if command -v gsettings >/dev/null 2>&1; then
    uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)"
    uri_dark="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || true)"
    if [[ -n "$uri" ]]; then
      write_file "$WALLPAPER_BACKUP_URI_FILE" "$uri"
      write_file "$BASE/system-wallpaper-uri-dark" "${uri_dark:-$uri}"
    fi
  fi
}

remember_system_wallpaper() {
  capture_system_wallpaper_backup
  if [[ -f "$WALLPAPER_BACKUP_URI_FILE" ]]; then
    log "wallpaper do sistema lembrado."
  else
    log "não foi possível lembrar o wallpaper do sistema; gsettings indisponível ou wallpaper não definido."
    return 1
  fi
}

apply_wallpaper_uri() {
  local uri="$1"
  if command -v gsettings >/dev/null 2>&1 && [[ -n "$uri" ]]; then
    gsettings set org.gnome.desktop.background picture-uri "$uri" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.background picture-uri-dark "$uri" >/dev/null 2>&1 || true
  fi
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
      }' | sort -k4,4n -k5,5n
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
  local layout_sig rel x y head source active_count
  local -a specs=()

  mapfile -t specs < <(monitor_specs)
  active_count="${#specs[@]}"
  if [[ "$active_count" -lt 1 ]]; then
    active_count=1
  fi

  layout_sig="$(layout_signature "$geom_file" "$tmpl_sig" "${window_type}:${window_hints}")"
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
    if [[ "${head:-0}" -ge "$active_count" ]]; then
      continue
    fi
    mkdir -p "$CONKY_LAYOUT_DIR/$(dirname "$rel")"
    render_conky_config "$source" "$CONKY_LAYOUT_DIR/$rel" "$x" "$y" "$head" top_left "$window_type" "$window_hints"
    CONKY_RENDERED_CONFIGS+=("$CONKY_LAYOUT_DIR/$rel")
  done <"$geom_file"

  printf '%s\n' "$layout_sig" >"$sig_file"
  log "rendered $label conky layout."
}

append_crypto_layout() {
  local window_type="$1"
  local window_hints="$2"
  local specs idx name width height origin_x origin_y monitor_dir

  if [[ "${CONKY_RENDERED_CONFIGS[*]}" == *".conkyrc4"* ]]; then
    return 0
  fi

  mapfile -t specs < <(monitor_specs)
  for idx in "${!specs[@]}"; do
    read -r name width height origin_x origin_y <<<"${specs[$idx]}"
    monitor_dir="$CONKY_LAYOUT_DIR/head${idx}"
    mkdir -p "$monitor_dir"

    if [[ "$idx" -eq 0 ]]; then
      render_conky_config "$BASE/.conkyrc4" "$monitor_dir/.conkyrc4" "$(calc_pct "$width" 0.555)" "$(calc_pct "$height" 0.535)" 0 top_left "$window_type" "$window_hints"
    else
      render_conky_config "$BASE/.conkyrc4-head1" "$monitor_dir/.conkyrc4" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.535)" "$idx" top_left "$window_type" "$window_hints"
    fi

    CONKY_RENDERED_CONFIGS+=("$monitor_dir/.conkyrc4")
  done
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
    "head0/.conkyrc4:$BASE/.conkyrc4:0"
    "head1/.conkyrc0:$BASE/.conkyrc0:1"
    "head1/.conkyrc1:$BASE/.conkyrc1:1"
    "head1/.conkyrc2:$BASE/.conkyrc2:1"
    "head1/.conkyrc3:$BASE/.conkyrc3:1"
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

  printf '%s\n' "$(layout_signature "$output_file" "$(template_signature)" "desktop:undecorated,below,sticky,skip_taskbar,skip_pager")" >"$sig_file"
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
    local edit_target edit_geom edit_sig
    edit_target="$(current_edit_target)"
    case "$edit_target" in
      profile-1|profile-2|profile-3)
        edit_geom="$(layout_file_for_target "$edit_target")"
        edit_sig="$(layout_sig_file_for_target "$edit_target")"
        if [[ -s "$edit_geom" ]]; then
          render_saved_layout "$edit_geom" "$edit_sig" "$edit_target" "$window_type" "$window_hints" "$tmpl_sig"
          append_crypto_layout "$window_type" "$window_hints"
          return 0
        fi
        ;;
    esac

    if [[ -s "$MANUAL_GEOM_FILE" ]]; then
      render_saved_layout "$MANUAL_GEOM_FILE" "$MANUAL_LAYOUT_SIG_FILE" "manual-edit" "$window_type" "$window_hints" "$tmpl_sig"
      append_crypto_layout "$window_type" "$window_hints"
      return 0
    fi
    if [[ -s "$AUTO_GEOM_FILE" ]]; then
      render_saved_layout "$AUTO_GEOM_FILE" "$AUTO_LAYOUT_SIG_FILE" "auto-edit" "$window_type" "$window_hints" "$tmpl_sig"
      append_crypto_layout "$window_type" "$window_hints"
      return 0
    fi
  fi

  if [[ "$layout_mode" == "manual" && -s "$MANUAL_GEOM_FILE" ]]; then
    render_saved_layout "$MANUAL_GEOM_FILE" "$MANUAL_LAYOUT_SIG_FILE" "manual" "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager" "$tmpl_sig"
    append_crypto_layout "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager"
    return 0
  fi

  if [[ "$layout_mode" == "auto" && -s "$AUTO_GEOM_FILE" ]]; then
    render_saved_layout "$AUTO_GEOM_FILE" "$AUTO_LAYOUT_SIG_FILE" "auto" "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager" "$tmpl_sig"
    append_crypto_layout "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager"
    return 0
  fi

  if [[ "$layout_mode" == profile-* ]]; then
    local profile_num profile_geom profile_sig
    profile_num="${layout_mode#profile-}"
    profile_geom="$(profile_geom_file "$profile_num")"
    profile_sig="$(profile_sig_file "$profile_num")"
    if [[ -s "$profile_geom" ]]; then
      render_saved_layout "$profile_geom" "$profile_sig" "$layout_mode" "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager" "$tmpl_sig"
      append_crypto_layout "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager"
      return 0
    fi
    if [[ -s "$AUTO_GEOM_FILE" ]]; then
      render_saved_layout "$AUTO_GEOM_FILE" "$AUTO_LAYOUT_SIG_FILE" "auto" "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager" "$tmpl_sig"
      append_crypto_layout "desktop" "undecorated,below,sticky,skip_taskbar,skip_pager"
      return 0
    fi
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
      render_conky_config "$BASE/.conkyrc4" "$monitor_dir/.conkyrc4" "$(calc_pct "$width" 0.555)" "$(calc_pct "$height" 0.535)" 0 top_left "$window_type" "$window_hints"
      CONKY_RENDERED_CONFIGS+=("$monitor_dir/.conkyrc0" "$monitor_dir/.conkyrc1" "$monitor_dir/.conkyrc2" "$monitor_dir/.conkyrc3" "$monitor_dir/.conkyrc4")
    else
      render_conky_config "$BASE/.conkyrc0" "$monitor_dir/.conkyrc0" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.055)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc1" "$monitor_dir/.conkyrc1" "$(calc_pct "$width" 0.682)" "$(calc_pct "$height" 0.055)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc2" "$monitor_dir/.conkyrc2" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.31)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc3" "$monitor_dir/.conkyrc3" "$(calc_pct "$width" 0.82)" "$(calc_pct "$height" 0.055)" "$idx" top_left "$window_type" "$window_hints"
      render_conky_config "$BASE/.conkyrc4-head1" "$monitor_dir/.conkyrc4" "$(calc_pct "$width" 0.547)" "$(calc_pct "$height" 0.535)" "$idx" top_left "$window_type" "$window_hints"
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
    'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,tether,nano&vs_currencies=usd,brl&include_24hr_change=true' \
    2>/dev/null || true
}

tradingview_brazil_quotes() {
  curl -fsS --max-time 15 \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'Origin: https://www.tradingview.com' \
    -H 'Referer: https://www.tradingview.com/' \
    --data '{"symbols":{"tickers":["BMFBOVESPA:IBOV","BMFBOVESPA:MXRF11","BMFBOVESPA:AREA11"],"query":{"types":[]}},"columns":["close","change","change_abs","pricescale","name","description"]}' \
    'https://scanner.tradingview.com/brazil/scan' \
    2>/dev/null || true
}

format_usd_price() {
  local value="${1:-}"
  if [[ -z "$value" || "$value" == "N/A" ]]; then
    printf 'N/A\n'
    return 0
  fi

  python3 - <<'PY' "$value"
import sys
from decimal import Decimal, InvalidOperation
raw = sys.argv[1]
try:
    num = Decimal(raw)
except InvalidOperation:
    print("N/A")
    raise SystemExit(0)
print("$ " + f"{num:,.2f}")
PY
}

format_brl_price() {
  local value="${1:-}"
  if [[ -z "$value" || "$value" == "N/A" ]]; then
    printf 'N/A\n'
    return 0
  fi

  python3 - <<'PY' "$value"
import sys
from decimal import Decimal, InvalidOperation
raw = sys.argv[1]
try:
    num = Decimal(raw)
except InvalidOperation:
    print("N/A")
    raise SystemExit(0)
formatted = f"{num:,.2f}"
formatted = formatted.replace(",", "X").replace(".", ",").replace("X", ".")
print("R$ " + formatted)
PY
}

format_index_points() {
  local value="${1:-}"
  if [[ -z "$value" || "$value" == "N/A" ]]; then
    printf 'N/A\n'
    return 0
  fi

  python3 - <<'PY' "$value"
import sys
from decimal import Decimal, InvalidOperation
raw = sys.argv[1]
try:
    num = Decimal(raw)
except InvalidOperation:
    print("N/A")
    raise SystemExit(0)
formatted = f"{num:,.2f}"
formatted = formatted.replace(",", "X").replace(".", ",").replace("X", ".")
print(formatted)
PY
}

format_percent_change() {
  local value="${1:-}"
  if [[ -z "$value" || "$value" == "N/A" ]]; then
    printf 'N/A\n'
    return 0
  fi

  python3 - <<'PY' "$value"
import sys
from decimal import Decimal, InvalidOperation
raw = sys.argv[1]
try:
    num = Decimal(raw)
except InvalidOperation:
    print("N/A")
    raise SystemExit(0)
sign = "+" if num >= 0 else "-"
num = abs(num)
formatted = f"{num:.2f}".replace(".", ",")
print(f"{sign}{formatted}%")
PY
}

format_percent_change_colorized() {
  local value="${1:-}"
  local formatted color
  formatted="$(format_percent_change "$value")"
  case "$formatted" in
    N/A) printf 'N/A\n' ;;
    +*) printf '${color1}%s${color2}\n' "$formatted" ;;
    -*) printf '${color FF3333}%s${color2}\n' "$formatted" ;;
    *) printf '%s\n' "$formatted" ;;
  esac
}

iface_rx_tx_bytes() {
  local iface="${1:-}"
  [[ -n "$iface" ]] || return 1
  awk -v iface="$iface" '
    $1 == iface":" {
      print $2, $10;
      exit
    }
  ' /proc/net/dev 2>/dev/null
}

format_bytes_per_second() {
  local value="${1:-}"
  if [[ -z "$value" || "$value" == "N/A" ]]; then
    printf 'N/A\n'
    return 0
  fi

  python3 - <<'PY' "$value"
import sys
from decimal import Decimal, InvalidOperation
raw = sys.argv[1]
try:
    num = Decimal(raw)
except InvalidOperation:
    print("N/A")
    raise SystemExit(0)
units = ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s"]
idx = 0
while num >= 1024 and idx < len(units) - 1:
    num /= 1024
    idx += 1
print(f"{num:.2f} {units[idx]}")
PY
}

format_decimal_gb() {
  local value="${1:-}"
  if [[ -z "$value" || "$value" == "N/A" ]]; then
    printf 'N/A\n'
    return 0
  fi

  python3 - <<'PY' "$value"
import sys
from decimal import Decimal, InvalidOperation
raw = sys.argv[1]
try:
    num = Decimal(raw) / Decimal(1000**3)
except InvalidOperation:
    print("N/A")
    raise SystemExit(0)
print(f"{num:.1f} GB")
PY
}

update_traffic_average_snapshot() {
  local iface now rx tx history tmp newest_ts newest_rx newest_tx oldest_ts oldest_rx oldest_tx elapsed down_bps up_bps
  iface="$(default_iface)"
  [[ -n "$iface" ]] || {
    write_file "$BASE/trafficavgdown_display" "N/A"
    write_file "$BASE/trafficavgup_display" "N/A"
    return 0
  }

  read -r rx tx < <(iface_rx_tx_bytes "$iface" 2>/dev/null || printf 'N/A N/A')
  if [[ -z "${rx:-}" || -z "${tx:-}" || "$rx" == "N/A" || "$tx" == "N/A" ]]; then
    write_file "$BASE/trafficavgdown_display" "N/A"
    write_file "$BASE/trafficavgup_display" "N/A"
    return 0
  fi

  now="$(date +%s)"
  history="$BASE/traffic-history.tsv"
  tmp="$(mktemp)"
  {
    printf '%s\t%s\t%s\t%s\n' "$now" "$iface" "$rx" "$tx"
    [[ -f "$history" ]] && cat "$history"
  } | awk -F'\t' -v now="$now" -v window=600 '($1 ~ /^[0-9]+$/) && (now - $1) <= window { print }' >"$tmp"
  mv "$tmp" "$history"

  read -r newest_ts newest_rx newest_tx oldest_ts oldest_rx oldest_tx < <(
    awk -F'\t' -v iface="$iface" '
      $2 == iface {
        if (!seen) {
          newest_ts = $1
          newest_rx = $3
          newest_tx = $4
          seen = 1
        }
        oldest_ts = $1
        oldest_rx = $3
        oldest_tx = $4
      }
      END {
        if (seen) {
          print newest_ts, newest_rx, newest_tx, oldest_ts, oldest_rx, oldest_tx
        }
      }
    ' "$history"
  )

  if [[ -z "${newest_ts:-}" || -z "${oldest_ts:-}" ]]; then
    write_file "$BASE/trafficavgdown_display" "N/A"
    write_file "$BASE/trafficavgup_display" "N/A"
    return 0
  fi

  elapsed=$((newest_ts - oldest_ts))
  if (( elapsed <= 0 )); then
    write_file "$BASE/trafficavgdown_display" "N/A"
    write_file "$BASE/trafficavgup_display" "N/A"
    return 0
  fi

  down_bps=$(( (newest_rx - oldest_rx) / elapsed ))
  up_bps=$(( (newest_tx - oldest_tx) / elapsed ))
  (( down_bps < 0 )) && down_bps=0
  (( up_bps < 0 )) && up_bps=0

  write_file "$BASE/trafficavgdown_display" "$(format_bytes_per_second "$down_bps")"
  write_file "$BASE/trafficavgup_display" "$(format_bytes_per_second "$up_bps")"
}

update_ping_snapshot() {
  local ping_target
  if pgrep -x openvpn >/dev/null 2>&1 || pgrep -f 'openvpn --daemon --config' >/dev/null 2>&1; then
    ping_target="9.9.9.9"
  else
    ping_target="8.8.8.8"
  fi
  write_file "$BASE/pingcurrent" "$(current_ping_ms "$ping_target")"
}

set_wallpaper_custom() {
  local wallpaper_path uri
  wallpaper_path="$(current_wallpaper_choice)"
  if [[ ! -f "$wallpaper_path" ]]; then
    wallpaper_path="$BG_DIR/243811.png"
  fi

  if [[ -f "$wallpaper_path" ]]; then
    capture_system_wallpaper_backup
    uri="$(wallpaper_uri_from_path "$wallpaper_path")"
    write_file "$WALLPAPER_MODE_FILE" "custom"
    write_file "$WALLPAPER_CHOICE_FILE" "$(basename "$wallpaper_path")"
    apply_wallpaper_uri "$uri"
  fi
}

set_wallpaper_by_name() {
  local wallpaper_arg="$1"
  local wallpaper_path
  if [[ "$wallpaper_arg" == /* ]]; then
    wallpaper_path="$wallpaper_arg"
  else
    wallpaper_path="$BG_DIR/$wallpaper_arg"
  fi

  if [[ ! -f "$wallpaper_path" ]]; then
    printf 'wallpaper não encontrado: %s\n' "$wallpaper_arg" >&2
    return 1
  fi

  capture_system_wallpaper_backup
  write_file "$WALLPAPER_CHOICE_FILE" "$(basename "$wallpaper_path")"
  apply_wallpaper_uri "$(wallpaper_uri_from_path "$wallpaper_path")"
  write_file "$WALLPAPER_MODE_FILE" "custom"
}

restore_system_wallpaper() {
  local backup backup_dark
  backup="$(cat "$WALLPAPER_BACKUP_URI_FILE" 2>/dev/null || true)"
  backup_dark="$(cat "$BASE/system-wallpaper-uri-dark" 2>/dev/null || true)"

  write_file "$WALLPAPER_MODE_FILE" "system"
  if [[ -n "$backup" ]]; then
    apply_wallpaper_uri "$backup"
    if [[ -n "$backup_dark" ]]; then
      gsettings set org.gnome.desktop.background picture-uri-dark "$backup_dark" >/dev/null 2>&1 || true
    fi
  elif command -v gsettings >/dev/null 2>&1; then
    gsettings reset org.gnome.desktop.background picture-uri >/dev/null 2>&1 || true
    gsettings reset org.gnome.desktop.background picture-uri-dark >/dev/null 2>&1 || true
  fi
}

apply_wallpaper_policy() {
  case "$(current_wallpaper_mode)" in
    system) restore_system_wallpaper ;;
    custom|*)
      set_wallpaper_custom
      ;;
  esac
}

update_snapshot() {
  local iface gateway lip pip json b3json btc_raw usdt_raw xno_raw btc usdt xno btcchg_raw usdtchg_raw xnochg btcchg usdtchg xnochg
  local ibov_raw mxrf11_raw area11_raw ibov mxrf11 area11 ibovchg_raw mxrf11chg_raw area11chg_raw ibovchg mxrf11chg area11chg
  local dns1 dns2 mem_used mem_total openfiles hwid machine_id kernel boot_mode ipv6_state cups_state os_version_label
  local tor_status vpn_status public_state country
  local root_source root_parent root_model root_size_bytes root_size_label
  local root_total_bytes root_used_bytes root_avail_bytes
  local root_total_display root_used_display root_avail_display
  local home_used_bytes home_size_label
  local query_time

  iface="$(default_iface)"
  gateway="$(default_gateway)"
  lip="$(local_ip_for_iface "$iface")"
  pip="$(public_ip)"
  query_time="hoje às $(date '+%H:%Mh')"
  json="$(coingecko_prices)"

  read -r btc_raw usdt_raw < <(
    python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("bitcoin",{}).get("usd","N/A"), d.get("tether",{}).get("brl","N/A"))' <<<"$json" 2>/dev/null || printf 'N/A N/A'
  )
  read -r xno_raw < <(
    python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("nano",{}).get("brl","N/A"))' <<<"$json" 2>/dev/null || printf 'N/A'
  )
  read -r btcchg_raw usdtchg_raw xnochg_raw < <(
    python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("bitcoin",{}).get("usd_24h_change","N/A"), d.get("tether",{}).get("brl_24h_change","N/A"), d.get("nano",{}).get("brl_24h_change","N/A"))' <<<"$json" 2>/dev/null || printf 'N/A N/A N/A'
  )
  btc="$(format_usd_price "$btc_raw")"
  usdt="$(format_brl_price "$usdt_raw")"
  xno="$(format_brl_price "$xno_raw")"
  btcchg="$(format_percent_change "$btcchg_raw")"
  usdtchg="$(format_percent_change "$usdtchg_raw")"
  xnochg="$(format_percent_change "$xnochg_raw")"

  b3json="$(tradingview_brazil_quotes)"
  read -r ibov_raw ibovchg_raw mxrf11_raw mxrf11chg_raw area11_raw area11chg_raw < <(
    python3 -c 'import json,sys
data=json.loads(sys.stdin.read() or "{}").get("data", [])
symbols={}
for item in data:
    symbols[item.get("s")] = item.get("d") or []
def get(symbol, idx):
    values=symbols.get(symbol) or []
    if idx >= len(values):
        return "N/A"
    value=values[idx]
    return "N/A" if value in (None, "") else value
print(get("BMFBOVESPA:IBOV", 0), get("BMFBOVESPA:IBOV", 1), get("BMFBOVESPA:MXRF11", 0), get("BMFBOVESPA:MXRF11", 1), get("BMFBOVESPA:AREA11", 0), get("BMFBOVESPA:AREA11", 1))' \
      <<<"$b3json" 2>/dev/null || printf 'N/A N/A N/A N/A N/A N/A'
  )
  ibov="$(format_index_points "$ibov_raw")"
  mxrf11="$(format_brl_price "$mxrf11_raw")"
  area11="$(format_brl_price "$area11_raw")"
  ibovchg="$(format_percent_change "$ibovchg_raw")"
  mxrf11chg="$(format_percent_change "$mxrf11chg_raw")"
  area11chg="$(format_percent_change "$area11chg_raw")"

  dns1="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  dns2="$(awk '/^nameserver/ {print $2; exit 1}' /etc/resolv.conf 2>/dev/null || true)"

  mem_used="$(free -h | awk '/Mem:/ {print $3 " / " $2}')"
  openfiles="$(lsof -u "$USER" 2>/dev/null | wc -l | tr -d ' ' || printf '0')"
  machine_id="$(cat /etc/machine-id 2>/dev/null || hostname)"
  kernel="$(uname -r)"
  hwid="$(printf '%s' "${machine_id}:${HOSTNAME:-$(hostname)}:${kernel}" | sha256sum | awk '{print substr($1,1,21)}')"
  os_version_label="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION:-24.04.4 LTS}" | sed 's/ ([^)]*)$//')"
  root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  root_parent="$(lsblk -no PKNAME "$root_source" 2>/dev/null | head -n1 || true)"
  if [[ -n "$root_parent" ]]; then
    root_model="$(lsblk -dn -o MODEL "/dev/$root_parent" 2>/dev/null | head -n1 | xargs)"
    root_size_bytes="$(lsblk -dn -b -o SIZE "/dev/$root_parent" 2>/dev/null | head -n1 | tr -d ' ' || true)"
    if [[ -n "$root_size_bytes" ]]; then
      root_size_label="$(awk -v bytes="$root_size_bytes" 'BEGIN { printf "%.0fTB", bytes / 1000000000000 }')"
    fi
  fi
  read -r root_total_bytes root_used_bytes root_avail_bytes < <(df -B1 / 2>/dev/null | awk 'NR==2 {print $2, $3, $4}')
  home_used_bytes="$(du -sbx /home/alves 2>/dev/null | awk '{print $1}')"
  root_total_display="$(format_decimal_gb "${root_total_bytes:-N/A}")"
  root_used_display="$(format_decimal_gb "${root_used_bytes:-N/A}")"
  root_avail_display="$(format_decimal_gb "${root_avail_bytes:-N/A}")"
  home_size_label="$(format_decimal_gb "${home_used_bytes:-N/A}")"

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

  update_ping_snapshot
  update_traffic_average_snapshot
  update_tcp_ports_snapshot

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
  write_file "$BASE/lastcryptoquery" "$query_time"
  write_file "$BASE/lastb3query" "$query_time"
  if [[ -n "$root_model" || -n "$root_size_label" ]]; then
  write_file "$BASE/systemdiskinfo" "Ponto de montagem: ${root_model:-Disco} ${root_size_label:-1TB}"
  else
    write_file "$BASE/systemdiskinfo" "Ponto de montagem: Disco"
  fi
  write_file "$BASE/systemdisksummary" "1. used:${root_used_display:-N/A}"
  write_file "$BASE/systemdiskfreelabel" "Total livre: ${root_avail_display:-N/A}"
  write_file "$BASE/homeusedsize" "2. used:${home_size_label:-N/A}"
  write_file "$BASE/btcprice" "${btc:-N/A}"
  write_file "$BASE/usdtprice" "${usdt:-N/A}"
  write_file "$BASE/xnoprice" "${xno:-N/A}"
  write_file "$BASE/btcchange" "${btcchg:-N/A}"
  write_file "$BASE/usdtchange" "${usdtchg:-N/A}"
  write_file "$BASE/xnochange" "${xnochg:-N/A}"
  write_file "$BASE/btcchange_display" "$(format_percent_change_colorized "${btcchg_raw:-N/A}")"
  write_file "$BASE/usdtchange_display" "$(format_percent_change_colorized "${usdtchg_raw:-N/A}")"
  write_file "$BASE/xnochange_display" "$(format_percent_change_colorized "${xnochg_raw:-N/A}")"
  write_file "$BASE/ibovprice" "${ibov:-N/A}"
  write_file "$BASE/mxrf11price" "${mxrf11:-N/A}"
  write_file "$BASE/area11price" "${area11:-N/A}"
  write_file "$BASE/ibovchange" "${ibovchg:-N/A}"
  write_file "$BASE/mxrf11change" "${mxrf11chg:-N/A}"
  write_file "$BASE/area11change" "${area11chg:-N/A}"
  write_file "$BASE/ibovchange_display" "$(format_percent_change_colorized "${ibovchg_raw:-N/A}")"
  write_file "$BASE/mxrf11change_display" "$(format_percent_change_colorized "${mxrf11chg_raw:-N/A}")"
  write_file "$BASE/area11change_display" "$(format_percent_change_colorized "${area11chg_raw:-N/A}")"
  write_file "$BASE/b3domain" "scanner.tradingview.com"
  write_file "$BASE/linuxversion" "$os_version_label"
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
  update_snapshot || log "snapshot refresh failed at startup; keeping previous state."
  while true; do
    current_sig="$(monitor_signature 2>/dev/null || printf 'no-xrandr')"
    if [[ "$current_sig" != "$last_sig" ]]; then
      log "monitor signature changed; rebuilding conky layout."
      refresh_conky_layouts
      last_sig="$current_sig"
    fi

    update_ping_snapshot || log "ping refresh failed; keeping previous value."
    update_traffic_average_snapshot || log "traffic average refresh failed; keeping previous value."

    if (( tick % 150 == 0 )); then
      update_snapshot || log "snapshot refresh failed; keeping previous state."
    fi

    tick=$((tick + 1))
    sleep 1
  done
}

save_current_layouts() {
  local target geom_file sig_file
  target="$(current_edit_target)"
  geom_file="$(layout_file_for_target "$target")"
  sig_file="$(layout_sig_file_for_target "$target")"
  capture_current_layouts "$geom_file" "$sig_file" "$target"
  printf '%s\n' "$target" >"$LAYOUT_MODE_FILE"
  printf '%s\n' "$target" >"$EDIT_TARGET_FILE"
  log "saved $target conky layout."
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
  local target
  target="$(current_edit_target)"
  printf '%s\n' "$target" >"$EDIT_TARGET_FILE"
  printf '%s\n' "$$" >"$EDIT_PID_FILE"
  printf 'edit\n' >"$LAYOUT_MODE_FILE"
  systemctl --user stop lmpanel.service >/dev/null 2>&1 || true
  update_snapshot || true
  apply_wallpaper_policy
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

save_profile_layout_mode() {
  local target
  target="$(current_edit_target)"
  case "$target" in
    profile-1|profile-2|profile-3)
      save_layout_mode
      ;;
    *)
      printf 'lmpanel save-profile requires lmpanel set-profile 1|2|3 first\n' >&2
      return 1
      ;;
  esac
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
  --save-profile-layout)
    save_profile_layout_mode
    ;;
  --set-auto-layout)
    set_auto_layout_mode
    ;;
  --auto-layout)
    auto_layout_mode
    ;;
  --profile-layout)
    profile_num="${2:-}"
    case "$profile_num" in
      1|2|3)
        printf 'profile-%s\n' "$profile_num" >"$LAYOUT_MODE_FILE"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        systemctl --user restart lmpanel.service >/dev/null 2>&1 || systemctl --user start lmpanel.service >/dev/null 2>&1 || true
        ;;
      *)
        printf 'o número do perfil deve ser 1, 2 ou 3\n' >&2
        exit 1
        ;;
    esac
    ;;
  --list-wallpapers)
    wallpaper_list
    ;;
  --remember-wallpaper)
    remember_system_wallpaper
    ;;
  --set-wallpaper)
    wallpaper_arg="${2:-}"
    if [[ -z "$wallpaper_arg" ]]; then
      printf 'o nome do wallpaper é obrigatório\n' >&2
      exit 1
    fi
    set_wallpaper_by_name "$wallpaper_arg"
    ;;
  --next-wallpaper)
    next_wallpaper="$(wallpaper_cycle 1)"
    set_wallpaper_by_name "$next_wallpaper"
    ;;
  --prev-wallpaper)
    prev_wallpaper="$(wallpaper_cycle -1)"
    set_wallpaper_by_name "$prev_wallpaper"
    ;;
  --system-wallpaper)
    restore_system_wallpaper
    ;;
  *)
    update_snapshot
    apply_wallpaper_policy
    refresh_conky_layouts
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
      ensure_daemon_running
    fi
    ;;
esac

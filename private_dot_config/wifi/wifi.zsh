# wifi — thin wrapper over networksetup + 1Password CLI.
# Deps: jq, op (1Password CLI with desktop-app + Touch ID integration).
# 1Password items:
#   connect: title "wifi/<ssid>", field "password"
#   tether:  title $WIFI_TETHER_ITEM, fields "ssid" + "password"
# Run `wifi help` for subcommands. See env defaults below.

: "${WIFI_IFACE:=en0}"
: "${WIFI_OP_VAULT:=Personal}"
: "${WIFI_TETHER_ITEM:=wifi/tether}"

# ---- color helpers -----------------------------------------------------------

_wifi_color_on() { (( ${_WIFI_COLOR:-0} )); }

_c() {
  local code="$1"; shift
  if _wifi_color_on; then
    print -n -- $'\e['"${code}m""$*"$'\e[0m'
  else
    print -n -- "$*"
  fi
}
_c_red()    { _c 31 "$@"; }
_c_green()  { _c 32 "$@"; }
_c_yellow() { _c 33 "$@"; }
_c_cyan()   { _c 36 "$@"; }
_c_dim()    { _c 2 "$@"; }
_c_bold()   { _c 1 "$@"; }

_wifi_label() { _c_dim "$(printf '%-10s' "$1")"; }

# ---- utilities ---------------------------------------------------------------

_wifi_need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "wifi: required command '$1' not found" >&2
  return 1
}

# ---- security parsing --------------------------------------------------------

# macOS occasionally drops the leading "s" (e.g. pairport_security_mode_wpa3_transition).
_wifi_format_security() {
  local raw="$1"
  raw="${raw#spairport_security_mode_}"
  raw="${raw#pairport_security_mode_}"
  print -- "$raw"
}

_wifi_is_open_security() {
  local raw="${1:l}"
  [[ -z "$raw" || "$raw" == *none || "$raw" == *open ]]
}

_wifi_security_colored() {
  local raw="$1" formatted lc
  formatted=$(_wifi_format_security "$raw")
  lc="${raw:l}"
  if _wifi_is_open_security "$raw"; then _c_red    "$formatted"
  elif [[ "$lc" == *wpa3* ]];         then _c_green  "$formatted"
  elif [[ "$lc" == *wpa2* ]];         then _c_yellow "$formatted"
  else                                     _c ""     "$formatted"
  fi
}

# ---- current state -----------------------------------------------------------

_wifi_current_ssid() {
  networksetup -getairportnetwork "$WIFI_IFACE" 2>/dev/null \
    | sed 's/^Current Wi-Fi Network: //'
}

_wifi_current_security() {
  system_profiler -json SPAirPortDataType 2>/dev/null | jq -r '
    .SPAirPortDataType[0].spairport_airport_interfaces[]?
    | select(.spairport_current_network_information)
    | .spairport_current_network_information.spairport_security_mode // ""
  ' 2>/dev/null | head -n1
}

_wifi_current_signal_dbm() {
  # Text form only: JSON has null for signal. Returns e.g. "-57".
  system_profiler SPAirPortDataType 2>/dev/null | awk '
    /Signal \/ Noise:/ {
      if (match($0, /-[0-9]+ dBm/)) {
        print substr($0, RSTART, RLENGTH-4); exit
      }
    }'
}

_wifi_signal_bar() {
  local dbm="$1"
  local -a bars
  bars=('█░░░░' '██░░░' '███░░' '████░' '█████')
  [[ -z "$dbm" ]] && { print -- '─────'; return }
  local level
  if   (( dbm >= -50 )); then level=5
  elif (( dbm >= -60 )); then level=4
  elif (( dbm >= -67 )); then level=3
  elif (( dbm >= -75 )); then level=2
  else level=1
  fi
  print -- "${bars[level]}"
}

# ---- 1Password ---------------------------------------------------------------

# op:// URIs interpret `/` as a path separator, so item titles containing `/`
# (like "wifi/<ssid>") break `op read`. Using `op item get --format=json`
# with jq sidesteps that by passing the title as a single arg.
_wifi_op_get_field() {
  local title="$1" field="$2"
  op item get "$title" --vault "$WIFI_OP_VAULT" --format=json 2>/dev/null \
    | jq -r --arg f "$field" '.fields[]? | select(.label == $f or .id == $f) | .value' \
    | head -n1
}

_wifi_op_read_password() {
  _wifi_op_get_field "$1" password
}

_wifi_op_save_password() {
  local title="$1" password="$2"
  if op item get "$title" --vault "$WIFI_OP_VAULT" >/dev/null 2>&1; then
    op item edit "$title" --vault "$WIFI_OP_VAULT" "password=$password" >/dev/null
  else
    op item create --category=password --vault "$WIFI_OP_VAULT" \
      --title="$title" "password=$password" >/dev/null
  fi
}

_wifi_read_password_stdin() {
  local pw
  printf 'Password for %s: ' "$1" >&2
  IFS= read -rs pw
  printf '\n' >&2
  printf '%s' "$pw"
}

# ---- captive portal ----------------------------------------------------------

_wifi_is_captive() {
  local code
  code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' \
    http://captive.apple.com/hotspot-detect.html 2>/dev/null)
  [[ "$code" != "200" ]]
}

# ---- spinner -----------------------------------------------------------------

# Runs `cmd args...` in background while animating "$msg..." on the current line.
# Captured output is left in $_WIFI_SPINNER_OUTPUT for the caller to inspect
# (useful when the wrapped command exits 0 but reports failure via stdout,
# e.g. networksetup -setairportnetwork).
# no_monitor/no_notify suppress the interactive "[N] pid" / "[N] done" lines
# that zsh prints around every `&` job.
typeset -g _WIFI_SPINNER_OUTPUT=""

_wifi_spinner_run() {
  setopt local_options no_monitor no_notify
  local msg="$1"; shift
  _WIFI_SPINNER_OUTPUT=""
  local tmp rc=0
  tmp=$(mktemp)
  if ! _wifi_color_on; then
    "$@" >"$tmp" 2>&1
    rc=$?
    _WIFI_SPINNER_OUTPUT=$(<"$tmp")
    rm -f "$tmp"
    return $rc
  fi
  {
    ( "$@" >"$tmp" 2>&1 ) &
    local pid=$!
    local -a frames
    frames=('   ' '.  ' '.. ' '...')
    local i=0
    printf '\e[?25l'
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r%s%s' "$msg" "${frames[$(( i % 4 + 1 ))]}"
      sleep 0.2
      (( i++ ))
    done
    wait "$pid" 2>/dev/null
    rc=$?
  } always {
    printf '\r\e[K\e[?25h'
    _WIFI_SPINNER_OUTPUT=$(<"$tmp" 2>/dev/null)
    rm -f "$tmp"
  }
  return $rc
}

# ---- help --------------------------------------------------------------------

_wifi_help() {
  cat <<'USAGE'
wifi — macOS Wi-Fi shortcut

SUBCOMMANDS
  connect <ssid>   Connect to SSID (password from 1Password, prompts if missing)
  tether           Connect to iPhone hotspot (uses $WIFI_TETHER_ITEM)
  scan             List nearby networks
  status           Show current SSID / IP / gateway / signal / encryption
  on               Turn Wi-Fi on
  off              Turn Wi-Fi off
  help             Show this help

ENV (override via export)
  WIFI_IFACE=en0
  WIFI_OP_VAULT=Personal
  WIFI_TETHER_ITEM=wifi/tether    # item with 'ssid' + 'password' fields

connect: 1Password item title "wifi/<ssid>" with field "password".
tether:  1Password item $WIFI_TETHER_ITEM with fields "ssid" + "password".
USAGE
}

# ---- subcommands -------------------------------------------------------------

_wifi_connect() {
  _wifi_need networksetup || return 1
  _wifi_need op || return 1
  local ssid="$1"
  local password="${2-}"   # optional: skip op lookup when caller provides it
  if [[ -z "$ssid" ]]; then
    echo "wifi connect: ssid required" >&2
    return 2
  fi

  local title="wifi/$ssid"
  local from_prompt=0
  if [[ -z "$password" ]]; then
    password=$(_wifi_op_read_password "$title")
    if [[ -z "$password" ]]; then
      from_prompt=1
      password=$(_wifi_read_password_stdin "$ssid")
      if [[ -z "$password" ]]; then
        echo "wifi: empty password, aborting" >&2
        return 2
      fi
    fi
  fi

  local prefix
  prefix="$(_c_cyan '→') Connecting to $(_c_bold "$ssid")"
  _wifi_spinner_run "$prefix" \
    networksetup -setairportnetwork "$WIFI_IFACE" "$ssid" "$password"
  # networksetup -setairportnetwork exits 0 even on failure; verify by SSID.
  if [[ "$(_wifi_current_ssid)" != "$ssid" ]]; then
    printf '%s Failed to connect to %s\n' "$(_c_red '✗')" "$ssid"
    [[ -n "$_WIFI_SPINNER_OUTPUT" ]] \
      && printf '  %s\n' "$(_c_dim "$_WIFI_SPINNER_OUTPUT")" >&2
    return 1
  fi
  printf '%s Connected to %s\n' "$(_c_green '✓')" "$(_c_bold "$ssid")"

  # Offer to save a newly-typed password. Default No to avoid 1P item sprawl
  # on one-off networks (e.g. cafes you won't revisit).
  if (( from_prompt )) && [[ -t 0 ]]; then
    local answer
    printf '%s Save password to op://%s/%s? [y/N] ' \
      "$(_c_dim '?')" "$WIFI_OP_VAULT" "$title"
    read -r answer
    if [[ "${answer:l}" == y || "${answer:l}" == yes ]]; then
      if _wifi_op_save_password "$title" "$password"; then
        printf '  %s\n' "$(_c_dim "saved → op://${WIFI_OP_VAULT}/${title}")"
      else
        echo "wifi: warning — failed to save password to 1Password" >&2
      fi
    fi
  fi

  sleep 2
  if _wifi_is_captive; then
    printf '%s Captive portal detected, opening login page...\n' "$(_c_yellow '↗')"
    command open 'http://captive.apple.com/hotspot-detect.html'
  fi
}

_wifi_tether() {
  _wifi_need op || return 1
  _wifi_need jq || return 1
  local item="$WIFI_TETHER_ITEM"
  if [[ -z "$item" ]]; then
    echo "wifi tether: WIFI_TETHER_ITEM is not set" >&2
    return 2
  fi
  local ssid password
  ssid=$(_wifi_op_get_field "$item" ssid)
  password=$(_wifi_op_get_field "$item" password)
  if [[ -z "$ssid" || -z "$password" ]]; then
    echo "wifi tether: missing 'ssid' or 'password' field in op item '$item' (vault: $WIFI_OP_VAULT)" >&2
    return 1
  fi
  _wifi_connect "$ssid" "$password"
}

_wifi_scan() {
  _wifi_need system_profiler || return 1
  _wifi_need jq || return 1

  local current R Y G C D B X
  current=$(_wifi_current_ssid)
  if _wifi_color_on; then
    R=$'\e[31m'; Y=$'\e[33m'; G=$'\e[32m'
    C=$'\e[36m'; D=$'\e[2m'; B=$'\e[1m'; X=$'\e[0m'
  fi

  printf '%s\n' "$(_c_dim 'Scanning...')"

  system_profiler -json SPAirPortDataType 2>/dev/null | jq -r '
    .SPAirPortDataType[0].spairport_airport_interfaces[]?
    | .spairport_airport_other_local_wireless_networks[]?
    | [
        (._name // "?"),
        ((.spairport_security_mode // "spairport_security_mode_none")
          | sub("^s?pairport_security_mode_"; "")),
        (.spairport_network_channel // "?")
      ] | @tsv
  ' 2>/dev/null \
  | sort -uf \
  | awk -F'\t' -v cur="$current" -v R="$R" -v Y="$Y" -v G="$G" \
                -v C="$C" -v D="$D" -v B="$B" -v X="$X" '
    BEGIN {
      printf "  %s%-30s%s  %s%-18s%s  %s%s%s\n", \
        B,"SSID",X, B,"SECURITY",X, B,"CH",X
    }
    {
      ssid=$1; sec=$2; ch=$3
      if (sec ~ /none|open/)      sc = R
      else if (sec ~ /wpa3/)      sc = G
      else if (sec ~ /wpa2/)      sc = Y
      else                        sc = ""
      if (ssid == cur) { prefix = "★ "; line_c = C }
      else             { prefix = "  "; line_c = "" }
      printf "%s%s%-30s%s  %s%-18s%s  %s%s%s\n", \
        line_c, prefix, ssid, X, sc, sec, X, D, ch, X
    }
  '
}

_wifi_status() {
  local ssid ip gw sec dbm
  ssid=$(_wifi_current_ssid)
  ip=$(ipconfig getifaddr "$WIFI_IFACE" 2>/dev/null)
  gw=$(route -n get -ifscope "$WIFI_IFACE" default 2>/dev/null \
        | awk '/gateway:/ {print $2}')
  sec=$(_wifi_current_security)
  dbm=$(_wifi_current_signal_dbm)

  printf '%s %s\n' "$(_wifi_label SSID)"    "$(_c_bold "${ssid:-<disconnected>}")"
  printf '%s %s\n' "$(_wifi_label IP)"      "${ip:-<none>}"
  printf '%s %s\n' "$(_wifi_label Gateway)" "${gw:-<none>}"
  if [[ -n "$dbm" ]]; then
    printf '%s %s %s\n' "$(_wifi_label Signal)" \
      "$(_wifi_signal_bar "$dbm")" \
      "$(_c_dim "(${dbm} dBm)")"
  fi
  if _wifi_is_open_security "$sec"; then
    printf '%s %s %s\n' "$(_wifi_label Security)" \
      "$(_c_red '⚠ OPEN')" \
      "$(_c_dim '(unsecured)')"
  elif [[ -z "$sec" ]]; then
    printf '%s %s\n' "$(_wifi_label Security)" "$(_c_dim '<none>')"
  else
    printf '%s %s %s\n' "$(_wifi_label Security)" \
      "$(_wifi_security_colored "$sec")" \
      "$(_c_green '✓')"
  fi
}

_wifi_power() {
  _wifi_need networksetup || return 1
  networksetup -setairportpower "$WIFI_IFACE" "$1"
}

# ---- dispatcher --------------------------------------------------------------

wifi() {
  local _WIFI_COLOR=0
  [[ -t 1 ]] && _WIFI_COLOR=1
  local cmd="${1:-help}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
    connect) _wifi_connect "$@" ;;
    tether)  _wifi_tether ;;
    scan)    _wifi_scan ;;
    status)  _wifi_status ;;
    on)      _wifi_power on ;;
    off)     _wifi_power off ;;
    help|-h|--help) _wifi_help ;;
    *)
      echo "wifi: unknown subcommand '$cmd'" >&2
      _wifi_help >&2
      return 2
      ;;
  esac
}

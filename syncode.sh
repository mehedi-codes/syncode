#!/usr/bin/env bash
# ============================================================
#  syncode — sync settings + extensions to VS Code-family editors
#  Version: 1.0.0
# ============================================================
set -Eeuo pipefail

VERSION="1.0.0"

# Guard: must run under real bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "ERROR: syncode must be run with bash (not $0)" >&2
  exit 1
fi

# Guard: bash 4+ required (associative arrays, [[ ]])
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "ERROR: syncode requires bash 4 or newer (found $BASH_VERSION)" >&2
  echo "       macOS ships bash 3.2 by default — install via Homebrew: brew install bash" >&2
  exit 1
fi

# Safe script directory detection
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"

# ------------------------------------------------------------
#  Structured logging (stderr)
# ------------------------------------------------------------
log_info()  { printf '[INFO ] %s\n' "$*" >&2; }
log_warn()  { printf '[WARN ] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

# ------------------------------------------------------------
#  Flags
# ------------------------------------------------------------
DRY_RUN=false
REVERT=false

usage() {
  cat <<EOF
syncode — apply settings.json + extensions.json to any VS Code-family editor

$(cat <<'BANNER'
  ____                 _         ___
 / ___| _   _ _ __ ___| | ___   / _ \ _ __   ___ _   _ ___
 \___ \| | | | '__/ _ \ |/ _ \ | | | | '_ \ / _ \ | | / __|
  ___) | |_| | | |  __/ |  __/ | |_| | | | |  __/ |_| \__ \
 |____/ \__, |_|  \___|_|\___|  \___/|_| |_|\___|\__, |___/
        |___/                                     |___/
BANNER
)

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help      show this help and exit
    -v, --version   show version and exit
    -d, --dry-run   show the plan, change nothing
    -r, --revert    restore editors to factory defaults:
                    settings.json.bak -> settings.json if it exists,
                    else delete settings.json; uninstall syncode-installed
                    extensions. With -d: applies to all detected editors;
                    without -d: interactive selection like apply.

WHAT IT DOES:
    Detects installed editors (VS Code, VSCodium, Cursor, Windsurf, Positron),
    then for each: backs up settings.json, copies the repo settings, and
    installs missing extensions. Shows a toggle menu when multiple editors
    are detected.

EXAMPLES:
    bash $SCRIPT_NAME           apply to selected editors (menu)
    bash $SCRIPT_NAME -d        preview the plan, change nothing
    bash $SCRIPT_NAME -r        restore editors to factory defaults
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage 0 ;;
    -v|--version) printf 'syncode v%s\n' "$VERSION"; exit 0 ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    -r|--revert)  REVERT=true; shift ;;
    *)
      log_error "unknown option: $1"
      usage 1
      ;;
  esac
done

# ------------------------------------------------------------
#  Banner
# ------------------------------------------------------------
banner() {
  cat <<'EOF'

:'######:::'#######::'########::'########::'######::'##:::'##:'##::: ##::'######::
'##... ##:'##.... ##: ##.... ##: ##.....::'##... ##:. ##:'##:: ###:: ##:'##... ##:
 ##:::..:: ##:::: ##: ##:::: ##: ##::::::: ##:::..:::. ####::: ####: ##: ##:::..::
 ##::::::: ##:::: ##: ##:::: ##: ######:::. ######::::. ##:::: ## ## ##: ##:::::::
 ##::::::: ##:::: ##: ##:::: ##: ##...:::::..... ##:::: ##:::: ##. ####: ##:::::::
 ##::: ##: ##:::: ##: ##:::: ##: ##:::::::'##::: ##:::: ##:::: ##:. ###: ##::: ##:
. ######::. #######:: ########:: ########:. ######::::: ##:::: ##::. ##:. ######::
:......::::.......:::........:::........:::......::::::..:::::..::::..:::......:::

EOF
  printf '  v%s — sync settings + extensions to VS Code-family editors\n\n' "$VERSION"
}

# ------------------------------------------------------------
#  OS / platform detection
# ------------------------------------------------------------
OS_NAME=""
DATA_ROOT=""

case "$OSTYPE" in
  msys*|mingw*)
    OS_NAME="Windows (Git Bash)"
    DATA_ROOT="${APPDATA:-$HOME/AppData/Roaming}"
    ;;
  linux*)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || (uname -r | grep -qi microsoft); then
      # Running under WSL — target the Windows editor install.
      # stdin is redirected from /dev/null so powershell.exe cannot
      # consume the script's interactive input (read).
      OS_NAME="Windows (WSL)"
      if command -v powershell.exe &>/dev/null; then
        WIN_APPDATA="$(powershell.exe -NoProfile -Command '[Environment]::GetFolderPath("ApplicationData")' < /dev/null 2>/dev/null | tr -d '\r' | tail -n 1)"
      fi
      if [[ -n "${WIN_APPDATA:-}" ]]; then
        if command -v wslpath &>/dev/null; then
          DATA_ROOT="$(wslpath "$WIN_APPDATA")"
        else
          DATA_ROOT="$WIN_APPDATA"
        fi
      else
        log_error "cannot resolve Windows AppData from WSL"
        exit 1
      fi
    else
      OS_NAME="Linux"
      DATA_ROOT="$HOME/.config"
    fi
    ;;
  darwin*)
    OS_NAME="macOS"
    DATA_ROOT="$HOME/Library/Application Support"
    ;;
  *)
    log_error "unsupported platform: $OSTYPE"
    exit 1
    ;;
esac

# fork -> data dir name (relative to DATA_ROOT)
declare -A FORK_DIR=(
  [code]="Code"
  [codium]="VSCodium"
  [cursor]="Cursor"
  [windsurf]="Windsurf"
  [positron]="Positron"
)
FORK_ORDER=(code codium cursor windsurf positron)

settings_path() { printf '%s/%s/User/settings.json\n' "$DATA_ROOT" "${FORK_DIR[$1]}"; }
backup_path()   { printf '%s/%s/User/settings.json.bak\n' "$DATA_ROOT" "${FORK_DIR[$1]}"; }

# ------------------------------------------------------------
#  Parallel detection (background jobs, PIDs tracked)
# ------------------------------------------------------------
DETECT_TMP=""
detected=()

detect_forks() {
  local tmp
  tmp="$(mktemp -d)" || { log_error "failed to create temp dir"; exit 1; }
  DETECT_TMP="$tmp"

  local pids=()
  local fork
  for fork in "${FORK_ORDER[@]}"; do
    (
      local found=false
      if command -v "$fork" &>/dev/null; then
        found=true
      fi
      local dir="${DATA_ROOT}/${FORK_DIR[$fork]}/User"
      if [[ -d "$dir" ]]; then
        found=true
      fi
      if [[ "$found" == true ]]; then
        printf '%s\n' "$fork" > "$tmp/$fork"
      fi
    ) &
    pids+=("$!")
  done

  # Wait for all background processes (tolerate individual failures)
  local pid
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  for fork in "${FORK_ORDER[@]}"; do
    if [[ -f "$tmp/$fork" ]]; then
      detected+=("$fork")
    fi
  done
}

cleanup() {
  [[ -n "${DETECT_TMP:-}" ]] && rm -rf -- "$DETECT_TMP"
}
trap cleanup EXIT

# ------------------------------------------------------------
#  Extension helpers
# ------------------------------------------------------------
ext_ids() {
  # extract "publisher.name" entries from extensions.json
  grep -oE '"[a-z0-9-]+\.[a-z0-9-]+"' "$SCRIPT_DIR/extensions.json" | tr -d '"'
}

installed_exts() {
  local cli
  cli="$(command -v "$1" 2>/dev/null || true)"
  [[ -n "$cli" ]] || return 0
  "$cli" --list-extensions 2>/dev/null || true
}

# ------------------------------------------------------------
#  Plan / apply
# ------------------------------------------------------------
plan_fork() {
  local fork="$1" out=""
  if [[ "$REVERT" == true ]]; then
    if [[ -f "$(backup_path "$fork")" ]]; then
      out="restore settings.json from .bak"
    else
      out="delete settings.json (factory defaults)"
    fi
    out="$out, uninstall syncode extensions"
  else
    local sp bd
    sp="$(settings_path "$fork")"
    bd="$(backup_path "$fork")"
    if [[ -f "$sp" ]] && cmp -s "$sp" "$SCRIPT_DIR/settings.json"; then
      out="settings already in sync"
    else
      out="copy settings (backup -> .bak)"
      [[ -f "$bd" ]] && out="$out (overwrite .bak)"
    fi
    out="$out, install missing extensions"
  fi
  printf '  %-10s %s\n' "$fork" "$out"
}

apply_fork() {
  local fork="$1" sp bd cli
  sp="$(settings_path "$fork")"
  bd="$(backup_path "$fork")"

  mkdir -p "$(dirname -- "$sp")"

  if [[ "$REVERT" == true ]]; then
    if [[ -f "$bd" ]]; then
      mv -- "$bd" "$sp"
      echo "    $fork: restored settings.json from .bak"
    elif [[ -f "$sp" ]]; then
      rm -f -- "$sp"
      echo "    $fork: deleted settings.json (factory defaults)"
    else
      echo "    $fork: no settings.json to revert"
    fi
  else
    if [[ -f "$sp" ]] && cmp -s "$sp" "$SCRIPT_DIR/settings.json"; then
      echo "    $fork: settings already in sync"
    else
      [[ -f "$sp" ]] && cp -- "$sp" "$bd"
      cp -- "$SCRIPT_DIR/settings.json" "$sp"
      echo "    $fork: settings copied (backup -> .bak)"
    fi
  fi

  # extensions: install missing / uninstall syncode-installed
  cli="$(command -v "$fork" 2>/dev/null || true)"
  if [[ -n "$cli" ]]; then
    local want have id
    want="$(ext_ids)"
    have="$(installed_exts "$fork")"

    if [[ "$REVERT" == true ]]; then
      for id in $want; do
        if printf '%s\n' "$have" | grep -qx "$id"; then
          "$cli" --uninstall-extension "$id" >/dev/null 2>&1 || true
          echo "    $fork: uninstalled $id"
        fi
      done
    else
      for id in $want; do
        if ! printf '%s\n' "$have" | grep -qx "$id"; then
          if "$cli" --install-extension "$id" --force >/dev/null 2>&1; then
            echo "    $fork: installed $id"
          else
            log_warn "$fork: FAILED to install $id"
          fi
        fi
      done
    fi
  else
    echo "    $fork: no CLI found — settings handled, extensions skipped"
  fi
}

# ------------------------------------------------------------
#  Main
# ------------------------------------------------------------
banner
detect_forks

if [[ "${#detected[@]}" -eq 0 ]]; then
  log_error "no VS Code-family editor detected on $OS_NAME"
  exit 1
fi

# selection (menu only when not dry-run and more than one fork)
selected=("${detected[@]}")
if [[ "$DRY_RUN" == false ]] && [[ "${#detected[@]}" -gt 1 ]]; then
  declare -A checked=()
  f=""
  for f in "${detected[@]}"; do checked[$f]=1; done

  while true; do
    echo "Detected editors:"
    i=1
    for f in "${detected[@]}"; do
      mark=" "
      if [[ "${checked[$f]}" -eq 1 ]]; then
        mark="x"
      fi
      printf '  %d) [%s] %s\n' "$i" "$mark" "$f"
      i=$((i + 1))
    done
    echo "  a) select all     n) select none     <enter> = apply checked"
    read -r -p "toggle (e.g. 1 3), a=all, n=none, enter=apply: " input

    case "$input" in
      "") break ;;
      a|A) for f in "${detected[@]}"; do checked[$f]=1; done ;;
      n|N) for f in "${detected[@]}"; do checked[$f]=0; done ;;
      *)
        for num in $input; do
          if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#detected[@]}" ]]; then
            f="${detected[$((num - 1))]}"
            checked[$f]=$((1 - checked[$f]))
          else
            echo "  invalid: $num"
          fi
        done
        ;;
    esac
  done

  selected=()
  for f in "${detected[@]}"; do
    if [[ "${checked[$f]}" -eq 1 ]]; then
      selected+=("$f")
    fi
  done
fi

# plan
echo ""
echo "Plan:"
if [[ "$REVERT" == true ]]; then
  echo "  mode: revert to factory defaults"
fi
for f in "${detected[@]}"; do
  if printf '%s\n' "${selected[@]}" | grep -qx "$f"; then
    plan_fork "$f"
  else
    printf '  %-10s not selected\n' "$f"
  fi
done

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "DRY RUN — nothing applied."
  exit 0
fi

# confirm
read -r -p "Apply? [Y/n] " ans
case "$ans" in
  n|N) echo "aborted."; exit 0 ;;
  *)   : ;;
esac

# apply
echo ""
for f in "${selected[@]}"; do
  echo "$f:"
  apply_fork "$f"
  echo ""
done

echo "done."

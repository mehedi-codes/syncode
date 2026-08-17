#!/usr/bin/env bash
# ============================================================
#  syncode — sync your editor setup to every VS Code-family editor
#  Version: 1.1.0
# ============================================================
set -Eeuo pipefail

VERSION="1.1.0"
TOOL_NAME="syncode"
DESCRIPTION="sync your editor setup to every VS Code-family editor"

BANNER="$(cat <<'BANNER_EOF'
:'######:'##:::'##'##::: ##:'######::'#######:'########:'########:
'##... ##. ##:'##::###:: ##'##... ##'##.... ##:##.... ##:##.....::
 ##:::..::. ####:::####: ##:##:::..::##:::: ##:##:::: ##:##:::::::
. ######:::. ##::::## ## ##:##:::::::##:::: ##:##:::: ##:######:::
:..... ##::: ##::::##. ####:##:::::::##:::: ##:##:::: ##:##...::::
'##::: ##::: ##::::##:. ###:##::: ##:##:::: ##:##:::: ##:##:::::::
. ######:::: ##::::##::. ##. ######:. #######::########::########:
:......:::::..::::..::::..::......:::.......::........::........::
BANNER_EOF
)"

# Guard: must run under real bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "ERROR: $TOOL_NAME must be run with bash (not $0)" >&2
  exit 1
fi

# Guard: bash 4+ required (associative arrays, [[ ]])
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "ERROR: $TOOL_NAME requires bash 4 or newer (found $BASH_VERSION)" >&2
  exit 1
fi

# Safe script directory detection
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"

# Config dir: beside the script (install temp dir) or ../shared (repo checkout)
if [[ -f "$SCRIPT_DIR/settings.json" && -f "$SCRIPT_DIR/extensions.json" ]]; then
  CONFIG_DIR="$SCRIPT_DIR"
else
  CONFIG_DIR="$(cd -- "$SCRIPT_DIR/../shared" && pwd -P)"
fi

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

$BANNER

$TOOL_NAME v$VERSION — $DESCRIPTION

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help      show this help and exit
    -v, --version   show version and exit
    -d, --dry-run   show the plan, change nothing
    -r, --revert    restore editors to factory defaults:
                    settings.json.bak -> settings.json if it exists,
                    else delete settings.json; uninstall $TOOL_NAME-installed
                    extensions. With -d: applies to all detected editors;
                    without -d: interactive selection like apply.

WHAT IT DOES:
    Detects installed editors (VS Code, VSCodium),
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
    -h|--help)   usage 0 ;;
    -v|--version) printf '%s v%s\n' "$TOOL_NAME" "$VERSION"; exit 0 ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    -r|--revert) REVERT=true; shift ;;
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
  printf '\n%s\n\n' "$BANNER"
  printf '%s v%s — %s\n\n' "$TOOL_NAME" "$VERSION" "$DESCRIPTION"
}

# ------------------------------------------------------------
#  OS / platform detection (Linux only)
# ------------------------------------------------------------
DATA_ROOT=""

case "$OSTYPE" in
  linux*)
    DATA_ROOT="$HOME/.config"
    ;;
  *)
    log_error "unsupported platform: $OSTYPE (syncode.sh is Linux-only; Windows uses syncode.ps1)"
    exit 1
    ;;
esac

# fork -> data dir name (relative to DATA_ROOT)
declare -A FORK_DIR=(
  [code]="Code"
  [codium]="VSCodium"
)
FORK_ORDER=(code codium)

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
    ) < /dev/null &
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
  grep -oE '"[a-z0-9-]+\.[a-z0-9-]+"' "$CONFIG_DIR/extensions.json" | tr -d '"'
}

installed_exts() {
  local cli
  cli="$(command -v "$1" 2>/dev/null || true)"
  [[ -n "$cli" ]] || return 0
  "$cli" --list-extensions </dev/null 2>/dev/null || true
}

editor_version() {
  local cli v
  cli="$(command -v "$1" 2>/dev/null || true)"
  [[ -n "$cli" ]] || { printf '%s' "n/a"; return; }
  v="$("$cli" --version </dev/null 2>/dev/null | head -n1)"
  printf '%s' "${v:-n/a}"
}

missing_exts() {
  local want have id out=""
  want="$(ext_ids)"
  have="$(installed_exts "$1")"
  for id in $want; do
    if ! printf '%s\n' "$have" | grep -qx "$id"; then
      out="$out $id"
    fi
  done
  printf '%s' "${out# }"
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
    out="$out, uninstall $TOOL_NAME extensions"
  else
    local sp bd
    sp="$(settings_path "$fork")"
    bd="$(backup_path "$fork")"
    if [[ -f "$sp" ]] && cmp -s "$sp" "$CONFIG_DIR/settings.json"; then
      out="settings already in sync"
    else
      out="copy settings (backup -> .bak)"
      [[ -f "$bd" ]] && out="$out (overwrite .bak)"
    fi
    local missing cli
    cli="$(command -v "$fork" 2>/dev/null || true)"
    if [[ -n "$cli" ]]; then
      missing="$(missing_exts "$fork")"
      if [[ -n "$missing" ]]; then
        out="$out, install missing extensions: $missing"
      else
        out="$out, extensions up to date"
      fi
    else
      out="$out, no CLI found — extensions skipped"
    fi
  fi
  printf '%s' "$out"
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
    if [[ -f "$sp" ]] && cmp -s "$sp" "$CONFIG_DIR/settings.json"; then
      echo "    $fork: settings already in sync"
    else
      [[ -f "$sp" ]] && cp -- "$sp" "$bd"
      cp -- "$CONFIG_DIR/settings.json" "$sp"
      echo "    $fork: settings copied (backup -> .bak)"
    fi
  fi

  # extensions: install missing / uninstall syncode-installed
  cli="$(command -v "$fork" 2>/dev/null || true)"
  if [[ -n "$cli" ]]; then
    local id missing
    missing="$(missing_exts "$fork")"

    if [[ "$REVERT" == true ]]; then
      local want
      want="$(ext_ids)"
      for id in $want; do
        if printf '%s\n' "$(installed_exts "$fork")" | grep -qx "$id"; then
          "$cli" --uninstall-extension "$id" </dev/null >/dev/null 2>&1 || true
          echo "    $fork: uninstalled $id"
        fi
      done
    else
      for id in $missing; do
        if "$cli" --install-extension "$id" --force </dev/null >/dev/null 2>&1; then
          echo "    $fork: installed $id"
        else
          log_warn "$fork: FAILED to install $id"
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

# plan table
echo "Plan:"
if [[ "$REVERT" == true ]]; then
  echo "  mode: revert to factory defaults"
fi
printf '  %-10s %-12s %s\n' "name" "version" "status"
printf '  %-10s %-12s %s\n' "----" "-------" "------"
for f in "${FORK_ORDER[@]}"; do
  if printf '%s\n' "${detected[@]}" | grep -qx "$f"; then
    printf '  %-10s %-12s %s\n' "$f" "$(editor_version "$f")" "$(plan_fork "$f")"
  else
    printf '  %-10s %-12s %s\n' "$f" "n/a" "not installed"
  fi
done

echo ""

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
    input="${input%$'\r'}"

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

if [[ "$DRY_RUN" == true ]]; then
  echo "DRY RUN — nothing applied."
  exit 0
fi

if [[ "${#selected[@]}" -eq 0 ]]; then
  echo "nothing to apply."
  exit 0
fi

echo ""
# confirm
read -r -p "Apply? [Y/n] " ans || ans="n"
ans="${ans%$'\r'}"
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

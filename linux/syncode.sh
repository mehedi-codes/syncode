#!/usr/bin/env bash
# ============================================================
#  syncode - Sync and manage your VS Code and VSCodium editors
#  Version: 1.2.0
# ============================================================
set -Eeuo pipefail

VERSION="1.2.0"
TOOL_NAME="syncode"
DESCRIPTION="Sync and manage your VS Code and VSCodium editors"

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

$TOOL_NAME v$VERSION - $DESCRIPTION

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
    -i, --install [fork]    install latest stable (code/codium; default all)
    -u, --update [fork]     upgrade if installed version is older than latest
    -rm, --uninstall [fork] remove editor and its config dir
    -l, --list-versions    show installed vs latest versions, then exit

WHAT IT DOES:
    Detects installed editors (VS Code, VSCodium),
    then for each: backs up settings.json, copies the repo settings, and
    installs missing extensions. Shows a toggle menu when multiple editors
    are detected. With no flags, opens the interactive dashboard
    (pick editor, then install/update/config/reset/uninstall/help).

EXAMPLES:
    bash $SCRIPT_NAME           apply to selected editors (menu)
    bash $SCRIPT_NAME           interactive dashboard (no flags)
    bash $SCRIPT_NAME -d        preview the plan, change nothing
    bash $SCRIPT_NAME -r        restore editors to factory defaults
    bash $SCRIPT_NAME -l        show installed vs latest versions
    bash $SCRIPT_NAME -i codium install latest VSCodium
    bash $SCRIPT_NAME -u        update all editors
EOF
  exit "${1:-0}"
}

ACTION=""
ACTION_FORK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage 0 ;;
    -v|--version) printf '%s v%s\n' "$TOOL_NAME" "$VERSION"; exit 0 ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    -r|--revert) REVERT=true; shift ;;
    -i|--install) ACTION=install; shift
      [[ $# -gt 0 && "$1" != -* ]] && { ACTION_FORK="$1"; shift; } ;;
    -u|--update) ACTION=update; shift
      [[ $# -gt 0 && "$1" != -* ]] && { ACTION_FORK="$1"; shift; } ;;
    -rm|--uninstall) ACTION=uninstall; shift
      [[ $# -gt 0 && "$1" != -* ]] && { ACTION_FORK="$1"; shift; } ;;
    -l|--list-versions) ACTION=list-versions; shift ;;
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
  printf '%s v%s - %s\n\n' "$TOOL_NAME" "$VERSION" "$DESCRIPTION"
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
      out="$out, no CLI found - extensions skipped"
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
    echo "    $fork: no CLI found - settings handled, extensions skipped"
  fi
}

# ------------------------------------------------------------
#  Release-driven actions (install/update/uninstall) + dashboard
# ------------------------------------------------------------
source "$SCRIPT_DIR/release.sh"
source "$SCRIPT_DIR/version.sh"

declare -A LATEST_CACHE=()

# latest_for <fork> - echoes latest (or "unknown"), cached per session.
latest_for() {
  local fork="$1" v
  if [[ -n "${LATEST_CACHE[$fork]:-}" ]]; then
    printf '%s' "${LATEST_CACHE[$fork]}"
    return
  fi
  if v="$(release_latest "$fork" 2>/dev/null)"; then
    LATEST_CACHE[$fork]="$v"
  else
    v="unknown"
    LATEST_CACHE[$fork]="$v"
  fi
  printf '%s' "$v"
}

invalidate_latest() { unset "LATEST_CACHE[$1]"; }

# resolve_cli <fork> - PATH first, else known install-path binary
# (closes the fresh-install dead-end: install -> config in the same session).
resolve_cli() {
  local fork="$1" cli p
  cli="$(command -v "$fork" 2>/dev/null || true)"
  if [[ -n "$cli" ]]; then printf '%s' "$cli"; return 0; fi
  case "$fork" in
    code)
      p="/usr/bin/code"
      ;;
    codium)
      p="/usr/bin/codium"
      [[ -x "$HOME/.local/share/VSCodium/bin/codium" ]] && p="$HOME/.local/share/VSCodium/bin/codium"
      ;;
  esac
  [[ -x "$p" ]] && printf '%s' "$p"
  return 0
}

# show_list_versions - -l / --list-versions table
show_list_versions() {
  printf '  %-10s %-12s %s\n' name installed latest
  local f inst
  for f in "${FORK_ORDER[@]}"; do
    inst="$(get_installed_version "$f")"
    [[ -z "$inst" ]] && inst="-"
    printf '  %-10s %-12s %s\n' "$f" "$inst" "$(latest_for "$f")"
  done
}

# render_dashboard - one row per fork: name / installed / latest / settings / extensions
render_dashboard() {
  printf '  %-8s %-12s %-12s %-9s %s\n' name installed latest settings extensions
  local f inst latest settings ext missing cli
  for f in "${FORK_ORDER[@]}"; do
    inst="$(get_installed_version "$f")"
    [[ -z "$inst" ]] && inst="-"
    latest="$(latest_for "$f")"
    if [[ -f "$(settings_path "$f")" ]]; then
      if cmp -s "$(settings_path "$f")" "$CONFIG_DIR/settings.json"; then
        settings="synced"
      else
        settings="diverged"
      fi
    else
      settings="-"
    fi
    cli="$(resolve_cli "$f")"
    if [[ -n "$cli" ]]; then
      missing="$(missing_exts "$f")"
      if [[ -z "$missing" ]]; then
        ext="up to date"
      else
        set -- $missing
        ext="$# missing"
      fi
    else
      ext="n/a"
    fi
    printf '  %-8s %-12s %-12s %-9s %s\n' "$f" "$inst" "$latest" "$settings" "$ext"
  done
}

# install_editor <fork> [ver] - download (syncode temp name) + silent install.
# apt -> .deb, dnf/yum -> .rpm, else tarball -> ~/.local/share/<ForkDir>.
# "already installed" check lives at the call sites (dashboard / -i flag);
# update calls straight through so the Inno/pkg installers can upgrade in place.
install_editor() {
  local fork="$1" ver="$2" url tmp dest
  ver="${ver:-$(latest_for "$fork")}"
  [[ "$ver" == "unknown" ]] && { log_error "$fork: can't determine latest version"; return 1; }
  echo "  $fork: installing $ver ..."
  if command -v apt-get >/dev/null 2>&1; then
    url="$(release_installer_url "$fork" linux)"
    tmp="$(mktemp --suffix=.deb)"
    echo "  downloading deb ..."
    curl -fsSL --max-time 600 -o "$tmp" "${url//<ver>/$ver}" 2>/dev/null \
      || { log_error "$fork: download failed"; rm -f "$tmp"; return 1; }
    sudo apt-get install -y "$tmp" \
      || { log_error "$fork: install failed"; rm -f "$tmp"; return 1; }
    rm -f "$tmp"
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    url="$(release_installer_url "$fork" linuxRpm)"
    tmp="$(mktemp --suffix=.rpm)"
    echo "  downloading rpm ..."
    curl -fsSL --max-time 600 -o "$tmp" "${url//<ver>/$ver}" 2>/dev/null \
      || { log_error "$fork: download failed"; rm -f "$tmp"; return 1; }
    sudo dnf install -y "$tmp" \
      || { log_error "$fork: install failed"; rm -f "$tmp"; return 1; }
    rm -f "$tmp"
  else
    # tarball fallback (no package manager detected)
    url="$(release_installer_url "$fork" linuxTar)"
    dest="$HOME/.local/share/${FORK_DIR[$fork]}"
    mkdir -p "$dest"
    echo "  downloading tarball ..."
    curl -fsSL --max-time 600 -o "$HOME/.cache/syncode-${fork}.tar.gz" "${url//<ver>/$ver}" 2>/dev/null \
      || { log_error "$fork: download failed"; return 1; }
    tar -xzf "$HOME/.cache/syncode-${fork}.tar.gz" -C "$dest" --strip-components=1 \
      || { log_error "$fork: extract failed"; rm -f "$HOME/.cache/syncode-${fork}.tar.gz"; return 1; }
    rm -f "$HOME/.cache/syncode-${fork}.tar.gz"
  fi
  echo "  $fork installed"
}

# update_editor <fork> - upgrade if installed < latest; no-op if current.
update_editor() {
  local fork="$1" inst latest
  inst="$(get_installed_version "$fork")"
  latest="$(latest_for "$fork")"
  if [[ -z "$inst" ]]; then
    echo "  $fork not installed - use install"
    return 0
  fi
  if [[ "$latest" == "unknown" ]]; then
    if [[ "${RELEASE_RATE_LIMITED:-0}" == "1" ]]; then
      log_error "$fork: GitHub API rate limit hit - try later"
    else
      log_error "$fork: can't check for updates (network unavailable)"
    fi
    return 1
  fi
  if [[ "$(version_compare "$inst" "$latest")" -lt 0 ]]; then
    echo "  $fork: updating $inst -> $latest"
    install_editor "$fork" "$latest"
  else
    echo "  $fork: already latest ($inst)"
  fi
}

# uninstall_editor <fork> - pkg manager remove + config dir; tarball -> rm -rf.
uninstall_editor() {
  local fork="$1" pkg dir
  pkg="$(release_uninstall_name "$fork")"
  if command -v apt-get >/dev/null 2>&1 \
     && dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    sudo apt-get remove -y "$pkg" || true
  elif command -v dnf >/dev/null 2>&1 && rpm -q "$pkg" >/dev/null 2>&1; then
    sudo dnf remove -y "$pkg" || true
  fi
  dir="$HOME/.local/share/${FORK_DIR[$fork]}"
  [[ -d "$dir" ]] && rm -rf -- "$dir"
  rm -rf -- "$DATA_ROOT/${FORK_DIR[$fork]}"
  echo "  $fork removed"
}

# run_dashboard - interactive hub: pick editor, pick action, loop. q quits.
run_dashboard() {
  local line editor action
  while true; do
    echo ""
    render_dashboard
    echo ""
    read -r -p "pick editor (1=code 2=codium, q=quit): " line || line="q"
    line="${line%$'\r'}"
    case "$line" in
      q|Q) echo "bye."; exit 0 ;;
      code|codium) editor="$line" ;;
      1) editor="code" ;;
      2) editor="codium" ;;
      *) echo "invalid: $line"; continue ;;
    esac
    while true; do
      read -r -p "action for $editor (install/update/config/reset/uninstall/help, q=quit): " action \
        || action="q"
      action="${action%$'\r'}"
      case "$action" in
        q|Q) echo "bye."; exit 0 ;;
        install|update|config|reset|uninstall|help) break ;;
        *) echo "invalid: $action" ;;
      esac
    done
    case "$action" in
      help)
        echo "  install    install latest stable if not installed"
        echo "  update     upgrade if installed version is older than latest"
        echo "  config     copy settings (backup .bak) + install missing extensions"
        echo "  reset      restore factory defaults  (type \"reset\" to confirm)"
        echo "  uninstall  remove editor and its config dir  (type \"uninstall\" to confirm)"
        ;;
      config)
        apply_fork "$editor" || true
        ;;
      reset)
        read -r -p 'Type "reset" to confirm: ' line || line=""
        line="${line%$'\r'}"
        if [[ "$line" == "reset" ]]; then
          REVERT=true; apply_fork "$editor" || true; REVERT=false
        else
          echo "  not confirmed - skipped"
        fi
        ;;
      uninstall)
        read -r -p 'Type "uninstall" to confirm: ' line || line=""
        line="${line%$'\r'}"
        if [[ "$line" == "uninstall" ]]; then
          uninstall_editor "$editor" || true
          invalidate_latest "$editor"
        else
          echo "  not confirmed - skipped"
        fi
        ;;
      install)
        if [[ -n "$(get_installed_version "$editor")" ]]; then
          echo "  $editor already installed"
        else
          install_editor "$editor" || true
          invalidate_latest "$editor"
        fi
        ;;
      update)
        update_editor "$editor" || true
        ;;
    esac
  done
}

# ------------------------------------------------------------
#  Main
# ------------------------------------------------------------
banner
detect_forks

# action flags take priority (list-versions / install / update / uninstall)
if [[ -n "$ACTION" ]]; then
  local_action_forks=("${FORK_ORDER[@]}")
  if [[ -n "$ACTION_FORK" ]]; then
    case "$ACTION_FORK" in
      code|codium) local_action_forks=("$ACTION_FORK") ;;
      *) log_error "unknown fork: $ACTION_FORK"; exit 1 ;;
    esac
  fi
  if [[ "$ACTION" == "list-versions" ]]; then
    show_list_versions
    exit 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    printf '  %-10s %-12s %-12s %s\n' name installed latest action
    f=""; inst=""; latest=""; desc=""
    for f in "${local_action_forks[@]}"; do
      inst="$(get_installed_version "$f")"
      [[ -z "$inst" ]] && inst="none"
      latest="$(latest_for "$f")"
      case "$ACTION" in
        install)   desc="install $latest" ;;
        update)    desc=$([[ "$inst" == "none" ]] && echo "not installed (install first)" || echo "update to $latest") ;;
        uninstall) desc="remove editor + config" ;;
      esac
      printf '  %-10s %-12s %-12s %s\n' "$f" "$inst" "$latest" "$desc"
    done
    echo "DRY RUN - nothing applied."
    exit 0
  fi
  echo ""
  read -r -p "Apply? [Y/n] " ans || ans="n"
  ans="${ans%$'\r'}"
  case "$ans" in
    n|N) echo "aborted."; exit 0 ;;
    *)   : ;;
  esac
  echo ""
  for f in "${local_action_forks[@]}"; do
    echo "$f:"
    case "$ACTION" in
      install)
        if [[ -n "$(get_installed_version "$f")" ]]; then
          echo "  $f already installed"
        else
          install_editor "$f"
        fi
        ;;
      update)    update_editor "$f" ;;
      uninstall) uninstall_editor "$f" ;;
    esac
    echo ""
  done
  exit 0
fi

# no flags -> interactive dashboard
if [[ "$REVERT" == false && "$DRY_RUN" == false ]]; then
  run_dashboard
  exit 0
fi

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
  echo "DRY RUN - nothing applied."
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

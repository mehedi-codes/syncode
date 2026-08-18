#!/usr/bin/env bash
# ============================================================
#  syncode release module (Linux/bash)
#  Loads shared/releases.json (via ../shared), fetches latest versions,
#  builds installer URLs. Sourced by syncode.sh.
# ============================================================
set -Eeuo pipefail

CONFIG_DIR="${CONFIG_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../shared" && pwd -P)}"
RELEASES_FILE="$CONFIG_DIR/releases.json"

# release_get <fork> <sed-regex> — first captured value under the fork block.
# ponytail: releases.json has a fixed schema; the extraction is unambiguous
# because installer URLs are quoted strings while the uninstall object lines
# are `"win":  {` (brace, not quote) and so don't match URL patterns.
release_get() {
  local fork="$1" re="$2"
  sed -n "/\"$fork\": {/,/^  }/p" "$RELEASES_FILE" 2>/dev/null \
    | sed -n "s|$re|\1|p" \
    | head -n1
}

release_latest_api()     { release_get "$1" '.*"latestApi":[[:space:]]*"\([^"]*\)".*'; }
release_installer_url()  { release_get "$1" ".*\"$2\":[[:space:]]*\"\([^\"]*\)\".*"; }
release_uninstall_type() { release_get "$1" ".*\"$2\":[[:space:]]*{[[:space:]]*\"type\":[[:space:]]*\"\([^\"]*\)\".*"; }
release_uninstall_exe()  { release_get "$1" '.*"exe":[[:space:]]*"\([^"]*\)".*'; }
release_uninstall_name() { release_get "$1" '.*"name":[[:space:]]*"\([^"]*\)".*'; }
release_winget()         { release_get "$1" '.*"winget":[[:space:]]*"\([^"]*\)".*'; }

# release_url <fork> <platform> <ver> — installer URL with <ver> substituted.
release_url() { release_installer_url "$1" "$2" | sed "s|<ver>|$3|g"; }

# release_latest <fork> — echoes latest version; exit 1 on failure.
# Sets RELEASE_RATE_LIMITED=1 if codium hit the GitHub 403 rate limit.
release_latest() {
  local fork="$1" api code tmp
  RELEASE_RATE_LIMITED=0
  api="$(release_latest_api "$fork")"
  case "$fork" in
    code)
      RELEASE_LATEST="$(curl -fsSL --max-time 10 "$api" 2>/dev/null \
        | sed -n 's/^\["\([^"]*\)".*/\1/p')" || true
      ;;
    codium)
      tmp="$(mktemp)"
      code="$(curl -sS -o "$tmp" -D "$tmp.h" -A "syncode" -w '%{http_code}' \
              --max-time 10 "$api" 2>/dev/null)" \
        || { rm -f "$tmp" "$tmp.h"; return 1; }
      if [[ "$code" == "403" ]] && grep -qi '^x-ratelimit-remaining:[[:space:]]*0' "$tmp.h"; then
        RELEASE_RATE_LIMITED=1
        rm -f "$tmp" "$tmp.h"
        return 1
      fi
      if [[ "$code" != "200" ]]; then
        rm -f "$tmp" "$tmp.h"
        return 1
      fi
      RELEASE_LATEST="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$tmp" | head -n1)"
      rm -f "$tmp" "$tmp.h"
      ;;
    *)
      return 1
      ;;
  esac
  if [[ -n "${RELEASE_LATEST:-}" ]]; then
    echo "$RELEASE_LATEST"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------
#  Self-check (runs only when executed directly, not sourced)
# ------------------------------------------------------------
release_selfcheck() {
  local fail=0 got
  check() {
    local want="$1" got="$2" label="$3"
    if [[ "$got" != "$want" ]]; then
      echo "FAIL: $label = '$got', want '$want'" >&2
      fail=1
    fi
  }
  check "https://update.code.visualstudio.com/api/releases/stable" \
        "$(release_latest_api code)" code.latestApi
  check "https://update.code.visualstudio.com/<ver>/win32-x64-user/stable" \
        "$(release_installer_url code win)" code.installer.win
  check "https://update.code.visualstudio.com/<ver>/linux-deb-x64/stable" \
        "$(release_installer_url code linux)" code.installer.linux
  check "https://update.code.visualstudio.com/<ver>/linux-rpm-x64/stable" \
        "$(release_installer_url code linuxRpm)" code.installer.linuxRpm
  check "https://update.code.visualstudio.com/<ver>/linux-x64/stable" \
        "$(release_installer_url code linuxTar)" code.installer.linuxTar
  check "https://github.com/VSCodium/vscodium/releases/download/<ver>/VSCodiumUserSetup-x64-<ver>.exe" \
        "$(release_installer_url codium win)" codium.installer.win
  check "https://github.com/VSCodium/vscodium/releases/download/<ver>/codium_<ver>_amd64.deb" \
        "$(release_installer_url codium linux)" codium.installer.linux
  check "https://github.com/VSCodium/vscodium/releases/download/<ver>/codium-<ver>-el8.x86_64.rpm" \
        "$(release_installer_url codium linuxRpm)" codium.installer.linuxRpm
  check "https://github.com/VSCodium/vscodium/releases/download/<ver>/VSCodium-linux-x64-<ver>.tar.gz" \
        "$(release_installer_url codium linuxTar)" codium.installer.linuxTar
  check "inno" "$(release_uninstall_type code win)" code.uninstall.win.type
  check "pkg"  "$(release_uninstall_type code linux)" code.uninstall.linux.type
  check "unins000.exe" "$(release_uninstall_exe code)" code.uninstall.win.exe
  check "code"   "$(release_uninstall_name code)" code.uninstall.linux.name
  check "codium" "$(release_uninstall_name codium)" codium.uninstall.linux.name
  check "Microsoft.VisualStudioCode" "$(release_winget code)" code.winget
  check "VSCodium.VSCodium" "$(release_winget codium)" codium.winget
  check "https://update.code.visualstudio.com/1.133.0/win32-x64-user/stable" \
        "$(release_url code win 1.133.0)" code.url.substitution
  if (( fail == 0 )); then echo "release selfcheck: OK"; fi
  return "$fail"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  release_selfcheck
fi
#!/usr/bin/env bash
# ============================================================
#  syncode — one-time runner
#  Fetches the latest syncode.sh + config via curl (no git,
#  no cache) and runs it immediately from a temp directory.
#  Version: 1.0.0
# ============================================================
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/mehedi-codes/syncode/main"
FILES=(syncode.sh settings.json extensions.json)

# Guard: curl required (no git involved)
if ! command -v curl &>/dev/null; then
  echo "ERROR: curl is required to run syncode — install curl and retry" >&2
  exit 1
fi

# Guard: bash 4+ (syncode.sh needs it too)
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "ERROR: syncode requires bash 4 or newer (found $BASH_VERSION)" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# One curl call fetches all files in parallel into the temp dir
curl -fsSL \
  -o "$tmp/syncode.sh"      "$REPO_RAW/syncode.sh" \
  -o "$tmp/settings.json"   "$REPO_RAW/settings.json" \
  -o "$tmp/extensions.json" "$REPO_RAW/extensions.json"

# Run with the real terminal attached (stdin inherited — prompts work)
exec bash "$tmp/syncode.sh" "$@"
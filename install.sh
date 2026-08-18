#!/usr/bin/env bash
# ============================================================
#  syncode — one-time runner
#  Fetches the latest syncode.sh + config via curl (no git,
#  no cache) and runs it immediately from a temp directory.
#  Version: 1.0.0
# ============================================================
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/mehedi-codes/syncode/main"
FILES=(
  "src/linux/syncode.sh:syncode.sh"
  "src/shared/settings.json:settings.json"
  "src/shared/extensions.json:extensions.json"
  "src/shared/releases.json:releases.json"
)

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

tmp="$(mktemp -d .syncode.XXXXXX)"
trap 'rm -rf -- "$tmp"' EXIT

# One curl call fetches all files in parallel into the temp dir (flattened:
# syncode.sh expects configs beside it)
curl_args=()
for entry in "${FILES[@]}"; do
  src="${entry%%:*}"
  dst="${entry##*:}"
  curl_args+=(-o "$tmp/$dst" "$REPO_RAW/$src")
done
curl -fsSL "${curl_args[@]}"

# Run with the real terminal attached (stdin inherited — prompts work).
# Not exec: the EXIT trap below must fire to clean up the temp dir.
bash "$tmp/syncode.sh" "$@"
#!/usr/bin/env bash
# ============================================================
#  syncode version module (Linux/bash)
#  version_compare + installed-version detection.
#  Sourced by syncode.sh; self-checks when run directly.
# ============================================================
set -Eeuo pipefail

# version_compare A B -> echoes -1 / 0 / 1
# Integer segment-wise, tolerant of differing segment counts
# (e.g. 1.126.04524 vs 1.133.0). Only ever used within one fork.
version_compare() {
  local a="${1:-}" b="${2:-}"
  if [[ "$a" == "$b" ]]; then echo 0; return; fi
  if [[ -z "$a" ]]; then echo -1; return; fi
  if [[ -z "$b" ]]; then echo 1; return; fi
  local -a sa sb
  IFS=. read -ra sa <<< "$a"
  IFS=. read -ra sb <<< "$b"
  local n=$(( ${#sa[@]} < ${#sb[@]} ? ${#sa[@]} : ${#sb[@]} ))
  local i ia ib
  for ((i = 0; i < n; i++)); do
    ia=$((10#${sa[$i]}))
    ib=$((10#${sb[$i]}))
    if (( ia < ib )); then echo -1; return; fi
    if (( ia > ib )); then echo 1; return; fi
  done
  if (( ${#sa[@]} < ${#sb[@]} )); then echo -1
  elif (( ${#sa[@]} > ${#sb[@]} )); then echo 1
  else echo 0; fi
}

# get_installed_version <fork> -> echoes version or "" if not found.
# CLI on PATH first; else resources/app/package.json from known install paths.
get_installed_version() {
  local fork="$1" v p
  if command -v "$fork" >/dev/null 2>&1; then
    v="$(command "$fork" --version 2>/dev/null | head -n1)" || true
    if [[ -n "$v" ]]; then echo "$v"; return; fi
  fi
  case "$fork" in
    code)   p="/usr/share/code";;
    codium) p="/usr/share/codium"
            [[ -d "$HOME/.local/share/VSCodium" ]] && p="$HOME/.local/share/VSCodium";;
    *) return;;
  esac
  if [[ -f "$p/resources/app/package.json" ]]; then
    v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
          "$p/resources/app/package.json" | head -n1)"
    if [[ -n "$v" ]]; then echo "$v"; return; fi
  fi
  echo ""
}

# ------------------------------------------------------------
#  Self-check (runs only when executed directly, not sourced)
# ------------------------------------------------------------
version_selfcheck() {
  local fail=0 got
  check() {
    local want="$1" a="$2" b="$3"
    got="$(version_compare "$a" "$b")"
    if [[ "$got" != "$want" ]]; then
      echo "FAIL: version_compare($a, $b) = $got, want $want" >&2
      fail=1
    fi
  }
  check -1 1.126.04524 1.133.0
  check  1 1.10.0      1.9.0
  check  0 1.133.0     1.133.0
  check  0 1.126.04524 1.126.04524
  check -1 1.126.04524 1.126.04525
  check -1 1.133       1.133.0
  check  1 1.133.0     1.133
  check -1 ""          1.0.0
  check  1 1.0.0       ""
  check  0 ""          ""
  if (( fail == 0 )); then echo "version selfcheck: OK"; fi
  return "$fail"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  version_selfcheck
fi
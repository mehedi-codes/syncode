#!/usr/bin/env bash
# CI checks for the Linux port. Run from the repo root:
#   bash .github/ci/linux.sh
set -euo pipefail

# Repo root (this script lives in .github/ci/)
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "== bash syntax =="
bash -n linux/syncode.sh linux/version.sh linux/release.sh install.sh

echo "== release module self-check (no network) =="
bash linux/release.sh

echo "== sandbox dashboard smoke test (checkout layout, ../shared configs) =="
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/home/.config/Code/User" "$sandbox/home/.config/VSCodium/User" \
         "$sandbox/home/.config/zed" "$sandbox/home/.local/share/zed/extensions/installed/html"
cat > "$sandbox/bin/code" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo 1.2.3 ;;
  --list-extensions) echo "aaron-bond.better-comments"; echo "editorconfig.editorconfig" ;;
esac
EOF
cp "$sandbox/bin/code" "$sandbox/bin/codium"
cat > "$sandbox/bin/zed" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Zed 1.2.3" ;;
esac
EOF
chmod +x "$sandbox/bin/code" "$sandbox/bin/codium" "$sandbox/bin/zed"
cp shared/code/settings.json "$sandbox/home/.config/Code/User/settings.json"
echo '{"workbench.colorTheme":"Not Synced"}' > "$sandbox/home/.config/VSCodium/User/settings.json"
cp shared/zed/settings.json "$sandbox/home/.config/zed/settings.json"
out="$(printf 'q\n' | PATH="$sandbox/bin:$PATH" HOME="$sandbox/home" bash linux/syncode.sh)"
echo "$out"
grep -q "Pick an editor" <<< "$out"
grep -q "VSCode" <<< "$out"
grep -q "Zed" <<< "$out"
grep -q "bye." <<< "$out"

echo "== sandbox dashboard smoke test (flattened install layout, beside-script configs) =="
rm -rf "$sandbox"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/home/.config/Code/User" \
         "$sandbox/code" "$sandbox/codium" "$sandbox/zed"
cp linux/syncode.sh linux/version.sh linux/release.sh "$sandbox/"
cp shared/code/settings.json "$sandbox/code/settings.json"
cp shared/code/extensions.json "$sandbox/code/extensions.json"
cp shared/codium/settings.json "$sandbox/codium/settings.json"
cp shared/codium/extensions.json "$sandbox/codium/extensions.json"
cp shared/zed/settings.json "$sandbox/zed/settings.json"
cp shared/zed/extensions.json "$sandbox/zed/extensions.json"
cp shared/releases.json "$sandbox/"
cat > "$sandbox/bin/code" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo 1.2.3 ;;
  --list-extensions) echo "aaron-bond.better-comments" ;;
esac
EOF
cp "$sandbox/bin/code" "$sandbox/bin/codium"
cat > "$sandbox/bin/zed" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Zed 1.2.3" ;;
esac
EOF
chmod +x "$sandbox/bin/code" "$sandbox/bin/codium" "$sandbox/bin/zed"
out="$(printf 'q\n' | PATH="$sandbox/bin:$PATH" HOME="$sandbox/home" bash "$sandbox/syncode.sh")"
echo "$out"
grep -q "Pick an editor" <<< "$out"
grep -q "Zed" <<< "$out"
rm -rf "$sandbox"
trap - EXIT

echo "== extensions.json docs coverage =="
for f in shared/code/extensions.json shared/codium/extensions.json shared/zed/extensions.json; do
  if [[ "$f" == shared/zed/* ]]; then
    # zed IDs are dot-less, one per line alone on its line
    ids="$(sed -n 's/^[[:space:]]*"\([a-z0-9-]*\)",\{0,1\}[[:space:]]*$/\1/p' "$f")"
  else
    ids="$(grep -oE '"[a-z0-9-]+\.[a-z0-9-]+"' "$f" | tr -d '"')"
  fi
  for id in $ids; do
    grep -qF "$id" shared/extensions.md || { echo "missing doc for $id ($f)"; exit 1; }
  done
done

echo "== port lockstep (version string) =="
bash_ver="$(sed -n 's/^VERSION="\(.*\)"/\1/p' linux/syncode.sh)"
ps_ver="$(sed -n 's/^\$VERSION_STR = "\(.*\)"/\1/p' windows/syncode.ps1)"
echo "bash=$bash_ver ps=$ps_ver"
test "$bash_ver" = "$ps_ver"

echo "ALL LINUX CHECKS PASSED"
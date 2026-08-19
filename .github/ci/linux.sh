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
mkdir -p "$sandbox/bin" "$sandbox/home/.config/Code/User" "$sandbox/home/.config/VSCodium/User"
cat > "$sandbox/bin/code" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo 1.2.3 ;;
  --list-extensions) echo "aaron-bond.better-comments"; echo "editorconfig.editorconfig" ;;
esac
EOF
cp "$sandbox/bin/code" "$sandbox/bin/codium"
chmod +x "$sandbox/bin/code" "$sandbox/bin/codium"
cp shared/settings.json "$sandbox/home/.config/Code/User/settings.json"
echo '{"workbench.colorTheme":"Not Synced"}' > "$sandbox/home/.config/VSCodium/User/settings.json"
out="$(printf 'q\n' | PATH="$sandbox/bin:$PATH" HOME="$sandbox/home" bash linux/syncode.sh)"
echo "$out"
grep -q "Pick an editor" <<< "$out"
grep -q "VSCode" <<< "$out"
grep -q "bye." <<< "$out"

echo "== sandbox dashboard smoke test (flattened install layout, beside-script configs) =="
rm -rf "$sandbox"
mkdir -p "$sandbox/bin" "$sandbox/home/.config/Code/User"
cp linux/syncode.sh linux/version.sh linux/release.sh \
   shared/settings.json shared/extensions.json shared/releases.json "$sandbox/"
cat > "$sandbox/bin/code" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo 1.2.3 ;;
  --list-extensions) echo "aaron-bond.better-comments" ;;
esac
EOF
cp "$sandbox/bin/code" "$sandbox/bin/codium"
chmod +x "$sandbox/bin/code" "$sandbox/bin/codium"
out="$(printf 'q\n' | PATH="$sandbox/bin:$PATH" HOME="$sandbox/home" bash "$sandbox/syncode.sh")"
echo "$out"
grep -q "Pick an editor" <<< "$out"
rm -rf "$sandbox"
trap - EXIT

echo "== extensions.json docs coverage =="
for id in $(grep -oE '"[a-z0-9-]+\.[a-z0-9-]+"' shared/extensions.json | tr -d '"'); do
  grep -qF "$id" shared/extensions.md || { echo "missing doc for $id"; exit 1; }
done

echo "== port lockstep (version string) =="
bash_ver="$(sed -n 's/^VERSION="\(.*\)"/\1/p' linux/syncode.sh)"
ps_ver="$(sed -n 's/^\$VERSION_STR = "\(.*\)"/\1/p' windows/syncode.ps1)"
echo "bash=$bash_ver ps=$ps_ver"
test "$bash_ver" = "$ps_ver"

echo "ALL LINUX CHECKS PASSED"
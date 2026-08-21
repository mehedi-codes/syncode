#!/usr/bin/env bash
# LOCAL smoke test only: runs a patched copy of syncode.sh that accepts
# msys (Git Bash on Windows) so the dashboard logic can be exercised here.
# Real CI (.github/ci/linux.sh) still tests the unpatched script on ubuntu.
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed 's/^  linux\*)/  linux*|msys*)/' linux/syncode.sh > "$tmp/syncode.sh"
cp linux/version.sh linux/release.sh "$tmp/"
mkdir -p "$tmp/code" "$tmp/codium" "$tmp/zed"
cp shared/code/settings.json shared/code/extensions.json "$tmp/code/"
cp shared/codium/settings.json shared/codium/extensions.json "$tmp/codium/"
cp shared/zed/settings.json shared/zed/extensions.json "$tmp/zed/"
cp shared/releases.json "$tmp/"

echo "== checkout layout =="
sandbox="$(mktemp -d)"
mkdir -p "$sandbox/bin" \
         "$sandbox/home/.config/Code/User" \
         "$sandbox/home/.config/VSCodium/User" \
         "$sandbox/home/.config/zed" \
         "$sandbox/home/.local/share/zed/extensions/installed/html"
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
chmod +x "$sandbox/bin/"*
cp shared/code/settings.json "$sandbox/home/.config/Code/User/settings.json"
echo '{"workbench.colorTheme":"Not Synced"}' > "$sandbox/home/.config/VSCodium/User/settings.json"
cp shared/zed/settings.json "$sandbox/home/.config/zed/settings.json"
out="$(printf 'q\n' | PATH="$sandbox/bin:$PATH" HOME="$sandbox/home" bash "$tmp/syncode.sh")"
echo "$out"
grep -q "Pick an editor" <<< "$out" || { echo "FAIL editor picker"; exit 1; }
grep -q "VSCode"        <<< "$out" || { echo "FAIL vscode row"; exit 1; }
grep -q "Zed"           <<< "$out" || { echo "FAIL zed row"; exit 1; }
grep -q "bye."          <<< "$out" || { echo "FAIL quit"; exit 1; }
rm -rf "$sandbox"
echo "checkout layout OK"

echo "== flattened layout =="
sandbox="$(mktemp -d)"
mkdir -p "$sandbox/bin" "$sandbox/home/.config/Code/User" \
         "$sandbox/code" "$sandbox/codium" "$sandbox/zed"
cp "$tmp/syncode.sh" "$tmp/version.sh" "$tmp/release.sh" "$sandbox/"
cp "$tmp/code/"*  "$sandbox/code/"
cp "$tmp/codium/"* "$sandbox/codium/"
cp "$tmp/zed/"*   "$sandbox/zed/"
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
chmod +x "$sandbox/bin/"*
out="$(printf 'q\n' | PATH="$sandbox/bin:$PATH" HOME="$sandbox/home" bash "$sandbox/syncode.sh")"
echo "$out"
grep -q "Pick an editor" <<< "$out" || { echo "FAIL editor picker"; exit 1; }
grep -q "Zed"            <<< "$out" || { echo "FAIL zed row"; exit 1; }
rm -rf "$sandbox"
echo "flattened layout OK"

echo "== extensions.md coverage =="
for f in shared/code/extensions.json shared/codium/extensions.json shared/zed/extensions.json; do
  if [[ "$f" == shared/zed/* ]]; then
    ids="$(sed -n 's/^[[:space:]]*"\([a-z0-9-]*\)",\{0,1\}[[:space:]]*$/\1/p' "$f")"
  else
    ids="$(grep -oE '"[a-z0-9-]+\.[a-z0-9-]+"' "$f" | tr -d '"')"
  fi
  for id in $ids; do
    grep -qF "$id" shared/extensions.md || { echo "missing doc for $id ($f)"; exit 1; }
  done
done
echo "coverage OK"

echo "== version lockstep =="
bash_ver="$(sed -n 's/^VERSION="\(.*\)"/\1/p' linux/syncode.sh)"
ps_ver="$(sed -n 's/^\$VERSION_STR = "\(.*\)"/\1/p' windows/syncode.ps1)"
echo "bash=$bash_ver ps=$ps_ver"
test "$bash_ver" = "$ps_ver" || { echo "FAIL lockstep"; exit 1; }

echo "ALL LOCAL LINUX CHECKS PASSED"

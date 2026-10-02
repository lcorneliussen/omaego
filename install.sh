#!/usr/bin/env bash
# Install omaego: link the binaries, migrate config, register as default
# browser, and relink native messaging hosts into every ego.
#
# Idempotent. Anything it would overwrite that is not already one of our
# symlinks is backed up to <file>.bak.<timestamp> first.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/omaego"
PLUGINS="$HOME/.config/omarchy/plugins"
STAMP=$(date +%s)

say() { printf '  %s\n' "$*"; }

link() { # link <target> <linkname>
  local target=$1 name=$2
  if [ -L "$name" ] && [ "$(readlink -f "$name")" = "$(readlink -f "$target")" ]; then
    say "ok      $name"; return
  fi
  if [ -e "$name" ] || [ -L "$name" ]; then
    mv "$name" "$name.bak.$STAMP"; say "backed up $name -> $name.bak.$STAMP"
  fi
  mkdir -p "$(dirname "$name")"
  ln -s "$target" "$name"; say "linked  $name"
}

echo "omaego install"
mkdir -p "$BIN" "$APPS" "$CFG"

echo "binaries:"
link "$REPO/bin/omaego"        "$BIN/omaego"
link "$REPO/bin/omaego-webapp" "$BIN/omaego-webapp"
# Compatibility: launchers and .desktop files written against the older names
# keep working. omaego-webapp still accepts --profile= as well as --ego=.
link "$BIN/omaego"             "$BIN/urlrouter"
link "$BIN/omaego-webapp"      "$BIN/chrome-webapp"

echo "config:"
if [ ! -f "$CFG/rules.toml" ]; then
  if [ -f "$HOME/.config/urlrouter/rules.toml" ]; then
    cp "$HOME/.config/urlrouter/rules.toml" "$CFG/rules.toml"
    say "migrated rules.toml from ~/.config/urlrouter/"
  else
    cp "$REPO/examples/rules.toml" "$CFG/rules.toml"
    say "seeded rules.toml from examples/"
  fi
else
  say "ok      $CFG/rules.toml"
fi

echo "desktop entries:"
sed "s#__BIN__#$BIN#g" "$REPO/share/applications/chromium.desktop" > "$APPS/chromium.desktop"
say "wrote   $APPS/chromium.desktop  (omarchy-launch-webapp fallback shim)"
OMAEGO_BIN="$BIN/omaego" "$BIN/omaego" sync >/dev/null
say "wrote   omaego.desktop, google-chrome.desktop, one per ego"
update-desktop-database "$APPS" 2>/dev/null || true

echo "default browser:"
xdg-settings set default-web-browser omaego.desktop 2>/dev/null || true
xdg-mime default omaego.desktop x-scheme-handler/http x-scheme-handler/https text/html
say "now     $(xdg-settings get default-web-browser)"

if [ "${1:-}" = "--with-plugin" ]; then
  echo "omarchy shell plugin:"
  id=$(python3 -c "import json;print(json.load(open('$REPO/plugin/manifest.json'))['id'])")
  mkdir -p "$PLUGINS"
  # The shell refuses symlinks inside a plugin folder, so this one is copied.
  rm -rf "${PLUGINS:?}/$id"
  cp -r "$REPO/plugin" "$PLUGINS/$id"
  say "installed $PLUGINS/$id"
  say "enable with: omarchy plugin enable $id right"
fi

echo
echo "done. try:  omaego list    omaego space    omaego --help"

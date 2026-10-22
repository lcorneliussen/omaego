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
link "$REPO/bin/omaego-remote" "$BIN/omaego-remote"
# Compatibility shims for installs that predate the rename, off by default so a
# fresh install leaves nothing duplicated. omaego-webapp accepts --profile= as
# well as --ego= either way, so existing launchers keep working once repointed.
if [ "${OMAEGO_COMPAT:-0}" = "1" ]; then
  link "$BIN/omaego"           "$BIN/urlrouter"
  link "$BIN/omaego-webapp"    "$BIN/chrome-webapp"
fi

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
# Must run before omaego becomes the default browser: this is where it reads
# which browser omarchy had as default, and keeps it as the engine.
OMAEGO_BIN="$BIN/omaego" "$BIN/omaego" sync >/dev/null
say "engine  $("$BIN/omaego" engine)"
say "wrote   omaego.desktop, chromium.desktop (omarchy-launch-webapp shim), one per ego"
update-desktop-database "$APPS" 2>/dev/null || true

echo "default browser:"
xdg-settings set default-web-browser omaego.desktop 2>/dev/null || true
xdg-mime default omaego.desktop x-scheme-handler/http x-scheme-handler/https text/html
say "now     $(xdg-settings get default-web-browser)"

echo "menu:"
# The picker and every prompt go through a menu. Without one, "New ego" and
# "which ego for this link?" cannot ask anything.
if command -v omarchy-menu-select >/dev/null && command -v omarchy-menu-input >/dev/null; then
  say "ok      Omarchy's own menu"
elif command -v walker >/dev/null; then
  say "ok      walker"
else
  say "MISSING - the ego picker, \"New ego\" and every prompt need Omarchy's own"
  say "    menu (omarchy-menu-select, Omarchy 4) or walker"
fi

if [ "${1:-}" = "--with-plugin" ]; then
  echo "bar widget:"
  # The widget is its own repository, installed the way omarchy installs any
  # plugin rather than by copying files around.
  if omarchy plugin add https://github.com/lcorneliussen/omaego-bar.git --enable --yes; then
    say "installed and enabled io.github.lcorneliussen.omaego"
    say "run 'omarchy restart shell' - a hot reload will not place a new widget"
  else
    say "could not add the widget; install it later with:"
    say "  omarchy plugin add https://github.com/lcorneliussen/omaego-bar.git --enable"
  fi
fi

echo
echo "done. try:  omaego list    omaego space    omaego --help"

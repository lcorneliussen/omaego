#!/usr/bin/env bash
# Produce the README's images - docs/media/*.{png,gif} - from a scripted run in
# a contained Omarchy desktop (omabox), never from the author's own session.
#
# The box is seeded with the invented egos Acme / Personal / Work, and every
# page shown in a browser is a local mock served under example.com, so nothing
# real can appear in a published image. Rerun it after a UI change.
#
#   scripts/readme-media.sh [--keep]     --keep leaves the box up for poking at
#
# Needs omabox, ffmpeg, magick, Google Chrome, and the omaego-bar checkout
# (OMAEGO_BAR, default ../omaego-bar). The web-app catalogue icons are fetched
# from the internet, as `omaego app add` does.
set -euo pipefail

CLI=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BAR=${OMAEGO_BAR:-$CLI/../omaego-bar}
OUT=$CLI/docs/media
BOX=omaego-readme
WIDGET=io.github.lcorneliussen.omaego
FRAMES=$(mktemp -d)
KEEP=${1:-}
trap '[ "$KEEP" = "--keep" ] || omabox -b "$BOX" down >/dev/null 2>&1 || true; rm -rf "$FRAMES"' EXIT

for c in omabox ffmpeg magick; do
  command -v $c >/dev/null || { echo "$c is required" >&2; exit 1; }
done
[ -f "$BAR/BarWidget.qml" ] || { echo "set OMAEGO_BAR to the omaego-bar checkout" >&2; exit 1; }
BAR=$(cd "$BAR" && pwd)
mkdir -p "$OUT"

ob() { omabox -b "$BOX" "$@"; }
settle() { ob wait still --timeout 6 >/dev/null 2>&1 || true; }
shot() { settle; ob shot -g "${2:-0,0 1920x1080}" -o "$1" >/dev/null 2>&1; }
panel() { ob run -- omarchy-shell shell "$1" "$WIDGET" >/dev/null; settle; }

# frames to a GIF: gif OUT CROP WIDTH FILE:SECONDS...
gif() {
  local out=$1 crop=$2 w=$3 list=$FRAMES/list.txt fd; shift 3
  : > "$list"
  for fd in "$@"; do printf "file '%s'\nduration %s\n" "${fd%%:*}" "${fd##*:}" >> "$list"; done
  printf "file '%s'\n" "${fd%%:*}" >> "$list"   # concat drops the last duration otherwise
  ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" -fps_mode vfr -vf \
    "crop=$crop,scale=$w:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=full[p];[b][p]paletteuse=dither=none" \
    "$out"
}

echo "==> box"
ob down >/dev/null 2>&1 || true
# Chrome lives under /opt, which a box does not see unless bound in
ob up --plugin "$BAR" --ro-bind "$CLI" --ro-bind /opt/google >/dev/null
H=$(ob path)/home
# a box copies the author's current theme; pin one so reruns look the same
ob run -- omarchy-theme-set "${OMAEGO_THEME:-tokyo-night}" >/dev/null 2>&1

echo "==> egos, rules, mock pages"
P=$H/.local/share/chrome-profiles
mkdir -p "$P"/{work,personal,acme} "$H/.config/omaego" "$H/.local/bin" "$H/mock"
printf 'Work\n'     > "$P/work/.profile-name"
printf 'Personal\n' > "$P/personal/.profile-name"
printf 'Acme\n'     > "$P/acme/.profile-name"
printf 'work\n'     > "$P/.default"
cat > "$H/.config/omaego/rules.toml" <<'RULES'
[[rule]]
url = "https://git.example.com/acme/*"
profile = "Acme"
[[rule]]
url = "https://acme.atlassian.net/*"
profile = "Acme"
[[rule]]
url = "https://github.com/your-handle/*"
profile = "Personal"
[[rule]]
url = "https://*zoom.us/j/*"
app = true
RULES
python3 - "$H" "$CLI" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])/".config/omarchy/shell.json"
d = json.loads(p.read_text())
for sec in d["bar"]["layout"].values():
    for e in sec:
        if isinstance(e, dict) and e.get("id", "").endswith("omaego"):
            e["command"] = f"{sys.argv[2]}/bin/omaego"
p.write_text(json.dumps(d, indent=2))
PY

# Every page a browser shows is one of these, served by Host header. Chrome is
# wrapped (first on the box's PATH) to resolve the demo hosts to that server and
# to stay quiet about the flag and about plain http.
cat > "$H/.local/bin/google-chrome-stable" <<'SH'
#!/bin/bash
exec /opt/google/chrome/google-chrome --test-type \
  --disable-features=HttpsUpgrades,HttpsFirstModeV2ForEngagedSites,HttpsFirstBalancedModeAutoEnable \
  '--host-resolver-rules=MAP *.example.com 127.0.0.1:47811, MAP acme.sharepoint.com 127.0.0.1:47811' "$@"
SH
chmod +x "$H/.local/bin/google-chrome-stable"
cat > "$H/mock/serve.py" <<'PY'
import http.server, pathlib
D = pathlib.Path(__file__).parent
MAP = {"docs.example.com": "work", "git.example.com": "acme",
       "notes.example.com": "personal", "acme.sharepoint.com": "files"}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        f = D / f"{MAP.get(self.headers.get('Host', '').split(':')[0], 'none')}.html"
        body = f.read_bytes() if f.exists() else b"<!doctype html><title>example.com</title>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", 47811), H).serve_forever()
PY
page() { # file title accent header body
  cat > "$H/mock/$1.html" <<EOF
<!doctype html><meta charset=utf-8><title>$2</title>
<style>body{margin:0;font:15px/1.5 system-ui,sans-serif;background:#f6f7f9;color:#1d2330}
header{background:$3;color:#fff;padding:14px 28px;font-weight:600;letter-spacing:.02em}
main{max-width:760px;margin:32px auto;padding:0 24px}h1{font-size:24px;margin:0 0 6px}
.m{color:#6b7280;margin-bottom:22px}.c,.r{background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:16px 20px;margin:12px 0}
.c b{display:block}.t{display:inline-block;font-size:12px;padding:2px 8px;border-radius:99px;background:#eef;color:#334;margin-top:6px}
.r{display:flex;justify-content:space-between;padding:12px 18px;margin:8px 0}.r span{color:#6b7280}</style>
<header>$4</header><main>$5</main>
EOF
}
page work "Q4 planning · Docs" "#2563eb" "docs.example.com" '<h1>Q4 planning</h1><div class=m>Shared with the team · edited 5 minutes ago</div><div class=c><b>Goals</b>Ship the new onboarding flow · cut p95 latency by a third</div><div class=c><b>Milestones</b>Beta in week 44, general availability in week 49</div><div class=c><b>Open questions</b>Who owns the migration runbook?<br><span class=t>3 comments</span></div>'
page acme "payments-service · Merge request !482" "#c2410c" "git.example.com/acme" '<h1>Retry failed webhooks with backoff</h1><div class=m>payments-service · !482 · opened 2 hours ago</div><div class=c><b>Pipeline passed</b>142 tests · 3m 12s<br><span class=t>ready to merge</span></div><div class=c><b>2 approvals</b>Reviewed from the Acme accounts.</div><div class=c><b>Changes</b>src/webhooks/retry.py · tests/test_retry.py</div>'
page personal "Sourdough, take three · Notes" "#15803d" "notes.example.com" '<h1>Sourdough, take three</h1><div class=m>Sunday</div><div class=c><b>Levain</b>50 g starter, 50 g flour, 50 g water · 6 hours</div><div class=c><b>Dough</b>450 g flour, 330 g water, 10 g salt</div><div class=c><b>Bake</b>250 °C lid on for 20 minutes, then 25 minutes open</div>'
page files "Finance · Shared documents" "#c2410c" "Acme · Finance" '<h1>Shared documents</h1><div class=r>Budget 2027.xlsx<span>yesterday</span></div><div class=r>Vendor contracts<span>3 days ago</span></div><div class=r>Board deck Q3.pptx<span>last week</span></div>'
ob run -d -q -- python3 /home/sbx/mock/serve.py
ob wait cmd --timeout 10 -- python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:47811/")' >/dev/null

echo "==> web apps (fetches their icons)"
ob run -- bash -c "export PATH=$CLI/bin:\$PATH
  omaego app add work outlook teams
  omaego app add acme outlook teams slack
  omaego app add personal gmail gcal
  omaego app catalog --fetch" >/dev/null 2>&1   # the add-app picker's icons
ob restart-shell >/dev/null

echo "==> one ego on workspace 2, two sharing workspace 1"
launch() {
  ob run -d -q -- "$CLI/bin/omaego" launch "$1" "$2"
  ob wait window "class:chrome-$1" --timeout 30 >/dev/null
}
ob hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })' >/dev/null
launch personal http://notes.example.com/sourdough
ob hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })' >/dev/null
launch work http://docs.example.com/q4-planning
launch acme http://git.example.com/acme/payments-service/-/merge_requests/482
ob pointer -- move 1400 900
ob run -- omarchy-notification-dismiss omaego >/dev/null   # the add-app ones

echo "==> hero: the panel open, every window outlined in its ego's colour"
panel summon
shot "$FRAMES/hero.png"
magick "$FRAMES/hero.png" -crop 1920x720+0+0 +repage -resize 1600x -strip "$OUT/hero.png"
panel hide

echo "==> badges"
( cd "$H/.local/share/icons/hicolor/256x256/apps"
  magick -background '#1a1b26' outlook-work.png outlook-acme.png teams-work.png \
    teams-acme.png slack-acme.png gmail-personal.png calendar-personal.png \
    -resize 150x150 -gravity center -extent 184x184 +append \
    -bordercolor '#1a1b26' -border 8 -strip "$OUT/badges.png" )

echo "==> a link that names an account"
ob pointer -- move 1900 1000
shot "$FRAMES/r0.png"
ob run -d -q -- "$CLI/bin/omaego" http://acme.sharepoint.com/sites/finance
ob wait layer walker --timeout 10 >/dev/null
shot "$FRAMES/r1.png"
ob keys --wait Return >/dev/null              # Acme
shot "$FRAMES/r2.png"
ob keys Return >/dev/null                     # Always open … in Acme
ob wait window 'title:Shared documents' --timeout 20 >/dev/null
shot "$FRAMES/r3.png"
panel summon
shot "$FRAMES/r4.png"
panel hide
gif "$OUT/route.gif" 1920:1080:0:0 1280 \
  "$FRAMES/r0.png:1.2" "$FRAMES/r1.png:2.2" "$FRAMES/r2.png:2.2" \
  "$FRAMES/r3.png:2.0" "$FRAMES/r4.png:3.8"

echo "==> adding a web app from the panel"
G="0,0 1000x500"
ob pointer -- move 1400 900
panel summon
shot "$FRAMES/a0.png" "$G"
ob click --steps 15 75 219 >/dev/null         # "+ Add app" on the Acme card
ob pointer -- move 1400 900
shot "$FRAMES/a1.png" "$G"
ob keys --wait -t f >/dev/null; shot "$FRAMES/a2.png" "$G"
ob keys --wait -t i >/dev/null; shot "$FRAMES/a3.png" "$G"
ob keys --wait -t g >/dev/null; shot "$FRAMES/a4.png" "$G"
ob keys Return >/dev/null
ob wait cmd --timeout 60 -- test -e "/home/sbx/.local/share/applications/Figma Acme.desktop" >/dev/null
shot "$FRAMES/a5.png" "$G"
# the card lists what `omaego panel` reports, which lags the .desktop file
ob wait cmd --timeout 30 -- bash -c "'$CLI/bin/omaego' panel | grep -q 'Figma'" >/dev/null
panel summon
shot "$FRAMES/a6.png" "$G"
gif "$OUT/add-app.gif" 1000:500:0:0 1000 \
  "$FRAMES/a0.png:1.5" "$FRAMES/a1.png:1.6" "$FRAMES/a2.png:0.5" "$FRAMES/a3.png:0.5" \
  "$FRAMES/a4.png:1.7" "$FRAMES/a5.png:0.9" "$FRAMES/a6.png:3.8"

echo "==> wrote"
for f in "$OUT"/*; do magick identify -format "    %f %wx%h %b\n" "$f[0]"; done

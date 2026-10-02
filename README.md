# omaego

Keep work, private and customer contexts apart in one browser — without logging
in and out of entirely different accounts.

An **ego** is one Chrome `--user-data-dir`: its own process, window class, cookie
jar, extensions and sync account. You run several at once. A link opens in the
ego that owns the **workspace you are on**, and never drags you to another
desktop to do it.

```
omaego list                     # the egos you have
omaego space                    # which ego owns this workspace
omaego add "Acme"               # a new ego
omaego <url>                    # what the desktop entry calls
```

There is deliberately **no "active ego"**. An ego is not a mode you switch the
system into; it is an identity that happens to have windows on a workspace. A
workspace usually belongs to one ego, and links resolve inside the workspace
they were clicked from.

## How a link is routed

1. **A rule in `~/.config/omaego/rules.toml`** → that ego, forced.
2. **A browser window of some ego already on this workspace** → reuse it,
   as a tab.
3. **Otherwise** → ask, with a picker of your egos.

A web-app window (Teams, Outlook, Chat) counts for step 2 as a *hint* about
which ego is here, but never receives the link: Chrome cannot put a tab in an
`--app` window and silently opens a whole new browser window instead.

```toml
[[rule]]
url = "https://bitbucket.org/acme/*"        # glob; '*' spans anything
profile = "Work"

[[rule]]                                     # Zoom: rewrite, and open as an app window
url = "https://*zoom.us/j/*"
rewrite = ["^https?://[^/]*zoom\\.us/j/(\\d+)([?#].*)?$", "https://app.zoom.us/wc/join/\\1\\2"]
app = true
```

Keys: `url` (glob) or `match` (host, or `re:` for a regex) · `profile` ·
`rewrite` · `app` · `source`. First match wins. A rule without `profile` still
goes through workspace/picker resolution.

## Why one data dir per ego

Chrome runs **one process per `--user-data-dir`**, and a launch naming a data dir
that is already running is handed to that process over the singleton socket. So
two Chrome-internal profiles inside one data dir are indistinguishable from
outside — same window class, same title, and `--class` is dropped. Verified on
Chrome 152 and Chromium 151:

```
chrome --profile-directory=Default / "Profile 1"
   →  BOTH class 'google-chrome', both titled 'about:blank - Google Chrome'
```

Separate data dirs are the only arrangement where the outside world can tell
which identity a window belongs to. The cost is no in-browser profile switcher
between egos; the gain is that each ego syncs to its own Google account.

A window's ego is resolved from its process's `--user-data-dir`, not its class —
see `docs/gotchas.md`, which is the part worth reading before changing anything.

## Install

```bash
git clone <this repo> ~/Work/omaego
cd ~/Work/omaego
./install.sh --with-plugin
omarchy plugin enable io.github.lcorneliussen.omaego right    # optional bar widget
```

Idempotent, and backs up anything it replaces. It links `bin/` into
`~/.local/bin`, migrates `~/.config/urlrouter/rules.toml` if present, installs
the `chromium.desktop` shim, registers omaego as the default browser, and
relinks native-messaging hosts into every ego. `urlrouter` and `chrome-webapp`
stay as compatibility symlinks so launchers written against the old names keep
working — `omaego-webapp` still accepts `--profile=` as well as `--ego=`.

The binaries are symlinks **into the repo**, so do not delete the checkout.

## Web apps, pinned to an ego

```bash
omarchy webapp install "Teams Work" https://teams.microsoft.com/ "" \
  "$HOME/.local/bin/omaego-webapp --ego=work --app=https://teams.microsoft.com/"
```

The fourth argument is what keeps the whole command line. `omarchy-launch-webapp`
keeps only the **first token** of an `Exec=` line, which is why the ego has to be
chosen inside a wrapper script.

## The bar widget

Shows the ego owning the current workspace, dimmed when the workspace has none,
and in the urgent colour when a workspace has gone **mixed** (more than one ego),
which is usually worth noticing. Click opens a browser here — the picker if the
workspace is empty. It shells out to `omaego space --json`.

## Requires

Omarchy (tested 4.0.2 → 4.0.4), Hyprland, Google Chrome, `walker` for the
picker, Python 3.11+ for `tomllib`. Chromium works for routing but has no Google
sync on Arch (`signin allowed: false`), which is why Chrome is the default.

## Origin

Built over 2026-09-04…09 and documented in two tries, which remain the long-form
record:

- `~/Work/tries/2026-10-01-urlrouter-chrome-profile-routing` — how and why it was
  built, and every trap hit on the way.
- `~/Work/tries/2026-09-24-chrome-profiles` — adding Outlook per-tenant egos, and
  the Google visitor-session wall.

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
omaego add "Acme"               # a new ego (or: omaego new, or the bar panel)
omaego <url>                    # what the desktop entry calls
```

There is deliberately **no "active ego"**. An ego is not a mode you switch the
system into; it is an identity that happens to have windows on a workspace. A
workspace usually belongs to one ego, and links resolve inside the workspace
they were clicked from.

## Setting up an ego

```bash
omaego add "Acme"            # a new --user-data-dir, its own class, own sync
omaego launch acme           # sign in to Google/Microsoft in the window it opens
omaego app add acme teams outlook
omaego rule add 'https://acme.atlassian.net/*' Acme
```

`omaego add` prints those next steps for you. Nothing else on the machine shares
that ego's cookies, extensions or sync account.

To lift an existing Chrome-internal profile out into its own ego (keeping its
history, bookmarks and logins), quit Chrome fully and:

```bash
omaego import google-chrome          # lists what is inside
omaego import google-chrome "Acme"   # copies it out; the original stays as a rollback
```

## How a link is routed

1. **A rule in `~/.config/omaego/rules.toml`** → that ego, forced.
2. **A browser window of some ego already on this workspace** → reuse it,
   as a tab. If the workspace holds several egos, the one whose window comes
   **first in the tiling** wins — no prompt.
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
omaego app list                           # the catalogue
omaego app add work teams outlook         # -> "Teams Work", "Outlook Work"
omaego app add personal gmail gcal gchat
omaego app add work --url https://jira.acme.io      # name offered: "Jira"
omaego app add work --name "Acme Wiki"              # asks for the URL
```

Each app becomes its own window, signed into that ego, with a real icon. The
launcher name is `{app} {ego}` by default (`OMAEGO_APP_NAME` to change it), so
typing "teams" in the launcher finds every tenant's Teams at once.

Icons are normalised on the way in: sites serve JPEGs under a `.png` name and
64px favicons into the 256px directory, both of which look wrong on a dark bar.

`--rule` additionally routes that host to the ego — offered only for hosts one
ego can plausibly own outright. **Teams, Outlook, Gmail and Meet deliberately
have no rule**: several egos share those hosts, so a rule would send a
customer's link to the wrong identity.

Under the hood this is `omarchy webapp install` with its fourth argument, the
only one that keeps a whole command line — `omarchy-launch-webapp` otherwise
truncates `Exec=` to its first token, which is why the ego must be chosen inside
a wrapper script.

## The bar widget

The label shows the ego owning the current workspace, dimmed when there is none
and in the urgent colour when a workspace has gone **mixed** (more than one ego),
which is usually worth noticing.

Clicking opens a panel with **one column per ego**. Egos on this desktop are
tinted. Each column shows the ego (click to open its browser here; hovering
outlines its windows), its web apps (click to launch), the hosts that always
open in it, and `+ Add app` / `+ Add rule`. Hover a rule to reveal its ✕. The last
column, **New ego**, runs `omaego new`: name it in walker, and its window
opens so you can sign in. Rules that name no ego, such as the Zoom rewrites, are
listed underneath. Text entry goes through walker rather than QML dialogs, so
the picker you already know handles it and the QML stays small.

Every ego has a colour. Names in the bar carry it, the panel shows it as a chip,
and **while the panel is open every ego's windows are outlined in that colour** —
so the mapping between a name and the tiles on screen is readable at a glance.
Override one with a `.ego-color` file (`rrggbb`) in the ego's directory.

It gets everything from one `omaego panel` call, and never logs its polling.

**After enabling or moving the widget, run `omarchy restart shell`** — a hot
reload will not re-instantiate it in a new bar section, and it simply will not
appear, with nothing in the logs to say so.

**If you build on this:** a third-party bar widget's QML file *must* be named
`BarWidget.qml`. Any other name fails with Qt's "File name case mismatch",
which points nowhere near the cause. First-party widgets use other names only
because they live inside the shell's own module tree.

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

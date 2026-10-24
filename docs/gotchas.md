# Gotchas

Everything here silently did the wrong thing at least once while omaego was
built. Read before changing launch or window-identification code.

Found against Chromium 151 / Chrome 152 · omarchy 4.0.2; re-checked on
Chrome 154 / omarchy 4.0.4, where the two omarchy bugs below **still stand**.

## Chrome

| Thing | Reality |
|---|---|
| `--class` on a launch that gets forwarded | **Dropped.** The *first* launcher of a data dir fixes the class of every browser window that instance ever opens. `omaego-webapp` passes `--class` for exactly this reason: web apps often start an ego at login, and without it that ego's later browser windows come out as anonymous `google-chrome`. |
| Identify a window's ego | Read `--user-data-dir` from `/proc/<pid>/cmdline`. **Chrome rewrites its own argv, so that file is SPACE separated, not NUL separated** — `tr '\0' '\n'` then matching `^--user-data-dir=` finds nothing, for every window, and looks like "no ego owns this". |
| Web-app window class | `chrome-<host><path>-<ProfileDir>`. A URL with a path gives `chrome-outlook.office.com__mail_-Default`, which does **not** match a `^chrome-.+__-` shape test. Detect app windows **by elimination** (any `chrome-*` class that is not a known ego class), or Outlook/Teams get treated as ordinary browser windows. |
| Opening a link in an `--app` window | Impossible. Chrome silently opens a **new browser window** instead. Hence web apps are a hint, never a reuse target. |
| Focus before launching | Chrome drops the tab into whichever window of that ego it last considered active, possibly on another desktop. Focus the target first — and **wait for the compositor to confirm it**: `hyprctl dispatch` returns when the dispatch is queued, and launching milliseconds later races the activation. |
| Chrome opens `--app=` in its **last-used profile** | Pin the ego explicitly or a web app lands wherever you last were. |
| Links clicked **inside** Chrome | Never reach `xdg-open`, so omaego never sees them. Chrome routes them into an existing browser window of the same ego, wherever it lives. Not fixable from outside. |
| Native messaging hosts | Resolved **relative to the user-data-dir**. A new ego sees none of `~/.config/google-chrome/NativeMessagingHosts/`, which silently breaks 1Password desktop unlock and omarchy's copy-url / yt-dlp extensions. `omaego sync` symlinks each manifest in, per *file* — Chrome creates an empty `NativeMessagingHosts` directory itself, so linking the directory fails. **Do not delete `~/.config/google-chrome`**; the symlinks point into it. |
| Arch Chromium | `signin allowed: false` — no Google sync at all. Separate data dirs would be isolated islands. The engine follows omarchy's default browser, so this is a reason to make Chrome that default. |

## Omarchy

| Thing | Reality |
|---|---|
| `omarchy-launch-webapp` | Whitelists the default browser by `.desktop` name and falls back to **`chromium.desktop`** for anything unrecognised — `omaego.desktop` is not on the list. It also keeps only the **first token** of `Exec=`, discarding every flag, then appends `--app=<url>`. Hence the NoDisplay `chromium.desktop` shim pointing at `omaego-webapp`. Still true in 4.0.4; worth reporting upstream. |
| `omarchy-launch-browser` | Probes the browser with `--help \| grep MOZ_LOG` to detect Firefox, then runs it with **no arguments** for a plain launch and `--incognito` for private. A default-browser handler must survive all three, or `SUPER+SHIFT+B` pops a picker and opens nothing. |
| `omarchy webapp install` 4th arg | Keeps the **whole** command line, unlike `omarchy-launch-webapp`. The only supported way to pin a web app to an ego. |
| Web-app icon fetch | Can return a **JPEG saved with a `.png` extension**, or a 512px file in the 256px directory. Check with `file`. To drop a white background without eating white *inside* the logo, flood-fill from the corner: `-fuzz 8% -fill none -floodfill +0+0 white`. |
| Moving a widget between bar sections — or any edit to it | Needs `omarchy restart shell`. A hot reload reloads plugin *code* only — the widget is never re-instantiated in its new section, so it silently does not render while the log cheerfully reports "Local plugin changed, reloading" and the plugin lists as enabled. Nothing in the logs says anything is wrong. |
| Checking a bar widget works | "Loads without errors" and "is polling its command" are both true of a widget that draws nothing. Screenshot the bar (`grim -g "0,0 900x36"`) and look. |
| Plugins | Six kinds (`bar`, `bar-widget`, `menu`, `overlay`, `panel`, `service`), all QML, with **no install hook** — a plugin cannot place a binary or claim `x-scheme-handler/https`. The CLI therefore cannot be a plugin; only the bar widget can. Symlinks anywhere inside a plugin folder are refused. The widget is its own repo, `omaego-bar`, and `install.sh --with-plugin` adds it through `omarchy plugin add`. |
| Quickshell `Component.onCompleted` in a bar widget | Runs **before** the bar injects `settings`, so anything it starts uses defaults — a bare `omaego` instead of the configured command path. Do start-up work after the first successful probe. |
| Reacting to focus and window changes | Do not poll. `ToplevelManager.activeToplevel` (`Quickshell.Wayland`) updates the instant focus moves, and Hyprland's `onRawEvent` reports `openwindow` / `closewindow` / `movewindow` / `activewindow` / `workspace`; coalesce bursts through a short timer. A web app's `appId` is the app's, not the ego's, so only browser windows match by `appId`. |
| A terminal window with its own class | Omarchy tags terminals **by class** (`default/hypr/apps/terminals.lua`), and SUPER+C / SUPER+V send Ctrl+Insert / Shift+Insert only to tagged windows. Any other class gets Ctrl+C / Ctrl+V: copy interrupts the program. Remote terminals are `TUI.omaego.<ego>.<remote>`, because `TUI.*` is on that list. |
| `omarchy webapp install` with no reachable icon | Exits non-zero with empty stderr and installs nothing. Internal hosts often serve no icon, so retry with a generic one. |

## Hyprland

| Thing | Reality |
|---|---|
| `set_prop` prop names | snake_case in the Lua API: `rounding`, `border_size`, `active_border_color`, `inactive_border_color`. The classic `bordercolor`/`bordersize` spellings are rejected as "Invalid prop name", and `hyprctl setprop` is gone entirely ("unknown request"). Setting `border_size` also **reflows the tiling and resizes windows** — for an outline, change colour only. |
| Clearing a `set_prop` colour | Only `value = 0` restores the theme's border. `'unset'` and `-1` both answer `ok` and change nothing, so a highlight "cleared" that way stays on the window for good. And colour **only** `inactive_border_color`: setting `active_border_color` too makes a focused window look like any other, which removes Hyprland's own focus marking. |
| Many dispatches | One `hyprctl dispatch` per window per property is a process each, and it lags visibly. `hyprctl --batch "dispatch … ; dispatch …"` accepts the Lua form and runs the lot in ~6ms. |
| Lua dispatch | `hyprctl dispatch closewindow address:0x…` **errors**. Use `hl.dsp.window.close({ window = 'address:0x…' })` and `hl.dsp.focus({ window = 'address:0x…' })`. |
| `hyprctl clients` | Has **no `focused` key** — it is `focusHistoryID`. Compare against `hyprctl activewindow`'s address instead, or the branch never fires. |

## walker

| Thing | Reality |
|---|---|
| `--dmenu` and typed text | Rows are filtered by what is typed. When **no** row is left, Enter returns the typed text (exit 0; checked on walker 2.17). Esc returns nothing with exit 130. So one prompt can be a list and a text field — but text that still fuzzy-matches a row (typing "Mail" with "Gmail" listed) returns that row. Keep an explicit row that opens `--inputonly` for that case. Older walker returned nothing on no match. |
| `-X` / `--selectsingle` | Picks the last remaining row **by itself** while you are still typing. Never use it on a search, where one row left is a filter result and not a choice. |
| `--inputonly` | Shows the input and nothing else, which looks identical to a broken picker. Say in the placeholder what Enter does. |

## herdr and remotes

| Thing | Reality |
|---|---|
| `herdr --remote` on a lost connection | Exits **1** and leaves the terminal at a shell, or closes it. There is no reconnect of its own; `omaego-remote` loops on any non-zero exit and treats 0 (detach, quit) as done. A herdr client killed mid-draw leaves its alternate screen behind until the reattach redraws it. |
| Commands over ssh | `ssh host cmd` runs a non-login shell: `openclaw` in `~/.npm-global/bin`, mise shims, `~/.local/bin` are often not on its PATH. Remote TUIs run as `exec "$SHELL" -lc '<cmd>'`, local ones in `$SHELL -lc` (the bar's environment lacks them too). |
| Probing a machine over ssh | A non-login shell often lacks `~/.local/bin`, so `herdr` is "not found" on a machine that has it. The probe runs in `"$SHELL" -l` with the script on stdin. |
| Tailscale SSH "additional check" | A machine can ask for a login to be approved in the browser before ssh goes through. `BatchMode` does not stop it: ssh prints `To authenticate, visit: https://login.tailscale.com/a/…` on stderr and then **waits**, so a probe looks like a slow timeout and the machine silently drops out. The probe watches stderr for that URL and reports the machine as needing approval. |
| Tailscale machine names | `HostName` is not unique: two Macs can both be `macbook-pro`. Use the MagicDNS label (`DNSName`'s first part), which is. |
| Omarchy menu width | Rows are cut at about 25 characters by default. `omarchy-menu-select … -- --width 560` widens it (`pick(…, width=)`); still put what tells rows apart first ("box: compose", not "herdr compose · box"). |
| Showing a menu while something loads | A second `omarchy-menu-select` while one is open **replaces its rows in place**, and the choice goes to the second caller; the first never returns and has to be terminated. `remote pick` opens a "Looking at your machines…" menu at once this way, since a notification about a slow probe is easily missed. |

## Icons

| Thing | Reality |
|---|---|
| Badging | Always draw the badge from `<icon>.orig.png`, the unbadged original, or a second run stacks a disc on the first. A replacement icon replaces the `.orig` too. |
| Ring-shaped logos | A transparent centre takes on whatever is behind it and reads as a white blob in the launcher. Fill the hole, clipped to the logo's outline. |
| Chrome's own copies | App windows use icons Chrome caches from the site manifest under `Web Applications/Manifest Resources/<id>/Icons/`. The `.desktop` icon drives the launcher only, so the two can differ. |

## Working on this in an agent shell

`pkill -f <pattern>` matches the agent's own command line and kills the shell
(exit 144). Split the literal (`P="oc""-test"`) or kill by explicit PID.

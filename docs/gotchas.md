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
| Arch Chromium | `signin allowed: false` — no Google sync at all. Separate data dirs would be isolated islands. This is why Chrome is the default engine. |

## Omarchy

| Thing | Reality |
|---|---|
| `omarchy-launch-webapp` | Whitelists the default browser by `.desktop` name and falls back to **`chromium.desktop`** for anything unrecognised — `omaego.desktop` is not on the list. It also keeps only the **first token** of `Exec=`, discarding every flag, then appends `--app=<url>`. Hence the NoDisplay `chromium.desktop` shim pointing at `omaego-webapp`. Still true in 4.0.4; worth reporting upstream. |
| `omarchy-launch-browser` | Probes the browser with `--help \| grep MOZ_LOG` to detect Firefox, then runs it with **no arguments** for a plain launch and `--incognito` for private. A default-browser handler must survive all three, or `SUPER+SHIFT+B` pops a picker and opens nothing. |
| `omarchy webapp install` 4th arg | Keeps the **whole** command line, unlike `omarchy-launch-webapp`. The only supported way to pin a web app to an ego. |
| Web-app icon fetch | Can return a **JPEG saved with a `.png` extension**, or a 512px file in the 256px directory. Check with `file`. To drop a white background without eating white *inside* the logo, flood-fill from the corner: `-fuzz 8% -fill none -floodfill +0+0 white`. |
| Moving a widget between bar sections | Needs `omarchy restart shell`. A hot reload reloads plugin *code* only — the widget is never re-instantiated in its new section, so it silently does not render while the log cheerfully reports "Local plugin changed, reloading" and the plugin lists as enabled. Nothing in the logs says anything is wrong. |
| Checking a bar widget works | "Loads without errors" and "is polling its command" are both true of a widget that draws nothing. Screenshot the bar (`grim -g "0,0 900x36"`) and look. |
| Plugins | Six kinds (`bar`, `bar-widget`, `menu`, `overlay`, `panel`, `service`), all QML, with **no install hook** — a plugin cannot place a binary or claim `x-scheme-handler/https`. The CLI therefore cannot be a plugin; only the bar widget can. Symlinks anywhere inside a plugin folder are refused, so `install.sh` copies the plugin rather than linking it. |

## Hyprland

| Thing | Reality |
|---|---|
| Lua dispatch | `hyprctl dispatch closewindow address:0x…` **errors**. Use `hl.dsp.window.close({ window = 'address:0x…' })` and `hl.dsp.focus({ window = 'address:0x…' })`. |
| `hyprctl clients` | Has **no `focused` key** — it is `focusHistoryID`. Compare against `hyprctl activewindow`'s address instead, or the branch never fires. |

## Working on this in an agent shell

`pkill -f <pattern>` matches the agent's own command line and kills the shell
(exit 144). Split the literal (`P="oc""-test"`) or kill by explicit PID.

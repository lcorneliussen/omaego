# Guide: launching separate Herdr **app windows** from omaego

Status: proposal / implementation guide. Written against `herdr-core-bin 0.1.16`,
`herdr-app-bin 0.1.11`, and `bin/omaego` as of this commit. The key behaviours
below (HC_SESSION honoring, HERDR_APP_ID class) were **verified live**, not
inferred — see [Verification](#verification-what-was-actually-tested).

## What this is about

omaego already pins **herdr** remotes per ego (`omaego remote add <ego> herdr
<machine> [session]`) and opens them as a **TUI in a terminal**, under the
`omaego-remote` reconnect wrapper. That targets the *legacy* standalone Herdr TUI:
the `herdr` binary (v0.9.x), model `herdr --session <name>` /
`herdr --remote <host> --session <name>`.

There is now a **new Herdr desktop app** — a GUI window, not a terminal program.
We want omaego to launch and pin **separate app windows**, each on a chosen
machine and session, alongside the legacy TUI remotes. **Support both.**

## The two generations

| | Legacy | New |
|---|--------|-----|
| Binary you launch | `herdr` (one binary: client + server + TUI) | `herdr-app` (GUI window) backed by `herdr-core` / `hc` (headless, owns terminals) |
| omaego remote kind | `herdr` (keep as-is) | **`herdr-app`** (this guide) |
| Window surface | terminal, under `omaego-remote` reconnect wrapper | native GUI window; core keeps terminals alive itself — **no reconnect wrapper** |
| Session select | `--session <name>` | `HC_SESSION=<name>` env (**verified honored by the app**) |
| Remote machine | `herdr --remote <host> --session <s>` | `hc machine add <host> --session <s>` + a space bound to that machine |
| Window class / id | `--app-id=TUI.omaego.<ego>.<remote>` to the terminal | `HERDR_APP_ID=<class>` env (**verified** sets Wayland `app_id`/`WM_CLASS`) |
| Separate windows | one terminal per launch | one window per `HERDR_APP_HOME` dir |

### On the name "hc"

We considered calling the new kind `hc`. Recommendation: **call it `herdr-app`,
not `hc`.** `hc` is the *backend/CLI* that drives the core; you don't run `hc` to
get a window, and `hc attach` is itself a (TUI) client — so `hc` is ambiguous and
would collide if we ever add a "new-stack TUI" mode. `herdr-app` names exactly
what is launched and reads well in the launcher ("herdr window on <machine>").
Legacy stays `herdr`. (If you still want `hc` as the user-typed keyword, accept it
as an alias that maps to kind `herdr-app` in the CLI parser.)

## The app's axes (all three are real and independent)

| Axis | Mechanism | Scope |
|------|-----------|-------|
| **Window / instance** | `HERDR_APP_HOME=<dir>` | one window — own `settings.json`, `keys.json`, `layouts/`, `mods/`, control socket. The only way to get a second coexisting window. Bare `herdr-app` with the same home raises the existing one (idempotent). |
| **Session** | `HC_SESSION=<name>` | the core namespace the window's terminals live in. **Verified:** a window launched with `HC_SESSION=x` puts its terminals in `~/.local/state/herdr-core/x/`, isolated from `default`. Unset → `default`. This is the direct analogue of legacy `--session`. |
| **Window identity** | `HERDR_APP_ID=<class>` | Wayland `app_id` / X11 `WM_CLASS` (default `herdr-app`). **Verified** it sets the class. Use it for bar/launcher/window-rule identity, like the TUI `--app-id`. |
| **Machine** | `hc machine add` + space `--machine` | a **space** inside the window, bound to a machine; its terminals run in that machine's core and persist there. One window can hold spaces on several machines. |

### Local vs remote session — read this

- `HC_SESSION` selects the session of the **local** core the window attaches to
  (and its "this machine" spaces).
- A **remote** machine's session is fixed when it is registered:
  `hc machine add <target> --session <name>`. The window's local `HC_SESSION`
  does **not** reach into a remote core.

So the two common omaego cases map cleanly onto the legacy ones:

| Legacy | New `herdr-app` |
|--------|-----------------|
| `herdr --session S` (local) | `HC_SESSION=S herdr-app` (+ its own `HERDR_APP_HOME`/`HERDR_APP_ID`) |
| `herdr --remote M --session S` | register `hc machine add M --session S` once, open the window, ensure a space `--machine M` |

## The launch recipe

Local machine, session `S`, pinned to ego `<ego>`:

```sh
HERDR_APP_HOME="$HOME/.local/state/omaego/herdr-app/<ego>-<session>"  \
HERDR_APP_ID="omaego.<ego>.herdr-app"                                 \
HC_SESSION="<session>"                                                \
herdr-app
```

- `HERDR_APP_HOME` → stable, unique per window omaego wants to coexist (per
  ego+session is a safe key). The app creates/populates it on first start.
- `HERDR_APP_ID` → distinct Wayland class (mirror `REMOTE_CLASS` scheme).
- `HC_SESSION` → the session; omit or `default` for the default one.
- **No `omaego-remote` wrapper, no terminal.**

Remote machine `M` (session handled at registration): same launch, then make sure
the window has a space on `M`:

```sh
# register once (idempotent-ish; skip if `hc machine ls` already lists M):
hc machine add <ssh-target> --name M --session <session>

# after the window answers, only if no space for M exists yet:
HERDR_APP_HOME=... herdr-app do space.new --name "<label>" --machine M \
    --folder "<path on M>"
```

### Startup ordering (required)

`herdr-app do ...` returns "the window did not answer" until the window is up:

1. `env … herdr-app &` (opens/raises).
2. Poll `HERDR_APP_HOME=… herdr-app status` until it answers (typically <0.5 s).
3. `herdr-app ls` → if no space matches `M`/`<label>`, run `space.new`; else do
   nothing (don't duplicate the space on every launcher click).

Put steps 1–3 in a small helper (sibling of `omaego-remote`, e.g.
`omaego-herdr-app`) that `open_remote` execs, so `bin/omaego` stays clean.

## Concrete changes in `bin/omaego`

Line numbers are against the current file.

### 1. New remote kind — line 2267
`REMOTE_KINDS = ("herdr", "tui", "web")` → add `"herdr-app"`.

Stored record in `egos.toml` (`remotes = [...]`):
```python
{"kind": "herdr-app", "machine": "<m>", "session": "<name>",
 "name": "<label>", "folder": "<optional>"}
```

### 2. `remote_command` — line 2813
Legacy-TUI argv builder, wrapped by `omaego-remote`. **herdr-app must not use it.**
Leave it for `herdr`/`tui`; handle `herdr-app` entirely in `open_remote`.

### 3. `open_remote` — line 2832
Add a branch *before* the `("herdr","tui")` one:
```python
if r["kind"] == "herdr-app":
    sess = r.get("session") or "default"
    home = STATE / "herdr-app" / f"{slug}-{slugify(sess)}"
    home.mkdir(parents=True, exist_ok=True)
    env = {**os.environ,
           "HERDR_APP_HOME": str(home),
           "HERDR_APP_ID": f"{REMOTE_CLASS}{slug}.herdr-app",
           "HC_SESSION": sess}
    me, peers = tailnet()
    args = []
    if r["machine"] != me:                       # remote → ensure machine + space
        args = ["--machine", r["machine"]]
        if r.get("ssh"): args += ["--ssh", r["ssh"]]
    if r.get("folder"): args += ["--folder", r["folder"]]
    helper = <path to omaego-herdr-app>          # does launch → status → space.new
    subprocess.Popen([helper, "--label", r["name"], *args],
                     env=env, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0
```
(For a remote, the helper also runs `hc machine add … --session <sess>` if the
machine isn't already in `hc machine ls`.)

### 4. `write_remote_entries` — line 2957
- `what` label dict (~line 2971): add
  `"herdr-app": f"herdr window ({r.get('session') or 'default'}) on {r['machine']}"`.
- `Exec=` stays `omaego remote open {slug} {remote_id(r)}` — unchanged.
- `Terminal=false` already correct.

### 5. Icons — `remote_base_icon` line 2914 (key ~line 2918)
Share the herdr-dev icon:
```python
key = "herdr" if r["kind"] in ("herdr", "herdr-app") or word == ["herdr"] else ...
```

### 6. CLI `remote add` — line 4349
Add usage + branch (parallels the `herdr` branch at 4366–4369):
```
omaego remote add <ego> herdr-app <machine> [session] [--folder /path] [--name N]
```
```python
elif kind == "herdr-app":
    r["session"] = pos[3] if len(pos) > 3 else "default"
    r["name"] = opts.get("name") or (f"herdr @{machine}" if r["session"] == "default"
                                     else f"herdr {r['session']} @{machine}")
    if opts.get("folder"): r["folder"] = opts["folder"]
```

### 7. Discovery / `PROBE` — line 2454
The probe already lists sessions via `herdr session list` (legacy). For the new
stack, list `hc` sessions per machine instead/also:
```sh
command -v hc >/dev/null 2>&1 && ls ~/.local/state/herdr-core 2>/dev/null \
  | while read s; do echo "herdr-app $s"; done
```
Then offer, in `pick`/`stream_offers`, one "herdr window (<session>) on <machine>"
per discovered session — the same UX you already have for legacy sessions.

## Verification (what was actually tested)

Run on this machine, `herdr-core 0.1.16` / `herdr-app 0.1.11`:

1. Seeded a marker terminal in a fresh session:
   `HC_SESSION=omaego-test hc run --bg -- bash -c 'echo MARKER; exec sleep 1e9'`.
2. Launched `HERDR_APP_HOME=/tmp/ht HERDR_APP_ID=omaego.test.herdrapp
   HC_SESSION=omaego-test herdr-app`.
3. Results:
   - The window's own new shell appeared in the **omaego-test** session
     (`HC_SESSION=omaego-test hc ls` showed the marker `t1` **and** the window's
     `t2`); the `default` session gained no live shell. → **the app honors
     `HC_SESSION`.**
   - `hyprctl clients` showed the window with `class=omaego.test.herdrapp`
     (vs the default `herdr-app`). → **`HERDR_APP_ID` sets the Wayland class.**
   - Note: an *unlabeled* background worker (`hc run --bg` with no space label)
     does not appear in the window — the app hides unlabeled workers. It still
     lives in the session. Expect only labeled/space terminals to render.

Keep step 2–3 as a regression check when bumping Herdr versions.

## Test plan for the omaego change

1. `omaego remote add work herdr-app <localmachine> myses` → egocard shows a
   "herdr myses @…" entry; `.desktop` has `Terminal=false` + herdr icon.
2. Click it → a window opens; `hyprctl clients` shows `class=omaego.work.herdr-app`;
   `HC_SESSION=myses hc ls` shows the window's terminal.
3. Click again → same window raised; no second window, no duplicate space.
4. `omaego remote add work herdr-app <remote> rs` (machine registered with
   `--session rs`) → window opens with a space on that machine; close + reopen →
   terminals persist (core keeps them).
5. `omaego remote remove work "…"` → entry + icon gone. Decide whether
   `apply --prune` also removes the `HERDR_APP_HOME` dir (recommend: leave it,
   it holds the window's layout/mods).

## Open items / upstream (herdr) requests

- **Launch-time machine/space flag.** `herdr-app --space <name> --machine <m>
  --folder <p>` would remove the "launch → poll status → space.new" dance. Worth
  requesting upstream.
- **Per-remote-core selection documented.** `HC_SESSION` works but isn't in the
  app's `AGENTS.md`; ask herdr to document it so we're not relying on an
  undocumented env var.

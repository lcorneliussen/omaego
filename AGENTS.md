# Working on omaego

Read `docs/gotchas.md` before touching launch, window-identification, walker or
Hyprland code. This file covers what the code and that doc do not say.

## Two repos

| Repo | Holds |
|---|---|
| `omaego` (this one) | The CLI (`bin/omaego`, `bin/omaego-webapp`), `install.sh`, `packaging/PKGBUILD`. |
| `omaego-bar` (sibling checkout, `../omaego-bar`) | The bar widget and panel: `BarWidget.qml`, `manifest.json`, preview assets, `scripts/demo.sh`. |

The widget lives **only** in `omaego-bar`. There is no `plugin/` here any more;
a copy in both repos drifted once and the wrong one got patched. A widget change
that needs new data usually means a CLI change here (`omaego panel` is what the
widget reads) and a QML change there.

`omaego-bar` is the repo meant for the Omarchy plugin marketplace, which shapes
both:

- It must keep `manifest.json` at its root and ship **no installer**. The
  marketplace scanner marks any repo with one as `installer` / `remote-build`;
  without one it passes clear. The combined installer therefore stays here.
- The README install chain here must pin a **full 40-character SHA** and stay
  one fail-closed `&&` chain, or the scanner reports
  `remote-git-execution-unpinned`.
- A plugin with a companion CLI says so in its description — "powered by the
  omaego CLI" — which is the convention across the marketplace.

## Vocabulary

- **ego** — one identity: a Chrome user-data-dir, its colour, its web apps.
- **egocard** — one ego's card in the bar panel: name, its apps, `+app`, the
  close `x`. When someone says "egocard", they mean that card.
- **pill** — the tint behind an ego's name in the bar when it owns the focused
  window.
- **badge** — the ego-coloured disc stamped bottom right on a web app's icon.

Web apps are named **app first, ego last** ("Outlook Work"), and the ego is
always appended, the fallback ego included.

## Nothing personal in either repo

Both repos are public. No real ego, customer, tenant or host names in code,
comments, docs, tests, commit messages or screenshots — history was rewritten
once to remove some. Use the invented set: egos **Acme / Personal / Work**,
hosts under `example.com`. Published images come from `scripts/demo.sh` in
`omaego-bar`, which seeds exactly those egos in a box, so nothing real can
appear in them. The images in this README come the same way from
`scripts/readme-media.sh`, which also serves every page it shows as a local
mock.

## Verifying changes

Anything that opens walker, the panel or a window gets driven in an **omabox**
box, not reasoned about and not run on the real desktop. Several flows here
were reported working without ever being exercised, and were broken.

- The panel launches the CLI detached, with no terminal: stderr goes nowhere
  and a traceback looks like "nothing happened". Run the same command in the
  foreground to see the error, and make every interactive outcome — success
  and failure — raise a notification.
- Every prompt must be gated to the interactive path. `omaego app add --url …
  --name …` has to return at once; an ungated walker prompt blocks a scripted
  call until walker times out.
- Kill stray detached pickers between box runs. They compete for keystrokes and
  produce results that look like code bugs.
- For the bar, look at a screenshot. "Loads without errors" is true of a widget
  that draws nothing.

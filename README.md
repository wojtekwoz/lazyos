# LazyOS

> Self-hosted apps for your Mac — without ever seeing the words *container*, *compose*, or *Docker*.

LazyOS is a native macOS app + CLI that lets non-technical people (or yourself, when you're tired) run things like **Mixpost**, **Postiz**, **n8n**, **Ghost** locally — on demand, or on a schedule — with no Docker Desktop, no OrbStack, no separate daemon to babysit.

Open the app. Click **Start** on Mixpost. Open it in your browser. Click **Stop** when you're done. That's the whole product.

```
┌──────────────────────────────────────────────┐
│ LazyOS                       ⌘K  Browse… ⚙   │
├──────────────────────────────────────────────┤
│ RUNNING (1)                                  │
│ ┌──────────────────────────────────────────┐ │
│ │ ✉  Mixpost              ● Running        │ │
│ │    Schedule social posts                 │ │
│ │    CPU 3%  ·  RAM 412 MB                 │ │
│ │  ╔══════════════╗  Stop                  │ │
│ │  ║   Open  ↗    ║                        │ │
│ │  ╚══════════════╝                        │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ INSTALLED (3)                                │
│ ┌────────┐  ┌────────┐  ┌────────┐           │
│ │ Postiz │  │  n8n   │  │ Ghost  │           │
│ │ Start  │  │ Start  │  │ Start  │           │
│ └────────┘  └────────┘  └────────┘           │
│ ────────────────────────────────────────     │
│ 1 running · 3 containers · 3% CPU · 412 MB   │
└──────────────────────────────────────────────┘
```

## Why not just use OrbStack?

You can. LazyOS is the *user* version of OrbStack — same idea, different audience. OrbStack gives you containers; LazyOS gives you *apps*. Your friend who wants to schedule Instagram posts shouldn't have to learn what a container is.

LazyOS also runs the runtime *itself* invisibly (a tiny Linux VM via Apple's Virtualization.framework, driven by [Lima](https://lima-vm.io)). One app to install, no extra dependencies, no Docker Desktop.

## Features

- **Curated catalog.** Mixpost, Postiz, MeTube, Excalidraw built in. n8n, Ghost coming. One click installs.
- **Custom apps.** Drag any folder containing a `docker-compose.yml` onto LazyOS to add it.
- **Schedules.** "Run Mixpost weekdays 9 AM – 7 PM." Translated to launchd plists under the hood.
- **Power tiers.** Light / Normal / Heavy. Plain English for CPU + RAM caps.
- **Auto-stop on sleep.** Closing your laptop stops the apps. They resume on demand.
- **Backups.** One click → `~/Documents/LazyOS Backups/<app>-<date>.tar.zst`.
- **Usage at a glance.** CPU + RAM bars on each card and a global footer. Know when you're bloating your Mac.
- **Menu bar.** 📦 icon to start/stop without opening the window.
- **CLI for AI coders.** `lazyos start mixpost`, `lazyos schedule mixpost "0 9 * * 1-5" "0 19 * * 1-5"`. Designed so Claude Code / Cursor / etc. can drive it programmatically.

## Quick start

Requires macOS 14+ on Apple Silicon.

```bash
git clone https://github.com/wojtekwoz/lazyos.git
cd lazyos

# Until the bundled runtime ships, the dev build uses Homebrew Lima:
brew install lima

# Run the GUI:
swift run -c release LazyOSApp

# Or the CLI:
swift run -c release lazyos list
swift run -c release lazyos start mixpost
swift run -c release lazyos open mixpost
```

The first start downloads ~1.2 GB of images (Mixpost + MySQL + Redis). Subsequent starts take a few seconds.

## CLI reference

```
lazyos list                              # show installed apps with status
lazyos catalog                           # show the catalog of available apps
lazyos install <slug>                    # install from catalog (e.g. mixpost)
lazyos add-folder <path>                 # add a custom app from a compose folder
lazyos start  <slug>                     # start an app
lazyos stop   <slug>                     # stop an app
lazyos status <slug>                     # off / starting / running / stopping
lazyos open   <slug>                     # open in default browser
lazyos remove <slug>                     # remove (volumes preserved)
lazyos schedule  <slug> "<startCron>" "<stopCron>"
lazyos unschedule <slug>
lazyos tier   <slug> light|normal|heavy  # set resource cap
lazyos backup  <slug>                    # → ~/Documents/LazyOS Backups/
lazyos restore <slug> <file.tar.zst>
lazyos usage                             # CPU/RAM by app + totals
```

## Architecture

```
LazyOSApp (SwiftUI)          lazyos (CLI)
        │                         │
        └──────── LazyOSCore ─────┘
                      │
              ContainerEngine protocol
                      │
              ┌───────┴────────┐
              │  LimaEngine    │   (Apple `container` framework coming next)
              └───────┬────────┘
                      │ docker socket (vsock-forwarded)
                      ▼
              lazyos VM (Lima)
              Ubuntu + containerd + Docker
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
     Mixpost       MySQL          Redis     (Mixpost stack)
```

- **`Sources/LazyOSCore`** — shared library (models, runtime, store, scheduler, catalog).
- **`Sources/LazyOSApp`** — SwiftUI macOS app.
- **`Sources/lazyos`** — CLI (`ArgumentParser`).
- **`Sources/LazyOSCore/Catalog/Templates/<slug>/`** — bundled compose templates.

Per-user state lives at `~/Library/Application Support/LazyOS/` (services.json, materialized compose files). Backups go to `~/Documents/LazyOS Backups/`.

## Adding an app to the catalog

1. Create `Sources/LazyOSCore/Catalog/Templates/<slug>/docker-compose.yml`. Use `${LAZYOS_PORT}` for the host port; use `${LAZYOS_APP_KEY}` if the app needs a unique per-install secret.
2. Create `Sources/LazyOSCore/Catalog/Templates/<slug>/meta.json`:
   ```json
   {
     "slug": "ghost",
     "name": "Ghost",
     "blurb": "Self-hosted blogging",
     "iconSymbol": "newspaper.fill",
     "accentHex": "#15171A",
     "defaultPort": 30030,
     "healthcheckPath": "/",
     "needsAppKey": false,
     "firstRunHintMB": 500
   }
   ```
3. `swift build` — `Package.swift` already copies `Catalog/Templates` as a bundle resource.
4. PR welcome.

## Status

Early. Mixpost / Postiz / MeTube / Excalidraw run end-to-end. CLI + GUI are wired. The bundled `.app` (signed/notarized DMG) and the migration from "depends on host Lima" → "bundled VM image inside the app" are the next two milestones. See [`ROADMAP.md`](ROADMAP.md) for what's next and [`docs/embedded-runtime-plan.md`](docs/embedded-runtime-plan.md) for the runtime plan.

## Security model

LazyOS runs each app's containers inside an Apple Virtualization-framework VM, so a container exploit doesn't reach macOS directly. Two things to keep in mind:

- **Container processes can still read your home directory** via Lima's default `~/` mount and can reach the public internet. Treat any catalog template (including ours) the same way you'd treat any `docker-compose.yml` — only run apps you trust.
- **Custom folders are not sandboxed.** Drag-and-drop install runs whatever the compose file says, including bind-mounts of host paths. Audit the YAML before adding.

Tighter mounts, image-digest pinning, and a custom-folder confirmation flow are all on the [roadmap](ROADMAP.md).

## Contributing

Issues and PRs welcome. Areas where help would be immediately useful:

- More catalog templates (Postiz, n8n, Ghost, Nextcloud, Plausible, Umami, ...)
- A first-run "Setting up runtime…" sheet with proper progress
- Image-pull progress parsing on the card during Starting
- macOS 15 path using Apple's `container` framework (behind the same `ContainerEngine` protocol)
- Linux-style menu bar polish (icon when something's running, etc.)

## License

MIT — see [LICENSE](LICENSE).

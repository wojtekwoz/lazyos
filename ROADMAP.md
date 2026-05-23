# Roadmap

What's next for LazyOS, grouped by horizon. Mostly informational — issues + PRs welcome on anything here.

## Now — security hardening

These came out of an audit at the end of the first build session. The current code is safe to publish (no secrets in the repo, no DBs exposed to host, MIT-only dependency, proper CSPRNG for app keys), but the trust surface for compose templates is wider than it should be. Items in priority order:

- [ ] **Bind host port-forwards to `127.0.0.1` only**, never `0.0.0.0`. One-line change in compose templates. Removes accidental LAN exposure on coffee-shop wifi.
- [ ] **Override Lima's default mounts** so the VM only sees `~/Library/Application Support/LazyOS/data/`, not the user's home. Any container started by any compose can already read `~/` because the docker template mounts it. Shrinking the mount set is the single biggest reduction in blast radius.
- [ ] **Generate per-install random DB passwords** for the catalog templates. Current templates hardcode `mixpost/mixpost`, `postiz/postiz`. Safe today (DBs aren't host-mapped) but a footgun if a user later publishes a port. Use the same mechanism as `LAZYOS_APP_KEY`.
- [ ] **Validate `webURL` before opening.** `NSWorkspace.shared.open(URL(string: webURL))` is currently called on whatever string the service has. Restrict to `http`/`https` + `localhost`/`127.0.0.1` so a future feature can't be tricked into opening `file://` / `javascript:` / `x-apple-*://` URLs.
- [ ] **Custom-folder import confirmation.** Display the compose YAML and warn before first start that the file runs with full container privileges. Reject `volumes:` entries that bind-mount paths outside the data directory.
- [ ] **Pin every catalog image to `image@sha256:...` digest** instead of `:latest`. A tag swap shouldn't silently ship new code to every LazyOS install. Add a `lazyos catalog update` command that re-pins with provenance.
- [ ] **"Also delete data" toggle** on Remove, default off. Today named volumes survive removal by design (good for restore); make sure the option to wipe is visible.

## Soon — runtime UX

- [ ] **Stream pull progress** when `lazyos start` runs. Today the CLI is silent during a multi-GB pull, which is bad for both humans and AI coding tools. Change `engine.start` to stream `docker compose --progress=plain` to stdout when invoked from a terminal.
- [ ] **First-run runtime sheet** in the GUI: "Setting up the local runtime (one-time)…" with real progress for `limactl start` + image cache warmup.
- [ ] **Pull progress on the card.** Parse `docker compose` pull events into "Downloading Postiz · 412 MB / 6.0 GB" on the running card instead of an indefinite spinner.
- [ ] **Idle-stop heuristic improvement.** Current check uses `lsof -iTCP:<port> -sTCP:ESTABLISHED`. Tools that finish a request and reconnect each time look idle. Track last-request-time via VM-side conntrack or healthcheck cadence instead.
- [ ] **Detailed status when `engine.status` short-circuits.** Today a missing docker context or stopped VM both surface as `.off`. Distinguish "runtime not ready" from "stopped".

## Catalog growth

Two-line meta + a compose file = one PR. Maintainers willing.

- [ ] **n8n** — workflow automation. Single container, easy.
- [ ] **Ghost** — self-hosted blog. Single container.
- [ ] **Plausible** — analytics. Postgres + ClickHouse.
- [ ] **Umami** — lighter analytics alternative. Postgres only.
- [ ] **Nextcloud** — files / collaboration. Heavy.
- [ ] **Affine** — Notion-like. Postgres + Redis.
- [ ] **PocketBase** — backend-in-a-box. Single binary container.
- [ ] **Memos** — self-hosted notes.

## Bundled runtime — replace "depends on Homebrew Lima" with "single .app"

Currently `swift run` works for development but a real install requires `brew install lima` first. The goal is to bundle everything inside `LazyOS.app`. Detailed plan: [docs/embedded-runtime-plan.md](docs/embedded-runtime-plan.md).

- [ ] Embed a signed `limactl` + a pre-baked Alpine VM image under `Resources/runtime/`.
- [ ] First-launch flow that extracts the runtime once and never again.
- [ ] Xcode-built `.app` bundle with hardened-runtime + Virtualization entitlement.
- [ ] Notarized DMG distribution.
- [ ] `Sparkle` updates with a local feed (no telemetry).

## Future — macOS 15 path

Apple shipped the [`container`](https://github.com/apple/container) framework in 2024: per-container microVMs, native Swift, designed for exactly this use case. As soon as it grows full compose v2 support, swap Lima out behind the existing `ContainerEngine` protocol with no UI changes.

- [ ] Implement `AppleContainerEngine: ContainerEngine`.
- [ ] Compose translation layer (parse YAML → individual `container` invocations) if `container` still lacks compose at the time.
- [ ] Bump minimum macOS to 15 when we make the switch; keep Lima as the macOS 14 path.

## Not planned

A few things we're deliberately *not* building, to keep the product focused:

- Building images from Dockerfiles. LazyOS is a runtime for vetted apps, not a dev tool.
- Multi-host orchestration / clustering. Single Mac, single VM.
- A general Docker Desktop replacement with a terminal pane. If you need that, use OrbStack — it's excellent.
- Telemetry. None, ever. The catalog is bundled; updates are explicit.

---

Last updated end of first build session — May 2026. None of these items are committed deadlines.

# LazyOS — agent guide

Native Mac app + CLI that runs self-hosted tools (Mixpost, Postiz, n8n, …) on-demand. UI hides containers — words like "container", "compose", "Docker" never appear in user-facing strings. OrbStack is the only supported runtime. Everything is local-only — no cloud services, no telemetry.

## Layout

```
Sources/LazyOSCore/    Shared library (models, runtime, store, catalog)
  Models/              Service, CatalogEntry, ServiceStatus, ResourceTier
  Runtime/             OrbStackRuntime, Shell, ErrorTranslator, ServiceManager
  Store/               ServiceStore (JSON-on-disk, file-locked)
  Catalog/             Catalog loader + bundled Templates/
  Util/                Paths, PortPicker, AppKeyGen
Sources/lazyos/        CLI executable (ArgumentParser)
Sources/LazyOSApp/     SwiftUI macOS app (@main)
  Views/, ViewModels/
Tests/LazyOSCoreTests/
```

## Build / run

- `swift build` — compiles core + CLI + app
- `swift test` — runs Core tests
- `swift run lazyos list` — list installed apps
- `swift run LazyOSApp` — launch the GUI (no .app bundle yet; that's a follow-up)

## State storage

- Library: `~/Library/Application Support/LazyOS/services.json`
- Per-service compose + data: `~/Library/Application Support/LazyOS/data/<slug>/`
- Volumes are docker named volumes (`mixpost-data`, `mixpost-mysql`, `mixpost-redis`).

## Runtime model

`OrbStackRuntime` shells out to OrbStack's bundled `docker` binary at `/Applications/OrbStack.app/Contents/MacOS/xbin/docker`. Every Service has a slug; compose project name is always `lazyos-<slug>`. Ports are picked via `PortPicker` from 30000-39999 with the catalog `defaultPort` as preference. Compose files use env-var substitution: `${LAZYOS_PORT}`, `${LAZYOS_APP_KEY}`.

## House rules

- **No Docker jargon in user-facing strings.** Use "app", "Start", "Open", "Power", "Off". When translating errors, route them through `ErrorTranslator.friendly`.
- **Local-only.** No HTTP calls outside `localhost:<port>` from the app process. Templates may reference public image registries — that's allowed because OrbStack handles the pull.
- **CLI and GUI share `LazyOSCore`.** Don't duplicate logic. If you need a new lifecycle action, add it to `ServiceManager` first, then expose in both surfaces.
- **JSON store, not SwiftData.** Two processes write to it (CLI + GUI); SwiftData isn't multi-process safe. Use `ServiceStore.upsert` for writes.
- **Don't bypass `ServiceManager`.** It's the single source of truth that handles port re-picking, env-var prep, and status reconciliation.

## Adding a new app to the catalog

1. Create `Sources/LazyOSCore/Catalog/Templates/<slug>/docker-compose.yml`. Use `${LAZYOS_PORT}` for the host port and (if the app needs it) `${LAZYOS_APP_KEY}` for a per-install secret.
2. Create `Sources/LazyOSCore/Catalog/Templates/<slug>/meta.json` with `slug`, `name`, `blurb`, `iconSymbol` (SF Symbol), `accentHex`, `defaultPort`, `healthcheckPath`, `needsAppKey`, `firstRunHintMB`.
3. Bump `swift build` — `Package.swift` already copies `Catalog/Templates` as a bundle resource.

## Not yet implemented (deferred)

Scheduling (launchd plists), backups, idle/sleep auto-stop, menu bar item, custom-folder add, IPC socket between CLI and live GUI, resource-tier compose overrides, notarized .app bundle. See `/Users/wozu/.claude/plans/i-want-to-build-keen-hopcroft.md` for the full roadmap.

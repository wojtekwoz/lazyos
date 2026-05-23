# Embedded Runtime — Replacing OrbStack inside LazyOS

## Goal

Ship LazyOS as a single, self-contained `.app`. The user installs LazyOS, opens it, clicks **Start Mixpost** — no separate OrbStack/Docker/Podman/Colima install, no second app to launch, no daemon to babysit. Performance, footprint, and reliability target: **parity with OrbStack, better in two specific places** (zero-install onboarding, and a smaller cold-start RAM floor when no services are running).

## Non-goals (v1)

- A general-purpose Docker Desktop replacement with a full GUI, terminal, etc. We only need to start/stop/expose a curated set of compose-based apps.
- Image building. We pull only.
- Multi-architecture. We target Apple Silicon first; Intel later if there's demand.
- Kubernetes, swarm, anything beyond a single host.

## The stack — what OrbStack uses and what we reuse

OrbStack is, under the hood, three layers:

1. **VM layer** — Apple `Virtualization.framework` (VZ) running a stripped Linux kernel with virtio-fs for host file sharing, vsock for socket forwarding, optional Rosetta translation for x86 binaries.
2. **Container engine** — a containerd-family runtime (OrbStack rolled their own; the OSS equivalent is `containerd` + `runc`).
3. **CLI / API surface** — Docker-compatible socket so existing `docker` / `docker compose` clients "just work".

Every one of those layers has a mature OSS implementation. We assemble them:

| Layer | Choice | Why |
|---|---|---|
| Hypervisor | **`Virtualization.framework`** (Apple, free, in-OS) | Same as OrbStack. Best perf on Apple Silicon. We call it directly from Swift — no extra binary. |
| VM orchestration | **Lima** (bundled binary, hidden from user) | Mature, MIT-licensed, used by Colima & Rancher Desktop. Speaks VZ natively. Handles VM lifecycle, virtio-fs, port forwarding, snapshots. |
| Guest OS | **Lima's default Alpine image** (~150 MB) | Tiny, fast boot, has containerd. We pre-build a custom snapshot with containerd+nerdctl pre-installed so first-launch is sub-5 s. |
| Container engine | **containerd + runc** (inside the VM) | OSS, what every modern runtime uses. |
| CLI inside VM | **nerdctl** (containerd-native; drop-in docker CLI) | Has `nerdctl compose` (compose v2 compatible). |
| Host-side calls | **Swift wrappers around `limactl shell <vm> nerdctl …`** | We never expose a docker socket to the user. Internal only. |
| x86 image translation | **Rosetta for Linux** via `VZLinuxRosettaDirectoryShare` | Same trick OrbStack uses. Lima already supports it. |
| File sharing | **virtiofs** (Lima default) | Host paths → VM paths transparently. |
| Networking | **Lima's `socket_vmnet`** for slirp/bridged net + per-service port forwards | Solves "localhost:30021 just works" without elevation. (`socket_vmnet` needs a one-time helper install; we can vend it or use `usernet` slirp mode which needs nothing.) |

Net effect: we are not rebuilding OrbStack. We're assembling the same primitives OrbStack does, but as a Swift host app that drives Lima invisibly. The user never types `lima` or `nerdctl` — those are implementation details.

**Future migration path:** Apple's `container` framework (released 2024, macOS 15+) does this whole stack natively in Swift with per-container microVMs. As it matures and as we drop macOS 14, we swap Lima out for `container` behind the same `ContainerEngine` protocol. We design `ContainerEngine` as an abstraction from day one to make this swap painless.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ LazyOS.app  (single .app bundle, signed + notarized)    │
│                                                         │
│ ┌────────────────────┐   ┌──────────────────────────┐   │
│ │ SwiftUI front-end  │──▶│ ServiceManager (Core)    │   │
│ └────────────────────┘   │                          │   │
│                          │ uses ContainerEngine ↓   │   │
│                          └──────────────────────────┘   │
│                                       │                 │
│                          ┌────────────▼─────────────┐   │
│                          │ ContainerEngine protocol │   │
│                          ├──────────────────────────┤   │
│                          │ LimaEngine (v1)          │   │
│                          │ AppleContainerEngine     │   │
│                          │   (future, macOS 15+)    │   │
│                          └────────────┬─────────────┘   │
│                                       │                 │
│                          ┌────────────▼─────────────┐   │
│                          │ Resources/runtime/       │   │
│                          │   limactl                │   │
│                          │   lima-guestagent        │   │
│                          │   nerdctl (bundled in    │   │
│                          │     the guest image)     │   │
│                          │   lazyos-vm.qcow2.gz     │   │
│                          │   (pre-baked guest)      │   │
│                          └──────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                       │  (vsock + virtio-fs)
                       ▼
        ┌─────────────────────────────────────┐
        │ "lazyos-vm" — one shared VZ VM      │
        │ Alpine + containerd + nerdctl       │
        │ ~256 MB RAM idle, 2 vCPU            │
        │ Sleeps when no services running     │
        │ (VM pause / unpause < 200 ms)       │
        └─────────────────────────────────────┘
                       │
                       ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ mixpost  │  │  mysql   │  │  redis   │
        │ container│  │ container│  │ container│
        └──────────┘  └──────────┘  └──────────┘
```

### One VM, many services

A single shared VM (named `lazyos-vm`) hosts every service. Costs:

- Idle: ~256 MB RAM, 0% CPU (paused when no services running)
- Running 1 service: VM RAM grows with the containers, not the VM itself

This beats OrbStack's footprint at idle (OrbStack keeps its VM active even with nothing running).

### Aggressive lifecycle

- **VM paused** when no service is running. `VZVirtualMachine.pause()` — full state retained, 0% CPU, RAM reclaimed by macOS pager.
- **VM resumed** on next `start` — under 500 ms.
- **VM stopped** after N minutes of no services and Mac on battery. Cold boot ~3 s with snapshot.
- **VM destroyed** never, unless the user uninstalls LazyOS or hits "Reset" in settings.

### Resource tiers (real this time)

Compose `deploy.resources.limits` becomes containerd cgroup limits inside the VM. We also let the VM grow/shrink: vCPU and RAM are set on VM start to (Light: 1c/1G, Normal: 4c/4G, Heavy: 8c/8G), based on the heaviest currently-running service.

### Compose translation

Two options, we'll pick during week 1:

**A.** `nerdctl compose -f docker-compose.yml up -d` — works out of the box, full compose v2 spec, almost zero work for us. Recommended.
**B.** A tiny Swift `ComposeInterpreter` that reads YAML and issues individual `nerdctl run` calls. More control, more bugs. Only if A has gaps for our templates.

Default to A. Keep B as the fallback strategy.

### Image storage

- containerd image store inside the VM, backed by virtio-blk on a sparse qcow2 file in `~/Library/Application Support/LazyOS/vm/lazyos-vm-data.qcow2`.
- Volumes (Mixpost MySQL data etc.) are containerd volumes inside the same qcow2 — no host-side path mapping needed for service data.
- User-facing "Backups" exports volumes via `nerdctl volume export` → tar.zst on the host's Documents folder. This is the one place host-side files matter.

## Risks & mitigations

1. **Bundling Lima legally.** Lima is Apache 2.0 — fine to bundle. We must include the LICENSE in our .app and credit it in About. Same for nerdctl, containerd, runc.
2. **`socket_vmnet` needs a privileged helper for vmnet bridged networking.** Mitigation: ship in user-mode slirp (`usernet` driver) by default — slower but zero privileges. Offer "Faster networking" toggle later that installs the helper with proper consent.
3. **First-launch download.** Pre-baking the VM image into the .app bloats it (~150–250 MB). Acceptable. Alternative: download on first launch with a friendly progress sheet. *Decision:* bundle it. The promise is "open the app and it works".
4. **VM snapshots after macOS updates.** New kernel + virtio drivers can occasionally break snapshots. Mitigation: detect by version-checking on launch; if mismatch, rebuild from base image (~5 s rebuild).
5. **Performance regressions vs OrbStack.** OrbStack has years of tuning. We will be slower on file I/O at the host↔VM boundary at v1 (virtiofs vs OrbStack's custom). Mitigation: services rarely touch host-mounted files; most I/O is inside the VM and equally fast. Benchmark Mixpost first paint to confirm.
6. **Notarization & entitlements.** Bundled `limactl` is a separately signed CLI. We embed it under `Contents/Resources/runtime/` with appropriate `com.apple.security.cs.allow-unsigned-executable-memory` and `com.apple.security.virtualization` entitlements. Validate notarization works end-to-end early — entitlements bugs surface late and hurt.
7. **VZ requires the app to be a foreground process for some operations.** We already promoted to a regular app via `NSApplicationDelegate`; verify VZ inside that context.
8. **Rosetta-for-Linux requires user consent prompt (one-time) the first time it's used.** That's fine — we'll surface it as "Enable compatibility for x86 apps?" with a clear explanation. Default off; Mixpost and our other catalog templates are arm64 so we don't need it for v1.
9. **macOS 14 vs 15.** Lima works on both. Apple `container` is 15+. We design for Lima now; macOS 15+ users get exactly the same UX. We bump minimum to 15 only when we migrate the engine.
10. **State migration from the OrbStack-based v0 we just shipped.** Tiny user base (you), but: on first launch of the new build, detect existing `services.json`, reset `folderPath` if it pointed at the old OrbStack paths, drop any cached statuses. Templates re-materialize on demand.

## Phased build plan

### Phase 1 — Spike & abstraction (1 day)
- Define `ContainerEngine` protocol in `LazyOSCore/Runtime/`. Methods: `ensureReady()`, `start(service)`, `stop(service)`, `status(service)`, `isHealthy(service)`, `pullProgress(service) -> AsyncStream`, `volumeExport(name, to:)`.
- Replace direct `OrbStackRuntime` references in `ServiceManager` with the protocol. Keep the old `OrbStackRuntime` implementation around behind a debug toggle for comparison while building.

### Phase 2 — Lima integration (2–3 days)
- Acquire `limactl` ARM binary (latest release).
- Write `LimaEngine: ContainerEngine`:
  - `ensureReady()` — extracts bundled `limactl` and the pre-baked VM image into `~/Library/Application Support/LazyOS/vm/` on first run; runs `limactl start` if VM not present.
  - `start(service)` — `limactl shell lazyos-vm -- nerdctl compose -f /lazyos/<slug>/docker-compose.yml --project-name lazyos-<slug> up -d`.
  - File sync: mount `~/Library/Application Support/LazyOS/data/` into the VM at `/lazyos/` via Lima's `mounts:` config (virtiofs).
  - `status` — parse `nerdctl compose ps --format json`.
  - `pullProgress` — tail `nerdctl events --format json` and surface layer-pull events to the UI.
- VM-lifecycle controller (separate from engine): auto-pause after 60 s with no running containers, auto-resume on next start.

### Phase 3 — Guest image (1 day)
- Build a custom Alpine 3.20 image with `containerd`, `nerdctl`, `cni-plugins`, and a `lazyos-init` script that pre-warms containerd and disables anything unnecessary.
- Compress and check into the repo (LFS or bundled binary script that downloads on first build).

### Phase 4 — UX polish for the new realities (1–2 days)
- First-launch sheet: "Setting up runtime… 4 s" with a progress bar (VM cold boot + first-time mount). Hidden on subsequent launches because the VM is already there.
- Pull progress on the Mixpost card: "Downloading Mixpost · 412 MB / 1.2 GB" driven by the events stream.
- Settings → Runtime: shows VM status (Sleeping / Active), RAM tier, "Reset runtime" button (rebuilds VM from base).
- Remove the "OrbStack isn't running" banner entirely. If our engine fails to start, the failure is ours to explain in plain English.

### Phase 5 — Bundling & notarization (1 day)
- Wrap the SPM executable in an Xcode `.app` bundle (App target with Info.plist + entitlements).
- Code-sign the embedded `limactl`. Verify hardened-runtime + library validation entitlements.
- Build a notarized DMG. Test on a clean Mac account.

### Phase 6 — Verification
- `swift test` for the engine abstraction with a mock `ContainerEngine`.
- Live test: clean Mac, install LazyOS DMG, open, click Start on Mixpost, wait for ready, open Mixpost web UI, post a test message, click Stop, quit LazyOS, reopen, click Start again — must be < 3 s warm start.
- Footprint: `Activity Monitor` with LazyOS open + Mixpost running, compare against OrbStack + same Mixpost setup. We don't need to beat OrbStack here; parity is the bar.

## What changes in the current code

| File | Change |
|---|---|
| `Sources/LazyOSCore/Runtime/OrbStackRuntime.swift` | Renamed `LegacyOrbStackEngine` (kept for one release as a debug-only fallback if env `LAZYOS_USE_HOST_DOCKER=1`), gated behind feature flag. |
| `Sources/LazyOSCore/Runtime/ContainerEngine.swift` | **New** protocol. |
| `Sources/LazyOSCore/Runtime/LimaEngine.swift` | **New** primary engine. |
| `Sources/LazyOSCore/Runtime/VMController.swift` | **New** VZ-paused-state lifecycle. |
| `Sources/LazyOSCore/Runtime/ServiceManager.swift` | Depends on `ContainerEngine` protocol, not a concrete class. |
| `Sources/LazyOSApp/Views/LibraryView.swift` | Remove OrbStack banner; add first-run sheet + runtime status in settings. |
| `Resources/runtime/` (in app bundle) | **New** — bundled `limactl`, base VM image, guestagent. |
| `CLAUDE.md` | Update "Runtime model" section: now we run our own VM via Lima; no external runtime expected. |
| Plan & roadmap docs | Reference this file as the v1 runtime plan. |

## Honest scope estimate

- A single focused engineer: **5–8 working days** for a build that boots, runs Mixpost, and DMG-installs cleanly on another Mac.
- Polish, edge cases (sleep/wake on macOS, network reset, Rosetta consent flow, snapshot reset after macOS updates): another **5 days** scattered over the following weeks.
- Calling parity-with-OrbStack with a straight face: needs ~2 weeks of performance work after the above (virtiofs caching tuning, prewarmed image cache, etc.). For our use case (start, run a web app, stop), v1 will already feel essentially identical to OrbStack to a non-technical user.

## Decision points I'm flagging up-front

1. **Bundle the VM image (200–250 MB) inside the .app, or download on first run?** Recommend bundle: matches the "open and it works" promise. Trade-off: bigger download for LazyOS itself.
2. **Apple `container` framework as the primary backend instead of Lima?** Recommend Lima for v1, with `container` ready behind the same protocol when we drop macOS 14. Reason: `container` is still maturing on compose support; Lima+nerdctl is rock-solid today.
3. **socket_vmnet (faster network, needs privileged helper) vs slirp usernet (slower, zero privileges)?** Recommend usernet at v1, helper as an opt-in later. Less to explain to the user.

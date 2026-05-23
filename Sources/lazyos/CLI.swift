import ArgumentParser
import Foundation
import LazyOSCore

@main
struct LazyOSCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lazyos",
        abstract: "Control LazyOS self-hosted apps from the terminal.",
        subcommands: [List.self, Install.self, Start.self, Stop.self, Status.self, Open.self,
                      Catalog.self, Remove.self, Schedule.self, Unschedule.self, Tier.self,
                      Backup.self, Restore.self, AddFolder.self, Usage.self],
        defaultSubcommand: List.self
    )
}

extension LazyOSCLI {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed apps.")
        func run() {
            let mgr = ServiceManager.shared
            mgr.bootstrapIfNeeded()
            let services = mgr.library()
            if services.isEmpty { print("No apps installed. Try: lazyos catalog"); return }
            for s in services {
                let status = mgr.status(slug: s.slug)
                let schedule = s.schedule.flatMap { $0.enabled ? CronParser.describe($0.startCron) : nil } ?? "-"
                print("\(statusGlyph(status))  \(s.name.padding(toLength: 14, withPad: " ", startingAt: 0))  \(s.webURL.padding(toLength: 26, withPad: " ", startingAt: 0))  \(schedule)")
            }
        }
    }

    struct Catalog: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show available apps.")
        func run() {
            for e in LazyOSCore.Catalog.shared.entries() {
                print("\(e.slug.padding(toLength: 12, withPad: " ", startingAt: 0))  \(e.name) — \(e.blurb)")
            }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install an app from the catalog.")
        @Argument var slug: String
        func run() throws {
            guard let entry = LazyOSCore.Catalog.shared.entries().first(where: { $0.slug == slug }) else {
                throw ValidationError("Unknown app '\(slug)'. Try: lazyos catalog")
            }
            let svc = try ServiceManager.shared.install(entry)
            print("Installed \(svc.name) at \(svc.webURL)")
        }
    }

    struct AddFolder: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add-folder",
                                                        abstract: "Add a custom app from a folder with docker-compose.yml.")
        @Argument var path: String
        func run() throws {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let svc = try ServiceManager.shared.installCustom(folder: url)
            print("Added \(svc.name) at \(svc.webURL)")
        }
    }

    struct Start: ParsableCommand {
        @Argument var slug: String
        func run() throws { try ServiceManager.shared.start(slug: slug); print("Starting \(slug)…") }
    }

    struct Stop: ParsableCommand {
        @Argument var slug: String
        func run() throws { try ServiceManager.shared.stop(slug: slug); print("Stopped \(slug).") }
    }

    struct Status: ParsableCommand {
        @Argument var slug: String
        @Flag(name: .long, help: "Dump diagnostics for this service") var diag = false
        func run() {
            if diag { Diag.dump(slug: slug); return }
            print(ServiceManager.shared.status(slug: slug).rawValue)
        }
    }

    struct Open: ParsableCommand {
        @Argument var slug: String
        func run() throws {
            guard let svc = ServiceManager.shared.find(slug: slug) else { throw ValidationError("Not installed: \(slug)") }
            _ = Shell.run("/usr/bin/open", [svc.webURL])
        }
    }

    struct Remove: ParsableCommand {
        @Argument var slug: String
        func run() throws { try ServiceManager.shared.uninstall(slug: slug); print("Removed \(slug).") }
    }

    struct Schedule: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set a recurring start/stop schedule.")
        @Argument(help: "App slug") var slug: String
        @Argument(help: "Start cron expression, e.g. \"0 9 * * 1-5\"") var startCron: String
        @Argument(help: "Stop cron expression, e.g. \"0 19 * * 1-5\"") var stopCron: String
        func run() throws {
            let sched = LazyOSCore.Schedule(enabled: true, startCron: startCron, stopCron: stopCron)
            try ServiceManager.shared.setSchedule(slug: slug, schedule: sched)
            print("Scheduled: \(CronParser.describe(startCron)) → \(CronParser.describe(stopCron))")
        }
    }

    struct Unschedule: ParsableCommand {
        @Argument var slug: String
        func run() throws { try ServiceManager.shared.setSchedule(slug: slug, schedule: nil); print("Schedule removed for \(slug).") }
    }

    struct Tier: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set the resource tier (light|normal|heavy).")
        @Argument var slug: String
        @Argument var tier: String
        func run() throws {
            guard let t = ResourceTier(rawValue: tier.lowercased()) else {
                throw ValidationError("Tier must be light, normal, or heavy.")
            }
            ServiceManager.shared.setResourceTier(slug: slug, tier: t)
            print("Set \(slug) → \(t.label) (\(t.detail))")
        }
    }

    struct Backup: ParsableCommand {
        @Argument var slug: String
        func run() throws {
            let url = try ServiceManager.shared.backup(slug: slug)
            print("Backed up to: \(url.path)")
        }
    }

    struct Restore: ParsableCommand {
        @Argument var slug: String
        @Argument(help: "Path to a .tar.zst backup file") var file: String
        func run() throws {
            guard let svc = ServiceManager.shared.find(slug: slug) else { throw ValidationError("Not installed: \(slug)") }
            let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
            let mgr = BackupManager(engine: ServiceManager.shared.engine)
            _ = try mgr.restore(svc, from: url)
            print("Restored \(slug) from \(url.lastPathComponent).")
        }
    }

    struct Usage: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show CPU/RAM usage of running apps.")
        func run() {
            let s = UsageProbe.shared.sample()
            print(String(format: "Total: %.0f%% CPU · %@ RAM · %d containers",
                         s.overall.cpuPercent,
                         formatBytes(s.overall.memoryBytes),
                         s.overall.runningContainers))
            for (proj, u) in s.perProject.sorted(by: { $0.key < $1.key }) {
                print(String(format: "  %-30@  %.0f%%   %@", proj as NSString, u.cpuPercent, formatBytes(u.memoryBytes)))
            }
        }
    }
}

private func statusGlyph(_ s: ServiceStatus) -> String {
    switch s {
    case .running: return "●"
    case .starting: return "◐"
    case .stopping: return "◑"
    case .error: return "✕"
    case .off: return "○"
    }
}

private func formatBytes(_ b: Int64) -> String {
    let mb = Double(b) / 1024 / 1024
    if mb > 1024 { return String(format: "%.1f GB", mb / 1024) }
    return String(format: "%.0f MB", mb)
}

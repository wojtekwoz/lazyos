import Foundation

/// Writes per-service launchd plists under ~/Library/LaunchAgents that call
/// the bundled `lazyos` CLI to start or stop a service at scheduled times.
public final class LaunchdScheduler {
    public static let shared = LaunchdScheduler()

    private var agentsDir: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cliPath() -> String {
        // Prefer a bundled CLI inside the .app. Fall back to a known PATH location.
        if let bundleCLI = Bundle.main.url(forAuxiliaryExecutable: "lazyos")?.path,
           FileManager.default.isExecutableFile(atPath: bundleCLI) {
            return bundleCLI
        }
        for c in ["/usr/local/bin/lazyos", "/opt/homebrew/bin/lazyos"] {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        // Final fallback for dev: the SPM build product.
        let dev = "\(FileManager.default.currentDirectoryPath)/.build/arm64-apple-macosx/release/lazyos"
        return dev
    }

    public func apply(_ schedule: Schedule, for slug: String) throws {
        try remove(slug: slug)
        guard schedule.enabled else { return }

        try writePlist(label: "co.lazyos.\(slug).start",
                       action: "start",
                       slug: slug,
                       cron: schedule.startCron)
        try writePlist(label: "co.lazyos.\(slug).stop",
                       action: "stop",
                       slug: slug,
                       cron: schedule.stopCron)
    }

    public func remove(slug: String) throws {
        for suffix in ["start", "stop"] {
            let label = "co.lazyos.\(slug).\(suffix)"
            let path = agentsDir.appendingPathComponent("\(label).plist")
            _ = Shell.run("/bin/launchctl", ["unload", path.path])
            try? FileManager.default.removeItem(at: path)
        }
    }

    public func isApplied(slug: String) -> Bool {
        let p = agentsDir.appendingPathComponent("co.lazyos.\(slug).start.plist")
        return FileManager.default.fileExists(atPath: p.path)
    }

    // MARK: - Implementation

    private func writePlist(label: String, action: String, slug: String, cron: String) throws {
        guard let intervals = CronParser.launchdCalendarIntervals(cron) else {
            throw LazyOSError.composeFailed("Invalid schedule expression: \(cron)")
        }

        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [cliPath(), action, slug],
            "RunAtLoad": false,
            "StandardOutPath": "/tmp/\(label).log",
            "StandardErrorPath": "/tmp/\(label).err",
        ]
        if intervals.count == 1 {
            plist["StartCalendarInterval"] = intervals[0]
        } else {
            plist["StartCalendarInterval"] = intervals
        }

        let path = agentsDir.appendingPathComponent("\(label).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: path, options: .atomic)
        _ = Shell.run("/bin/launchctl", ["unload", path.path])
        _ = Shell.run("/bin/launchctl", ["load", path.path])
    }
}

import Foundation

/// Exports a service's named docker volumes into a single .tar.zst file under
/// ~/Documents/LazyOS Backups. Uses an ephemeral container in the running VM
/// (`docker run --rm -v <vol>:/src -v <out>:/out alpine tar -caf …`) so we
/// don't need any host-side tar / zstd binary.
public final class BackupManager {
    public static let shared = BackupManager()

    private let engine: ContainerEngine

    public init(engine: ContainerEngine = LimaEngine()) {
        self.engine = engine
    }

    public var backupsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("LazyOS Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Volume names follow `<projectName>_<defined-name>` for docker compose.
    /// Mixpost defines mixpost-data, mixpost-mysql, mixpost-redis →
    /// `lazyos-mixpost_mixpost-data` etc.
    public func volumeNames(for service: Service) -> [String] {
        let proj = "lazyos-\(service.slug)"
        // We parse the compose file very loosely for top-level volumes:
        let composePath = URL(fileURLWithPath: service.folderPath).appendingPathComponent("docker-compose.yml").path
        guard let text = try? String(contentsOfFile: composePath, encoding: .utf8) else { return [] }
        var names: [String] = []
        var inVolumesBlock = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("volumes:") { inVolumesBlock = true; continue }
            if inVolumesBlock {
                if line.first == " " || line.first == "\t" {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let colon = trimmed.firstIndex(of: ":") {
                        names.append("\(proj)_\(String(trimmed[..<colon]))")
                    }
                } else if !line.isEmpty {
                    inVolumesBlock = false
                }
            }
        }
        return names
    }

    @discardableResult
    public func backup(_ service: Service) throws -> URL {
        guard let lima = engine as? LimaEngine else {
            throw LazyOSError.composeFailed("Backups currently require the bundled runtime.")
        }
        let stamp = Self.timestamp()
        let outName = "\(service.slug)-\(stamp).tar.zst"
        let outURL = backupsDir.appendingPathComponent(outName)
        // We write into the backups dir; mount that dir into the helper container.
        let vols = volumeNames(for: service)
        guard !vols.isEmpty else {
            throw LazyOSError.composeFailed("No volumes found to back up for \(service.name).")
        }

        // Build a single helper command: tar everything to /out/<file>
        // Mount all named volumes under /src/<volume>.
        var args: [String] = ["run", "--rm"]
        for v in vols { args.append(contentsOf: ["-v", "\(v):/src/\(v):ro"]) }
        args.append(contentsOf: ["-v", "\(backupsDir.path):/out", "alpine:3.20",
                                 "sh", "-c",
                                 "apk add --no-cache zstd >/dev/null && tar -C /src -cf - . | zstd -q -19 -o /out/\(outName)"])
        let r = lima.runDocker(args)
        if !r.ok {
            throw LazyOSError.composeFailed(ErrorTranslator.friendly(r.stderr))
        }
        return outURL
    }

    @discardableResult
    public func restore(_ service: Service, from file: URL) throws -> Bool {
        guard let lima = engine as? LimaEngine else {
            throw LazyOSError.composeFailed("Restores currently require the bundled runtime.")
        }
        let vols = volumeNames(for: service)
        var args: [String] = ["run", "--rm"]
        for v in vols { args.append(contentsOf: ["-v", "\(v):/dst/\(v)"]) }
        args.append(contentsOf: ["-v", "\(file.deletingLastPathComponent().path):/in:ro", "alpine:3.20",
                                 "sh", "-c",
                                 "apk add --no-cache zstd >/dev/null && zstd -dc /in/\(file.lastPathComponent) | tar -C /dst -xf -"])
        let r = lima.runDocker(args)
        return r.ok
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}

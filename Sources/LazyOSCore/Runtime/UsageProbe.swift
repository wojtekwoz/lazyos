import Foundation

public struct ServiceUsage: Sendable, Hashable {
    public let cpuPercent: Double   // 0...n×100 (containerd reports % of one core; we sum across containers)
    public let memoryBytes: Int64
    public let memoryLimitBytes: Int64
}

public struct OverallUsage: Sendable, Hashable {
    public let cpuPercent: Double
    public let memoryBytes: Int64
    public let memoryLimitBytes: Int64
    public let runningContainers: Int

    public static let zero = OverallUsage(cpuPercent: 0, memoryBytes: 0, memoryLimitBytes: 0, runningContainers: 0)
}

public final class UsageProbe {
    public static let shared = UsageProbe()
    private let engine: LimaEngine

    public init(engine: LimaEngine = LimaEngine()) { self.engine = engine }

    /// One-shot `docker stats --no-stream` parsed into ServiceUsage per project.
    public func sample() -> (overall: OverallUsage, perProject: [String: ServiceUsage]) {
        let r = engine.runDocker([
            "stats", "--no-stream", "--format",
            "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.Container}}"
        ])
        guard r.ok else { return (.zero, [:]) }

        var totalCPU = 0.0
        var totalMem: Int64 = 0
        var totalLimit: Int64 = 0
        var count = 0
        var perProject: [String: (Double, Int64, Int64)] = [:]

        for line in r.stdout.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { continue }
            let name = parts[0]                      // e.g. lazyos-mixpost-mysql-1
            let cpu = parseCPU(parts[1])             // 0.13% -> 0.13
            let (mem, lim) = parseMem(parts[2])      // "11.4MiB / 4GiB"
            count += 1
            totalCPU += cpu; totalMem += mem; totalLimit += lim
            // Group by service project: lazyos-<slug>
            if let project = projectName(from: name) {
                var (c, m, l) = perProject[project] ?? (0, 0, 0)
                c += cpu; m += mem; l += lim
                perProject[project] = (c, m, l)
            }
        }
        let overall = OverallUsage(cpuPercent: totalCPU, memoryBytes: totalMem, memoryLimitBytes: totalLimit, runningContainers: count)
        let mapped = perProject.mapValues { ServiceUsage(cpuPercent: $0.0, memoryBytes: $0.1, memoryLimitBytes: $0.2) }
        return (overall, mapped)
    }

    // MARK: - Parsing

    private func parseCPU(_ s: String) -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        return Double(trimmed) ?? 0
    }

    private func parseMem(_ s: String) -> (Int64, Int64) {
        // "11.4MiB / 4GiB"
        let parts = s.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return (0, 0) }
        return (parseSize(parts[0]), parseSize(parts[1]))
    }

    private func parseSize(_ s: String) -> Int64 {
        let digits = s.filter { "0123456789.".contains($0) }
        guard let value = Double(digits) else { return 0 }
        let unit = s.replacingOccurrences(of: digits, with: "").trimmingCharacters(in: .whitespaces).lowercased()
        let mult: Double
        switch unit {
        case "b": mult = 1
        case "kib", "kb", "k": mult = 1024
        case "mib", "mb", "m": mult = 1024 * 1024
        case "gib", "gb", "g": mult = 1024 * 1024 * 1024
        case "tib", "tb", "t": mult = 1024 * 1024 * 1024 * 1024
        default: mult = 1
        }
        return Int64(value * mult)
    }

    private func projectName(from containerName: String) -> String? {
        // Container names look like "lazyos-mixpost-mysql-1" — the project name
        // is everything up to the last two `-` segments (service + replica index).
        let parts = containerName.split(separator: "-")
        guard parts.count >= 3 else { return nil }
        return parts.prefix(parts.count - 2).joined(separator: "-")
    }
}

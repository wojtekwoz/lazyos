import Foundation

/// Drives a Lima-managed VZ VM with Docker inside. The VM exposes a
/// docker socket under ~/.lima/<vm>/sock/docker.sock; we set DOCKER_HOST
/// to that and use the host's `docker compose` CLI as a thin client.
public final class LimaEngine: ContainerEngine {
    public let displayName = "LazyOS runtime"
    public let instanceName: String

    public init(instanceName: String = "lazyos") {
        self.instanceName = instanceName
    }

    // MARK: - Paths

    private var limactlPath: String {
        let candidates = [
            "/opt/homebrew/bin/limactl",
            "/usr/local/bin/limactl",
            // Future: embedded inside the app bundle.
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "limactl"
    }

    private var dockerPath: String {
        let candidates = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/usr/bin/docker",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "docker"
    }

    private var dockerSocket: String {
        let home = NSHomeDirectory()
        return "\(home)/.lima/\(instanceName)/sock/docker.sock"
    }

    private var dockerHostEnv: [String: String] {
        ["DOCKER_HOST": "unix://\(dockerSocket)"]
    }

    private func limactlInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: limactlPath)
    }

    private func vmExists() -> Bool {
        guard limactlInstalled() else { return false }
        let r = Shell.run(limactlPath, ["list", "--format", "{{.Name}}"])
        return r.ok && r.stdout.split(whereSeparator: \.isNewline).map(String.init).contains(instanceName)
    }

    private func vmStatus() -> String {
        guard limactlInstalled(), vmExists() else { return "Missing" }
        let r = Shell.run(limactlPath, ["list", "--format", "{{.Status}}", instanceName])
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dockerSocketReady() -> Bool {
        FileManager.default.fileExists(atPath: dockerSocket)
    }

    // MARK: - ContainerEngine

    public func isAvailable() -> Bool {
        guard limactlInstalled(), vmStatus() == "Running", dockerSocketReady() else { return false }
        let r = Shell.run(dockerPath, ["info", "--format", "{{.ServerVersion}}"], env: dockerHostEnv)
        return r.ok
    }

    public func ensureReady() -> Bool {
        guard limactlInstalled() else { return false }
        if !vmExists() {
            // Create from the bundled docker template (Lima 2.x syntax).
            _ = Shell.run(limactlPath, ["start", "--name=\(instanceName)", "--tty=false", "template:docker"])
        } else if vmStatus() != "Running" {
            _ = Shell.run(limactlPath, ["start", "--tty=false", instanceName])
        }
        // Wait briefly for the docker socket to surface.
        for _ in 0..<20 {
            if dockerSocketReady() { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return isAvailable()
    }

    public var setupHint: EngineSetupHint? {
        if !limactlInstalled() {
            return EngineSetupHint(
                title: "Setting up runtime…",
                body: "LazyOS needs to install its local runtime (Lima). Run this once in Terminal: brew install lima",
                actionLabel: "Copy install command",
                actionShellCommand: "brew install lima"
            )
        }
        if !vmExists() || vmStatus() != "Running" {
            return EngineSetupHint(
                title: "Starting runtime…",
                body: "First start takes about a minute while LazyOS prepares its virtual machine.",
                actionLabel: nil,
                actionShellCommand: nil
            )
        }
        return nil
    }

    private func composeArgs(for service: Service) -> [String] {
        ["compose",
         "-f", service.folderPath + "/docker-compose.yml",
         "--project-name", "lazyos-\(service.slug)"]
    }

    private func envForCompose(_ service: Service) -> [String: String] {
        var env = dockerHostEnv
        env["LAZYOS_PORT"] = "\(service.port)"
        for (k, v) in service.env { env[k] = v }
        return env
    }

    public func start(_ service: Service) throws {
        if !isAvailable() {
            _ = ensureReady()
            guard isAvailable() else { throw LazyOSError.orbStackMissing }
        }
        let r = Shell.run(dockerPath, composeArgs(for: service) + ["up", "-d"], env: envForCompose(service))
        if !r.ok {
            throw LazyOSError.composeFailed(ErrorTranslator.friendly(r.stderr.isEmpty ? r.stdout : r.stderr))
        }
    }

    public func stop(_ service: Service) throws {
        guard isAvailable() else { throw LazyOSError.orbStackMissing }
        let r = Shell.run(dockerPath, composeArgs(for: service) + ["down"], env: envForCompose(service))
        if !r.ok {
            throw LazyOSError.composeFailed(ErrorTranslator.friendly(r.stderr.isEmpty ? r.stdout : r.stderr))
        }
    }

    public func status(_ service: Service) -> ServiceStatus {
        guard isAvailable() else { return .off }
        let r = Shell.run(dockerPath, composeArgs(for: service) + ["ps", "--format", "json"], env: envForCompose(service))
        guard r.ok, !r.stdout.isEmpty else { return .off }
        var running = false, starting = false
        // docker compose ps emits a JSON array OR newline-delimited JSON depending on version.
        let trimmed = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for obj in arr {
                    let state = (obj["State"] as? String ?? "").lowercased()
                    if state == "running" { running = true }
                    if ["created", "restarting", "paused"].contains(state) { starting = true }
                }
            }
        } else {
            for line in trimmed.split(whereSeparator: \.isNewline) {
                guard let data = String(line).data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let state = (obj["State"] as? String ?? "").lowercased()
                if state == "running" { running = true }
                if ["created", "restarting", "paused"].contains(state) { starting = true }
            }
        }
        if running { return .running }
        if starting { return .starting }
        return .off
    }

    /// Public helper used by BackupManager and UsageProbe. Runs a raw docker
    /// invocation against the VM-side daemon.
    public func runDocker(_ args: [String], env extra: [String: String] = [:]) -> ShellResult {
        var env = dockerHostEnv
        for (k, v) in extra { env[k] = v }
        return Shell.run(dockerPath, args, env: env)
    }

    public func isHealthy(_ service: Service, timeout: TimeInterval) -> Bool {
        guard let url = URL(string: service.webURL + service.healthcheckPath) else { return false }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var healthy = false
        URLSession.shared.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                healthy = true
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 0.5)
        return healthy
    }
}

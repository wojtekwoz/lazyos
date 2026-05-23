// Diagnostic helper. Run with: lazyos --diag mixpost
// (We add the flag wiring elsewhere; this file just exposes a function.)
import Foundation
import LazyOSCore

enum Diag {
    static func dump(slug: String) {
        guard let svc = ServiceManager.shared.find(slug: slug) else { print("DIAG: service not found"); return }
        let eng = LimaEngine()
        print("DIAG: limactl=\(FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/limactl"))")
        print("DIAG: docker.sock exists=\(FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/.lima/lazyos/sock/docker.sock"))")
        print("DIAG: isAvailable=\(eng.isAvailable())")
        print("DIAG: engine.status(svc)=\(eng.status(svc).rawValue)")

        // Raw shell call
        let env: [String: String] = [
            "DOCKER_HOST": "unix://\(NSHomeDirectory())/.lima/lazyos/sock/docker.sock",
            "LAZYOS_PORT": "\(svc.port)",
            "LAZYOS_APP_KEY": svc.env["LAZYOS_APP_KEY"] ?? "",
        ]
        let r = Shell.run("/usr/local/bin/docker",
                          ["compose", "-f", svc.folderPath + "/docker-compose.yml",
                           "--project-name", "lazyos-\(slug)", "ps", "--format", "json"],
                          env: env)
        print("DIAG: shell ok=\(r.ok) exit=\(r.exitCode)")
        print("DIAG: stdout first 400 chars:")
        print(String(r.stdout.prefix(400)))
        print("DIAG: stderr first 400 chars:")
        print(String(r.stderr.prefix(400)))
    }
}

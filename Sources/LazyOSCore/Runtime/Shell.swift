import Foundation

public struct ShellResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { exitCode == 0 }
}

public enum Shell {
    @discardableResult
    public static func run(
        _ launchPath: String,
        _ args: [String],
        cwd: URL? = nil,
        env: [String: String]? = nil
    ) -> ShellResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        if let cwd { proc.currentDirectoryURL = cwd }

        var merged = ProcessInfo.processInfo.environment
        // Ensure docker can find common paths.
        let extraPath = "/Applications/OrbStack.app/Contents/MacOS/xbin:/opt/homebrew/bin:/usr/local/bin"
        merged["PATH"] = (merged["PATH"].map { "\(extraPath):\($0)" }) ?? extraPath
        if let env { for (k, v) in env { merged[k] = v } }
        proc.environment = merged

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: "Failed to launch: \(error.localizedDescription)")
        }
        proc.waitUntilExit()

        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        return ShellResult(
            exitCode: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

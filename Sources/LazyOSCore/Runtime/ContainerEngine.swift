import Foundation

/// Abstraction over the container engine (Lima today, Apple `container`
/// framework tomorrow). The UI talks to ServiceManager which talks to this.
public protocol ContainerEngine: AnyObject {
    /// Display name, used in diagnostics.
    var displayName: String { get }

    /// Is the engine installed and the VM/daemon reachable?
    func isAvailable() -> Bool

    /// Best-effort startup of the underlying VM/daemon if it's installed but stopped.
    /// Returns true if available after the attempt.
    func ensureReady() -> Bool

    /// Path that should be reported to the user if the engine is missing.
    var setupHint: EngineSetupHint? { get }

    func start(_ service: Service) throws
    func stop(_ service: Service) throws
    func status(_ service: Service) -> ServiceStatus
    func isHealthy(_ service: Service, timeout: TimeInterval) -> Bool
}

public struct EngineSetupHint: Sendable {
    public let title: String
    public let body: String
    public let actionLabel: String?
    public let actionShellCommand: String?

    public init(title: String, body: String, actionLabel: String? = nil, actionShellCommand: String? = nil) {
        self.title = title
        self.body = body
        self.actionLabel = actionLabel
        self.actionShellCommand = actionShellCommand
    }
}

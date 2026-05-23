import Foundation

public final class ServiceManager {
    public static let shared = ServiceManager()
    private let store = ServiceStore()
    public let engine: ContainerEngine

    public init(engine: ContainerEngine = LimaEngine()) {
        self.engine = engine
    }

    // MARK: - Library

    public func library() -> [Service] {
        store.load()
    }

    public func find(slug: String) -> Service? {
        store.find(slug: slug)
    }

    public func isInstalled(slug: String) -> Bool {
        store.find(slug: slug) != nil
    }

    /// Seed bootstrap content on first launch. Pre-installs Mixpost so the
    /// user can be productive immediately.
    public func bootstrapIfNeeded() {
        if library().isEmpty {
            if let entry = Catalog.shared.entries().first(where: { $0.slug == "mixpost" }) {
                _ = try? install(entry)
            }
        }
    }

    @discardableResult
    public func install(_ entry: CatalogEntry) throws -> Service {
        if let existing = store.find(slug: entry.slug) { return existing }
        let folder = try Catalog.shared.materialize(slug: entry.slug)
        let port = PortPicker.pick(preferred: entry.defaultPort)
        var env: [String: String] = [:]
        if entry.needsAppKey {
            env["LAZYOS_APP_KEY"] = AppKeyGen.generate()
        }
        let service = Service(
            slug: entry.slug,
            name: entry.name,
            blurb: entry.blurb,
            iconSymbol: entry.iconSymbol,
            accentHex: entry.accentHex,
            folderPath: folder.path,
            port: port,
            webURL: "http://localhost:\(port)",
            healthcheckPath: entry.healthcheckPath,
            env: env,
            firstRunHintMB: entry.firstRunHintMB
        )
        store.upsert(service)
        return service
    }

    public func uninstall(slug: String) throws {
        if let s = store.find(slug: slug) {
            try? engine.stop(s)
        }
        store.remove(slug: slug)
    }

    // MARK: - Lifecycle

    public func start(slug: String) throws {
        guard var service = store.find(slug: slug) else { return }
        // Apply the current resource tier override before each start so changes
        // take effect on the next compose up.
        ResourceTierOverride.write(for: service)
        try engine.start(service)
        service.lastStartedAt = Date()
        store.upsert(service)
    }

    // MARK: - Settings

    public func setSchedule(slug: String, schedule: Schedule?) throws {
        guard var service = store.find(slug: slug) else { return }
        service.schedule = schedule
        store.upsert(service)
        if let s = schedule {
            try LaunchdScheduler.shared.apply(s, for: slug)
        } else {
            try LaunchdScheduler.shared.remove(slug: slug)
        }
    }

    public func setResourceTier(slug: String, tier: ResourceTier) {
        guard var service = store.find(slug: slug) else { return }
        service.resourceTier = tier
        store.upsert(service)
        ResourceTierOverride.write(for: service)
    }

    public func setAutoStopOnSleep(slug: String, value: Bool) {
        guard var service = store.find(slug: slug) else { return }
        service.autoStopOnSleep = value
        store.upsert(service)
    }

    public func setAutoStopAfterIdleMinutes(slug: String, minutes: Int?) {
        guard var service = store.find(slug: slug) else { return }
        service.autoStopAfterIdleMinutes = minutes
        store.upsert(service)
    }

    @discardableResult
    public func backup(slug: String) throws -> URL {
        guard var service = store.find(slug: slug) else {
            throw LazyOSError.composeFailed("Service not installed: \(slug)")
        }
        let backups = BackupManager(engine: engine)
        let url = try backups.backup(service)
        service.lastBackupAt = Date()
        store.upsert(service)
        return url
    }

    @discardableResult
    public func installCustom(folder: URL) throws -> Service {
        let composeFile = folder.appendingPathComponent("docker-compose.yml")
        guard FileManager.default.fileExists(atPath: composeFile.path) else {
            throw LazyOSError.composeFailed("That folder doesn't contain a docker-compose.yml.")
        }
        let slug = folder.lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-")
        if let existing = store.find(slug: slug) { return existing }
        let port = PortPicker.pick(preferred: 30100)
        let service = Service(
            slug: slug,
            name: folder.lastPathComponent.capitalized,
            blurb: "Custom app from \(folder.path)",
            iconSymbol: "shippingbox.fill",
            accentHex: "#888888",
            folderPath: folder.path,
            port: port,
            webURL: "http://localhost:\(port)"
        )
        store.upsert(service)
        return service
    }

    /// Force a new port for a service. Re-stops + restarts if it was running.
    @discardableResult
    public func repickPort(slug: String) throws -> Service {
        guard var service = store.find(slug: slug) else {
            throw LazyOSError.composeFailed("Service \(slug) not installed")
        }
        let wasRunning = engine.status(service) != .off
        if wasRunning { try? engine.stop(service) }
        service.port = PortPicker.pick(preferred: service.port == 30000 ? 30021 : service.port)
        service.webURL = "http://localhost:\(service.port)"
        store.upsert(service)
        if wasRunning { try engine.start(service) }
        return service
    }

    public func stop(slug: String) throws {
        guard let service = store.find(slug: slug) else { return }
        try engine.stop(service)
    }

    public func status(slug: String) -> ServiceStatus {
        guard let service = store.find(slug: slug) else { return .off }
        return engine.status(service)
    }

    /// Returns true when the service is both running and responding to HTTP.
    /// UI can use this to show a "Warming up" hint while running but not yet healthy.
    public func isHealthy(slug: String) -> Bool {
        guard let service = store.find(slug: slug) else { return false }
        return engine.isHealthy(service, timeout: 1.0)
    }

    public func runtimeAvailable() -> Bool {
        engine.isAvailable()
    }
}

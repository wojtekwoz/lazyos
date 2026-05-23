import Foundation

public enum ServiceStatus: String, Codable, Sendable {
    case off
    case starting
    case running
    case stopping
    case error
}

public enum ResourceTier: String, Codable, Sendable, CaseIterable {
    case light, normal, heavy

    public var label: String {
        switch self {
        case .light: return "Light"
        case .normal: return "Normal"
        case .heavy: return "Heavy"
        }
    }

    public var detail: String {
        switch self {
        case .light: return "0.5 cores · 512 MB"
        case .normal: return "2 cores · 2 GB"
        case .heavy: return "6 cores · 6 GB"
        }
    }
}

public struct Service: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var slug: String
    public var name: String
    public var blurb: String
    public var iconSymbol: String
    public var accentHex: String
    public var folderPath: String     // absolute path to dir containing docker-compose.yml
    public var port: Int
    public var webURL: String         // http://localhost:<port>
    public var healthcheckPath: String
    public var resourceTier: ResourceTier
    public var env: [String: String]  // additional env (APP_KEY etc.)
    public var lastStartedAt: Date?
    public var firstRunHintMB: Int?
    public var schedule: Schedule?
    public var autoStopOnSleep: Bool
    public var autoStopAfterIdleMinutes: Int?  // nil = never
    public var lastBackupAt: Date?

    public init(
        id: UUID = UUID(),
        slug: String,
        name: String,
        blurb: String,
        iconSymbol: String,
        accentHex: String,
        folderPath: String,
        port: Int,
        webURL: String,
        healthcheckPath: String = "/",
        resourceTier: ResourceTier = .normal,
        env: [String: String] = [:],
        lastStartedAt: Date? = nil,
        firstRunHintMB: Int? = nil,
        schedule: Schedule? = nil,
        autoStopOnSleep: Bool = true,
        autoStopAfterIdleMinutes: Int? = nil,
        lastBackupAt: Date? = nil
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.blurb = blurb
        self.iconSymbol = iconSymbol
        self.accentHex = accentHex
        self.folderPath = folderPath
        self.port = port
        self.webURL = webURL
        self.healthcheckPath = healthcheckPath
        self.resourceTier = resourceTier
        self.env = env
        self.lastStartedAt = lastStartedAt
        self.firstRunHintMB = firstRunHintMB
        self.schedule = schedule
        self.autoStopOnSleep = autoStopOnSleep
        self.autoStopAfterIdleMinutes = autoStopAfterIdleMinutes
        self.lastBackupAt = lastBackupAt
    }

    public var isCustom: Bool {
        // A service whose folder doesn't live in our managed data dir is user-added.
        !folderPath.hasPrefix(Paths.servicesData.path)
    }

    // MARK: - Tolerant Codable
    // Older services.json files don't have the newer fields. Provide defaults
    // for any missing key so we never lose the on-disk library after an upgrade.

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, blurb, iconSymbol, accentHex, folderPath, port, webURL
        case healthcheckPath, resourceTier, env, lastStartedAt, firstRunHintMB
        case schedule, autoStopOnSleep, autoStopAfterIdleMinutes, lastBackupAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slug = try c.decode(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        blurb = try c.decode(String.self, forKey: .blurb)
        iconSymbol = try c.decode(String.self, forKey: .iconSymbol)
        accentHex = try c.decode(String.self, forKey: .accentHex)
        folderPath = try c.decode(String.self, forKey: .folderPath)
        port = try c.decode(Int.self, forKey: .port)
        webURL = try c.decode(String.self, forKey: .webURL)
        healthcheckPath = try c.decodeIfPresent(String.self, forKey: .healthcheckPath) ?? "/"
        resourceTier = try c.decodeIfPresent(ResourceTier.self, forKey: .resourceTier) ?? .normal
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        lastStartedAt = try c.decodeIfPresent(Date.self, forKey: .lastStartedAt)
        firstRunHintMB = try c.decodeIfPresent(Int.self, forKey: .firstRunHintMB)
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule)
        autoStopOnSleep = try c.decodeIfPresent(Bool.self, forKey: .autoStopOnSleep) ?? true
        autoStopAfterIdleMinutes = try c.decodeIfPresent(Int.self, forKey: .autoStopAfterIdleMinutes)
        lastBackupAt = try c.decodeIfPresent(Date.self, forKey: .lastBackupAt)
    }
}

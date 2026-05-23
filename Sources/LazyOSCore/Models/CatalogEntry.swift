import Foundation

public struct CatalogEntry: Codable, Identifiable, Hashable, Sendable {
    public var slug: String
    public var name: String
    public var blurb: String
    public var iconSymbol: String
    public var accentHex: String
    public var defaultPort: Int
    public var healthcheckPath: String
    public var needsAppKey: Bool
    public var firstRunHintMB: Int?

    public var id: String { slug }
}

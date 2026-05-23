import Foundation

public final class Catalog {
    public static let shared = Catalog()

    public func entries() -> [CatalogEntry] {
        guard let templatesDir = Bundle.module.url(forResource: "Templates", withExtension: nil) else {
            return []
        }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: templatesDir.path) else { return [] }
        return names.compactMap { name in
            let metaURL = templatesDir.appendingPathComponent(name).appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let entry = try? JSONDecoder().decode(CatalogEntry.self, from: data)
            else { return nil }
            return entry
        }.sorted { $0.name < $1.name }
    }

    public func templateFolder(slug: String) -> URL? {
        Bundle.module.url(forResource: "Templates", withExtension: nil)?
            .appendingPathComponent(slug, isDirectory: true)
    }

    /// Copy compose template into the user's data dir and return the destination folder.
    public func materialize(slug: String) throws -> URL {
        guard let src = templateFolder(slug: slug) else {
            throw LazyOSError.catalogTemplateMissing(slug)
        }
        let dst = Paths.serviceFolder(slug: slug)
        let composeSrc = src.appendingPathComponent("docker-compose.yml")
        let composeDst = dst.appendingPathComponent("docker-compose.yml")
        try? FileManager.default.removeItem(at: composeDst)
        try FileManager.default.copyItem(at: composeSrc, to: composeDst)
        return dst
    }
}

public enum LazyOSError: LocalizedError {
    case catalogTemplateMissing(String)
    case orbStackMissing
    case composeFailed(String)
    case portUnavailable(Int)

    public var errorDescription: String? {
        switch self {
        case .catalogTemplateMissing(let s): return "Template for \(s) is missing."
        case .orbStackMissing: return "OrbStack isn't installed or isn't running."
        case .composeFailed(let s): return s
        case .portUnavailable(let p): return "Port \(p) is in use."
        }
    }
}

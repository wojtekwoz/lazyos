import Foundation

public final class ServiceStore {
    private let url: URL
    private let queue = DispatchQueue(label: "co.lazyos.store")

    public init(url: URL = Paths.servicesJSON) {
        self.url = url
    }

    public func load() -> [Service] {
        queue.sync {
            guard let data = try? Data(contentsOf: url) else { return [] }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            do {
                return try dec.decode([Service].self, from: data)
            } catch {
                FileHandle.standardError.write(Data("LazyOS: failed to load services.json: \(error)\n".utf8))
                return []
            }
        }
    }

    public func save(_ services: [Service]) {
        queue.sync {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(services) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public func upsert(_ service: Service) {
        var list = load()
        if let idx = list.firstIndex(where: { $0.id == service.id }) {
            list[idx] = service
        } else {
            list.append(service)
        }
        save(list)
    }

    public func remove(slug: String) {
        save(load().filter { $0.slug != slug })
    }

    public func find(slug: String) -> Service? {
        load().first(where: { $0.slug == slug })
    }
}

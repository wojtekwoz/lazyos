import AppKit
import Combine
import LazyOSCore

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem
    private var library: LibraryViewModel
    private var cancellables: Set<AnyCancellable> = []

    init(library: LibraryViewModel) {
        self.library = library
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shippingbox.circle.fill",
                                   accessibilityDescription: "LazyOS")
            button.imagePosition = .imageOnly
        }
        rebuildMenu()
        // Rebuild whenever services or statuses change.
        library.$services
            .combineLatest(library.$statuses, library.$overallUsage)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Header summary
        let runningCount = library.services.filter { library.status(for: $0.slug) == .running }.count
        let header = NSMenuItem(title:
            runningCount == 0 ? "LazyOS — everything is off" :
            "LazyOS — \(runningCount) running · \(Int(library.overallUsage.cpuPercent))% CPU · \(UsageBars.formatBytes(library.overallUsage.memoryBytes)) RAM",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // One row per service
        for service in library.services {
            let status = library.status(for: service.slug)
            let title = "\(statusGlyph(status))  \(service.name)"
            let item = NSMenuItem(title: title,
                                  action: #selector(toggleService(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = service.slug
            menu.addItem(item)
            if status == .running {
                let open = NSMenuItem(title: "    Open \(service.name)",
                                      action: #selector(openService(_:)),
                                      keyEquivalent: "")
                open.target = self
                open.representedObject = service.slug
                menu.addItem(open)
            }
        }
        if library.services.isEmpty {
            let empty = NSMenuItem(title: "No apps installed", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())

        let openApp = NSMenuItem(title: "Open LazyOS", action: #selector(openWindow), keyEquivalent: "o")
        openApp.target = self
        menu.addItem(openApp)

        let quit = NSMenuItem(title: "Quit LazyOS", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func statusGlyph(_ s: ServiceStatus) -> String {
        switch s {
        case .running: return "🟢"
        case .starting, .stopping: return "🟡"
        case .error: return "🔴"
        case .off: return "⚪️"
        }
    }

    @objc private func toggleService(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String,
              let svc = library.services.first(where: { $0.slug == slug }) else { return }
        if library.status(for: slug) == .running {
            library.stop(svc)
        } else {
            library.start(svc)
        }
    }

    @objc private func openService(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String,
              let svc = library.services.first(where: { $0.slug == slug }) else { return }
        library.open(svc)
    }

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

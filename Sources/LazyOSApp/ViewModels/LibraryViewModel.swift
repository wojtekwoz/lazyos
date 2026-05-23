import Foundation
import Combine
import AppKit
import LazyOSCore

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var services: [Service] = []
    @Published var statuses: [String: ServiceStatus] = [:]
    @Published var runtimeAvailable: Bool = true
    @Published var inFlight: Set<String> = []
    @Published var lastError: String?
    @Published var lastInfo: String?

    // Usage
    @Published var overallUsage: OverallUsage = .zero
    @Published var usagePerProject: [String: ServiceUsage] = [:]

    // UI nav
    @Published var detailSlug: String?
    @Published var showCatalog: Bool = false

    private var statusTimer: Timer?
    private var usageTimer: Timer?
    private var idleCheckTimer: Timer?
    private var sleepObserver: NSObjectProtocol?

    func refresh() {
        services = ServiceManager.shared.library()
        runtimeAvailable = ServiceManager.shared.runtimeAvailable()
        Task.detached { [weak self] in
            await self?.refreshStatuses()
            await self?.refreshUsage()
        }
    }

    func refreshStatuses() async {
        let snapshot = await MainActor.run { self.services }
        var next: [String: ServiceStatus] = [:]
        for s in snapshot {
            next[s.slug] = ServiceManager.shared.status(slug: s.slug)
        }
        await MainActor.run {
            self.statuses = next
            self.runtimeAvailable = ServiceManager.shared.runtimeAvailable()
        }
    }

    func refreshUsage() async {
        let sample = UsageProbe.shared.sample()
        await MainActor.run {
            self.overallUsage = sample.overall
            self.usagePerProject = sample.perProject
        }
    }

    func startPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { await self?.refreshStatuses() }
        }
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { await self?.refreshUsage() }
        }
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.applyIdleAutoStop()
        }
        if sleepObserver == nil {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.stopServicesForSleep()
            }
        }
    }

    func status(for slug: String) -> ServiceStatus { statuses[slug] ?? .off }

    // MARK: - Mutations

    func start(_ service: Service) {
        guard !inFlight.contains(service.slug) else { return }
        inFlight.insert(service.slug)
        statuses[service.slug] = .starting
        Task.detached { [weak self] in
            do { try ServiceManager.shared.start(slug: service.slug) }
            catch { let msg = error.localizedDescription; await MainActor.run { self?.lastError = msg } }
            await self?.burstRefresh()
            await MainActor.run { self?.inFlight.remove(service.slug) }
        }
    }

    func stop(_ service: Service) {
        guard !inFlight.contains(service.slug) else { return }
        inFlight.insert(service.slug)
        statuses[service.slug] = .stopping
        Task.detached { [weak self] in
            do { try ServiceManager.shared.stop(slug: service.slug) }
            catch { let msg = error.localizedDescription; await MainActor.run { self?.lastError = msg } }
            await self?.burstRefresh()
            await MainActor.run { self?.inFlight.remove(service.slug) }
        }
    }

    func open(_ service: Service) {
        if let url = URL(string: service.webURL) { NSWorkspace.shared.open(url) }
    }

    func install(_ entry: CatalogEntry) {
        Task.detached { [weak self] in
            do {
                _ = try ServiceManager.shared.install(entry)
                await MainActor.run { self?.refresh() }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { self?.lastError = msg }
            }
        }
    }

    func uninstall(slug: String) {
        Task.detached { [weak self] in
            try? ServiceManager.shared.uninstall(slug: slug)
            try? LaunchdScheduler.shared.remove(slug: slug)
            await MainActor.run {
                self?.refresh()
                self?.statuses[slug] = nil
            }
        }
    }

    func updateSchedule(slug: String, schedule: Schedule?) {
        Task.detached { [weak self] in
            do {
                try ServiceManager.shared.setSchedule(slug: slug, schedule: schedule)
                await MainActor.run {
                    self?.refresh()
                    self?.lastInfo = schedule == nil ? "Schedule removed." : "Schedule saved."
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { self?.lastError = msg }
            }
        }
    }

    func updateResourceTier(slug: String, tier: ResourceTier) {
        ServiceManager.shared.setResourceTier(slug: slug, tier: tier)
        refresh()
    }

    func updateAutoStopOnSleep(slug: String, value: Bool) {
        ServiceManager.shared.setAutoStopOnSleep(slug: slug, value: value)
        refresh()
    }

    func backup(slug: String) {
        inFlight.insert(slug)
        Task.detached { [weak self] in
            do {
                let url = try ServiceManager.shared.backup(slug: slug)
                let path = url.path
                await MainActor.run {
                    self?.lastInfo = "Backed up to \(path)"
                    self?.refresh()
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { self?.lastError = msg }
            }
            await MainActor.run { self?.inFlight.remove(slug) }
        }
    }

    func installCustomFolder(_ folder: URL) {
        Task.detached { [weak self] in
            do {
                _ = try ServiceManager.shared.installCustom(folder: folder)
                await MainActor.run { self?.refresh() }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { self?.lastError = msg }
            }
        }
    }

    // MARK: - Auto-stop logic

    private func stopServicesForSleep() {
        let toStop = services.filter {
            $0.autoStopOnSleep && status(for: $0.slug) == .running
        }
        for svc in toStop {
            Task.detached { try? ServiceManager.shared.stop(slug: svc.slug) }
        }
    }

    private func applyIdleAutoStop() {
        for svc in services {
            guard let minutes = svc.autoStopAfterIdleMinutes else { continue }
            guard status(for: svc.slug) == .running else { continue }
            // Idle = no port connections for `minutes` minutes. We approximate by
            // checking lsof for active TCP connections to the service's port.
            if !hasActiveConnections(port: svc.port),
               let started = svc.lastStartedAt,
               Date().timeIntervalSince(started) > Double(minutes * 60) {
                Task.detached { try? ServiceManager.shared.stop(slug: svc.slug) }
            }
        }
    }

    private func hasActiveConnections(port: Int) -> Bool {
        let r = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:ESTABLISHED"])
        return r.ok && !r.stdout.isEmpty
    }

    // MARK: - Quick refresh after actions

    private func burstRefresh() async {
        await refreshStatuses(); await refreshUsage()
        try? await Task.sleep(nanoseconds: 800_000_000)
        await refreshStatuses(); await refreshUsage()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refreshStatuses(); await refreshUsage()
    }
}

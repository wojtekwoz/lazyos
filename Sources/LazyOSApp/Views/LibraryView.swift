import SwiftUI
import LazyOSCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var showAddMenu = false
    @State private var showCustomImporter = false

    private let cols = [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if !library.runtimeAvailable {
                RuntimeMissingBanner()
            }
            ScrollView {
                runningSection
                installedSection
                if library.services.isEmpty {
                    emptyState
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            footer
        }
        .alert("Couldn't run that", isPresented: Binding(
            get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } }
        )) {
            Button("OK") { library.lastError = nil }
        } message: { Text(library.lastError ?? "") }
        .sheet(item: Binding(
            get: { library.detailSlug.map(IDWrap.init) },
            set: { library.detailSlug = $0?.id }
        )) { wrap in
            ServiceDetail(slug: wrap.id)
        }
        .sheet(isPresented: $library.showCatalog) {
            CatalogBrowser()
        }
        .fileImporter(isPresented: $showCustomImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                library.installCustomFolder(url)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url, url.hasDirectoryPath else { return }
                DispatchQueue.main.async { library.installCustomFolder(url) }
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("LazyOS").font(.system(size: 18, weight: .semibold))
            Spacer()
            Menu {
                Button("Browse catalog…") { library.showCatalog = true }
                Button("Add custom folder…") { showCustomImporter = true }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .help("Add a new app")

            Button {
                Task { await library.refreshStatuses(); await library.refreshUsage() }
            } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var running: [Service] {
        library.services.filter {
            let s = library.status(for: $0.slug)
            return s == .running || s == .starting || s == .stopping
        }
    }

    private var installed: [Service] {
        library.services.filter {
            let s = library.status(for: $0.slug)
            return s == .off || s == .error
        }
    }

    @ViewBuilder
    private var runningSection: some View {
        if !running.isEmpty {
            sectionHeader("Running", count: running.count)
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(running) { ServiceCardView(service: $0) }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var installedSection: some View {
        if !installed.isEmpty {
            sectionHeader("Installed", count: installed.count)
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(installed) { ServiceCardView(service: $0) }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary).tracking(0.8)
            Text("\(count)").font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("No apps yet").font(.headline)
            Text("Add one from the catalog or drop a folder with a compose file here.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Browse catalog") { library.showCatalog = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 80)
    }

    @ViewBuilder
    private var footer: some View {
        Divider().opacity(0.5)
        HStack(spacing: 14) {
            FooterStat(label: "Apps running", value: "\(running.count)")
            FooterStat(label: "Containers", value: "\(library.overallUsage.runningContainers)")
            FooterStat(label: "CPU", value: String(format: "%.0f%%", library.overallUsage.cpuPercent))
            FooterStat(label: "RAM", value: UsageBars.formatBytes(library.overallUsage.memoryBytes))
            Spacer()
            if let info = library.lastInfo {
                Text(info).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct FooterStat: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }
}

private struct IDWrap: Identifiable, Hashable {
    let id: String
}

private struct RuntimeMissingBanner: View {
    @EnvironmentObject var library: LibraryViewModel
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Setting up the runtime…")
                    .font(.system(size: 13, weight: .semibold))
                Text("LazyOS is preparing a small local environment so apps can run. This only happens once.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView().controlSize(.small)
        }
        .padding(12).background(Color.orange.opacity(0.08))
    }
}

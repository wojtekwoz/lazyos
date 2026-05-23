import SwiftUI
import LazyOSCore

struct CatalogBrowser: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private let cols = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Browse apps").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider().opacity(0.5)

            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(Catalog.shared.entries(), id: \.slug) { entry in
                        CatalogTile(entry: entry,
                                    installed: library.services.contains(where: { $0.slug == entry.slug }))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 480)
    }
}

private struct CatalogTile: View {
    let entry: CatalogEntry
    let installed: Bool
    @EnvironmentObject var library: LibraryViewModel
    @State private var showHeavyConfirm = false

    var accent: Color { Color(hex: entry.accentHex) ?? .accentColor }
    var sizeMB: Int { entry.firstRunHintMB ?? 0 }
    var isHeavy: Bool { sizeMB >= 3000 }
    var isMedium: Bool { sizeMB >= 1000 && sizeMB < 3000 }

    private var sizeLabel: String {
        if sizeMB >= 1000 { return String(format: "%.1f GB download", Double(sizeMB) / 1024) }
        return "\(sizeMB) MB download"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.16))
                    Image(systemName: entry.iconSymbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accent)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.system(size: 14, weight: .semibold))
                    Text(entry.blurb).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            if sizeMB > 0 {
                HStack(spacing: 6) {
                    Image(systemName: isHeavy ? "exclamationmark.triangle.fill" : "arrow.down.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHeavy ? .orange : (isMedium ? .secondary : .tertiary))
                    Text(sizeLabel)
                        .font(.system(size: 11, weight: isHeavy ? .semibold : .regular))
                        .foregroundStyle(isHeavy ? .primary : .secondary)
                    if isHeavy {
                        Text("on first start").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    Capsule().fill(isHeavy ? Color.orange.opacity(0.15) : Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                )
            }

            HStack {
                Spacer()
                if installed {
                    Label("Installed", systemImage: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Add") {
                        if isHeavy { showHeavyConfirm = true } else { library.install(entry) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
        .confirmationDialog("Add \(entry.name)?",
                            isPresented: $showHeavyConfirm,
                            titleVisibility: .visible) {
            Button("Download \(sizeLabel)", role: .destructive) { library.install(entry) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This app is large. On a typical connection the first start can take 10–20 minutes. The download happens once and is cached.")
        }
    }
}

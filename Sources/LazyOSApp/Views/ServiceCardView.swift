import SwiftUI
import LazyOSCore

struct ServiceCardView: View {
    let service: Service
    @EnvironmentObject var library: LibraryViewModel
    @State private var hover = false

    var status: ServiceStatus { library.status(for: service.slug) }
    var busy: Bool { library.inFlight.contains(service.slug) }
    var accent: Color { Color(hex: service.accentHex) ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(service.blurb)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                StatusPill(status: status)
                infoChip
            }
            if let u = library.usagePerProject["lazyos-\(service.slug)"], status == .running {
                HStack(spacing: 10) {
                    Label(String(format: "%.0f%%", u.cpuPercent), systemImage: "cpu")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Label(UsageBars.formatBytes(u.memoryBytes), systemImage: "memorychip")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            actionRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(hover ? 0.06 : 0), radius: hover ? 6 : 0, y: hover ? 2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hover)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: status)
        .onHover { hover = $0 }
        .contextMenu {
            Button(status == .running ? "Stop" : "Start") {
                status == .running ? library.stop(service) : library.start(service)
            }
            Button("Open in browser") { library.open(service) }.disabled(status != .running)
            Divider()
            Button("Details…") { library.detailSlug = service.slug }
            Button("Schedule…") { library.detailSlug = service.slug }
            Divider()
            Button("Remove…", role: .destructive) { library.detailSlug = service.slug }
        }
    }

    var infoChip: some View {
        Button {
            library.detailSlug = service.slug
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .help("Details")
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.16))
            Image(systemName: service.iconSymbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accent)
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch status {
                case .running:
                    Button {
                        library.open(service)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)

                    Button("Stop") { library.stop(service) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(busy)

                case .starting:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(busy ? "Starting…" : "Starting in background…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Stop") { library.stop(service) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(busy)

                case .stopping:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Stopping…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)

                case .off, .error:
                    Button {
                        library.start(service)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .disabled(busy)
                }
            }

            if status == .starting, let mb = service.firstRunHintMB {
                Text("First start downloads ~\(mb) MB")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct StatusPill: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        )
    }

    private var color: Color {
        switch status {
        case .running: return .green
        case .starting, .stopping: return .yellow
        case .error: return .red
        case .off: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var label: String {
        switch status {
        case .running: return "Running"
        case .starting: return "Starting"
        case .stopping: return "Stopping"
        case .error: return "Error"
        case .off: return "Off"
        }
    }
}

// MARK: - Color hex

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

import SwiftUI
import LazyOSCore

struct ServiceDetail: View {
    let slug: String
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSchedule = false
    @State private var showingRemoveConfirm = false

    private var service: Service? { library.services.first { $0.slug == slug } }
    private var status: ServiceStatus { library.status(for: slug) }
    private var usage: ServiceUsage? { library.usagePerProject["lazyos-\(slug)"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let svc = service {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(svc)
                        primaryActions(svc)
                        Divider().padding(.vertical, 4)
                        settingsRows(svc)
                    }
                    .padding(24)
                }
                bottomBar(svc)
            } else {
                Text("Service not found").padding()
            }
        }
        .frame(width: 520, height: 540)
        .sheet(isPresented: $showingSchedule) {
            if let svc = service {
                ScheduleEditor(slug: svc.slug, initial: svc.schedule) { newSchedule in
                    library.updateSchedule(slug: svc.slug, schedule: newSchedule)
                }
            }
        }
        .confirmationDialog("Remove \(service?.name ?? "this app")?",
                            isPresented: $showingRemoveConfirm,
                            titleVisibility: .visible) {
            Button("Remove (keep data)", role: .destructive) {
                library.uninstall(slug: slug); dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The app will be removed from your library. Volumes stay on disk so you can restore later.")
        }
    }

    // MARK: - Sub-views

    private func header(_ svc: Service) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((Color(hex: svc.accentHex) ?? .accentColor).opacity(0.18))
                Image(systemName: svc.iconSymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(hex: svc.accentHex) ?? .accentColor)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(svc.name).font(.system(size: 22, weight: .semibold))
                Text(svc.blurb).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            StatusPill(status: status)
        }
    }

    private func primaryActions(_ svc: Service) -> some View {
        let accent = Color(hex: svc.accentHex) ?? .accentColor
        return HStack(spacing: 10) {
            if status == .running {
                Button { library.open(svc) } label: {
                    Label("Open \(svc.name)", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)

                Button("Stop") { library.stop(svc) }
                    .buttonStyle(.bordered).controlSize(.large)
            } else if status == .starting || status == .stopping {
                ProgressView().controlSize(.small)
                Text(status == .starting ? "Starting…" : "Stopping…")
                    .foregroundStyle(.secondary).font(.system(size: 13))
                Spacer()
                Button("Stop") { library.stop(svc) }
                    .buttonStyle(.bordered).controlSize(.large)
            } else {
                Button { library.start(svc) } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
            }
        }
    }

    private func settingsRows(_ svc: Service) -> some View {
        VStack(spacing: 14) {
            // Address
            row(label: "Address", trailing: {
                HStack(spacing: 6) {
                    Text(svc.webURL)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(svc.webURL, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy URL")
                }
            })

            // Schedule
            row(label: "Schedule", trailing: {
                HStack(spacing: 8) {
                    Text(svc.schedule.flatMap { $0.enabled ? CronParser.describe($0.startCron) : "Off" } ?? "Off")
                        .foregroundStyle(.secondary).font(.system(size: 13))
                    Button("Change") { showingSchedule = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            })

            // Power tier
            row(label: "Power", trailing: {
                Picker("", selection: Binding(
                    get: { svc.resourceTier },
                    set: { library.updateResourceTier(slug: svc.slug, tier: $0) }
                )) {
                    ForEach(ResourceTier.allCases, id: \.self) { t in
                        Text("\(t.label) — \(t.detail)").tag(t)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(maxWidth: 220)
            })

            // Auto-stop on sleep
            row(label: "Auto-stop on sleep", trailing: {
                Toggle("", isOn: Binding(
                    get: { svc.autoStopOnSleep },
                    set: { library.updateAutoStopOnSleep(slug: svc.slug, value: $0) }
                ))
                .labelsHidden().toggleStyle(.switch)
            })

            // Usage
            if let u = usage, status == .running {
                row(label: "Usage", trailing: {
                    HStack(spacing: 8) {
                        UsageBars(cpu: u.cpuPercent, mem: u.memoryBytes, memLimit: u.memoryLimitBytes)
                    }
                })
            }

            // Backups
            row(label: "Backup", trailing: {
                HStack(spacing: 8) {
                    if let d = svc.lastBackupAt {
                        Text("Last \(Self.relative(d))")
                            .font(.system(size: 12)).foregroundStyle(.tertiary)
                    } else {
                        Text("Never").font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                    Button("Back up now") {
                        library.backup(slug: svc.slug)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(library.inFlight.contains(svc.slug))
                }
            })
        }
    }

    private func bottomBar(_ svc: Service) -> some View {
        HStack {
            Button("Remove app…", role: .destructive) { showingRemoveConfirm = true }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func row<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            trailing()
            Spacer(minLength: 0)
        }
    }

    private static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

struct UsageBars: View {
    let cpu: Double          // %
    let mem: Int64
    let memLimit: Int64

    var body: some View {
        HStack(spacing: 12) {
            metric(title: "CPU", value: String(format: "%.0f%%", cpu), fraction: min(1, cpu / 200))
            metric(title: "RAM", value: Self.formatBytes(mem), fraction: memLimit > 0 ? Double(mem) / Double(memLimit) : 0)
        }
    }

    private func metric(title: String, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                Text(value).font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor))
                    Capsule().fill(fraction > 0.85 ? Color.red : (fraction > 0.6 ? Color.orange : Color.green))
                        .frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 4)
        }
        .frame(width: 90)
    }

    static func formatBytes(_ b: Int64) -> String {
        let mb = Double(b) / 1024 / 1024
        if mb > 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}

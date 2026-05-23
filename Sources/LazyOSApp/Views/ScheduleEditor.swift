import SwiftUI
import LazyOSCore

struct ScheduleEditor: View {
    let slug: String
    let initial: Schedule?
    let onSave: (Schedule?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var preset: Preset
    @State private var startHour: Int
    @State private var stopHour: Int
    @State private var weekdaysOnly: Bool

    enum Preset: String, CaseIterable, Identifiable {
        case weekdays = "Weekdays, 9 AM – 7 PM"
        case evenings = "Evenings, 6 PM – 11 PM"
        case weekends = "Weekends, all day"
        case custom = "Custom…"
        var id: String { rawValue }
    }

    init(slug: String, initial: Schedule?, onSave: @escaping (Schedule?) -> Void) {
        self.slug = slug; self.initial = initial; self.onSave = onSave
        _enabled = State(initialValue: initial?.enabled ?? true)
        _preset = State(initialValue: Self.preset(for: initial))
        let parts = initial?.startCron.split(separator: " ").map(String.init)
        _startHour = State(initialValue: Int(parts?[safe: 1] ?? "9") ?? 9)
        let stopParts = initial?.stopCron.split(separator: " ").map(String.init)
        _stopHour = State(initialValue: Int(stopParts?[safe: 1] ?? "19") ?? 19)
        _weekdaysOnly = State(initialValue: (parts?[safe: 4]) == "1-5")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Schedule").font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle("On", isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Preset", selection: $preset) {
                    ForEach(Preset.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.menu)
                .disabled(!enabled)

                if preset == .custom {
                    HStack {
                        Text("Start at")
                        Picker("", selection: $startHour) {
                            ForEach(0..<24) { Text(Self.hourLabel($0)).tag($0) }
                        }.frame(width: 100)
                        Text("Stop at")
                        Picker("", selection: $stopHour) {
                            ForEach(0..<24) { Text(Self.hourLabel($0)).tag($0) }
                        }.frame(width: 100)
                    }
                    Toggle("Weekdays only", isOn: $weekdaysOnly)
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)

            if enabled {
                let s = currentSchedule()
                Text("LazyOS will run this app \(CronParser.describe(s.startCron)) and stop it at \(CronParser.describe(s.stopCron)).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Schedules need your Mac to be awake at those times.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack {
                Button("Remove Schedule") { onSave(nil); dismiss() }
                    .disabled(initial == nil)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { onSave(enabled ? currentSchedule() : nil); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 320)
    }

    private func currentSchedule() -> Schedule {
        switch preset {
        case .weekdays: return .weekdays9to7
        case .evenings: return .evenings
        case .weekends: return .weekendsAlways
        case .custom:
            let weekdaySpec = weekdaysOnly ? "1-5" : "*"
            return Schedule(enabled: true,
                            startCron: "0 \(startHour) * * \(weekdaySpec)",
                            stopCron: "0 \(stopHour) * * \(weekdaySpec)")
        }
    }

    static func preset(for s: Schedule?) -> Preset {
        guard let s else { return .weekdays }
        if s == .weekdays9to7 { return .weekdays }
        if s == .evenings { return .evenings }
        if s == .weekendsAlways { return .weekends }
        return .custom
    }

    static func hourLabel(_ h: Int) -> String {
        var c = DateComponents(); c.hour = h
        let date = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: date)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

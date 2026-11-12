import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal
    @State private var confirmReset = false

    var body: some View {
        let stats = model.stats
        let totalWords = stats.values.reduce(0) { $0 + $1.words }
        let totalSeconds = stats.values.reduce(0) { $0 + $1.seconds }
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading statistics").font(.title2.bold())
            if stats.isEmpty {
                Text("No reading yet. Statistics appear here after you read with Odak.")
                    .foregroundStyle(theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                HStack(spacing: 12) {
                    tile("Today", "\(stats[AppModel.dayKey(.now)]?.words ?? 0)")
                    tile("This week", "\(Self.words(stats, since: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now))")
                    tile("Total time read", Self.hoursMinutes(totalSeconds))
                    tile("Average speed", totalSeconds < 1 ? "–" : String(localized: "\(Int(Double(totalWords) / (totalSeconds / 60))) WPM"))
                }
                Text("Current streak: \(Self.streak(stats)) days").foregroundStyle(theme.dim)
                Chart(Self.lastDays(14), id: \.self) { day in
                    BarMark(x: .value("Day", day, unit: .day), y: .value("Words", stats[AppModel.dayKey(day)]?.words ?? 0))
                        .foregroundStyle(theme.accent)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 180)
                .accessibilityLabel("Words per day, last 14 days")
            }
            HStack {
                Button("Reset Statistics…", role: .destructive) { confirmReset = true }
                    .disabled(stats.isEmpty)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(theme.background)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .confirmationDialog("Reset all reading statistics?", isPresented: $confirmReset) {
            Button("Reset Statistics", role: .destructive) { model.resetStats() }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func tile(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(theme.dim)
            Text(value).font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    // MARK: Aggregation

    private static func lastDays(_ n: Int) -> [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<n).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    private static func words(_ stats: [String: AppModel.DayStats], since start: Date) -> Int {
        let key = AppModel.dayKey(start)
        return stats.filter { $0.key >= key }.values.reduce(0) { $0 + $1.words }
    }

    /// Consecutive days with words, ending today, or yesterday when nothing was read yet today.
    private static func streak(_ stats: [String: AppModel.DayStats]) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if (stats[AppModel.dayKey(day)]?.words ?? 0) == 0 { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while (stats[AppModel.dayKey(day)]?.words ?? 0) > 0 {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private static func hoursMinutes(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

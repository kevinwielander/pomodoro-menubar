import Charts
import PomodoroCore
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var controller: TimerController
    @State private var range = Range.week
    @State private var hoveredDay: Date?
    let done: () -> Void

    enum Range: Int, CaseIterable {
        case today = 1, week = 7, month = 30

        var title: String {
            switch self {
            case .today: "Today"
            case .week: "7 days"
            case .month: "30 days"
            }
        }
    }

    var body: some View {
        let stats = controller.stats
        let summary = stats.summary(in: stats.interval(days: range.rawValue, endingAt: controller.now))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BackHeader(title: "Stats", back: done)
                Button { controller.exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
                    .help("Export history as CSV")
            }

            Picker("Range", selection: $range) {
                ForEach(Range.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            tiles(summary, streak: stats.streak(at: controller.now))

            Text("Breaks: \(summary.breaksTaken) taken, \(summary.breaksSkipped) skipped")
                .font(.caption)
                .foregroundStyle(.secondary)

            if range == .today {
                TodayList(records: stats.records(in: stats.interval(days: 1, endingAt: controller.now)))
            } else {
                chart(stats.dailyTotals(days: range.rawValue, endingAt: controller.now))
            }
        }
    }

    private func tiles(_ summary: StatsSummary, streak: Int) -> some View {
        let attempted = summary.completedFocus + summary.partialFocus
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                StatTile(title: "Focused", value: formatDuration(summary.focusTime),
                         detail: summary.partialFocusTime > 0 ? "incl. \(formatDuration(summary.partialFocusTime)) partial" : "")
                StatTile(title: "Pomodoros", value: "\(summary.completedFocus)",
                         detail: summary.partialFocus > 0 ? "+\(summary.partialFocus) partial" : "")
            }
            GridRow {
                StatTile(title: "Completed", value: attempted > 0 ? "\(summary.completedFocus * 100 / attempted)%" : "–",
                         detail: "of started blocks")
                StatTile(title: "Streak", value: "\(streak) \(streak == 1 ? "day" : "days")",
                         detail: "with a full pomodoro")
            }
        }
    }

    private func chart(_ totals: [DayTotal]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(readout(totals))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Chart(totals) { day in
                ForEach([("Completed", day.completedTime), ("Partial", day.partialTime)], id: \.0) { kind, time in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", time / 60))
                        .foregroundStyle(by: .value("Kind", kind))
                        .cornerRadius(2)
                        .opacity(hoveredDay == nil || hoveredDay == day.day ? 1 : 0.4)
                }
            }
            .chartForegroundStyleScale(["Completed": Color.accentColor, "Partial": Color.gray.opacity(0.55)])
            .chartLegend(position: .top, alignment: .trailing)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let minutes = value.as(Double.self) { Text("\(Int(minutes))m") } }
                }
            }
            .chartXAxis {
                if range == .week {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case .active(let location) = phase, let plotFrame = proxy.plotFrame,
                                  let date: Date = proxy.value(atX: location.x - geometry[plotFrame].origin.x)
                            else {
                                hoveredDay = nil
                                return
                            }
                            let day = Calendar.current.startOfDay(for: date)
                            hoveredDay = totals.contains { $0.day == day } ? day : nil
                        }
                }
            }
            .frame(height: 150)
        }
    }

    /// Hover readout above the chart; the range average when nothing is hovered.
    private func readout(_ totals: [DayTotal]) -> String {
        if let hoveredDay, let day = totals.first(where: { $0.day == hoveredDay }) {
            let date = day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            var text = "\(date): \(formatDuration(day.completedTime)) in \(day.completedCount) full"
            if day.partialCount > 0 { text += ", \(formatDuration(day.partialTime)) in \(day.partialCount) partial" }
            return text
        }
        let total = totals.reduce(0) { $0 + $1.completedTime + $1.partialTime }
        return "Average \(formatDuration(total / Double(max(1, totals.count)))) focused per day"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(detail.isEmpty ? " " : detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TodayList: View {
    let records: [BlockRecord]

    var body: some View {
        if records.isEmpty {
            Text("No blocks yet today.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(records.reversed()) { record in
                        row(record)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private func row(_ record: BlockRecord) -> some View {
        HStack {
            Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Image(systemName: record.phase == .focus ? "timer" : "cup.and.saucer")
                .frame(width: 16)
            Text(record.phase == .focus ? "Focus" : "Break")
            Spacer()
            // Partial blocks show the time actually spent, never the planned length.
            Text(record.outcome == .completed
                 ? formatDuration(record.actual)
                 : "\(formatDuration(record.actual)) of \(formatDuration(record.planned))")
                .monospacedDigit()
            if record.outcome == .completed {
                Image(systemName: "checkmark").foregroundStyle(.secondary)
                    .help("Completed")
            } else {
                Text(record.outcome.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .font(.caption)
    }
}

import SwiftUI
import SwiftData
import Charts
import StrideKit
import StrideUI

/// Progress: challenges still running, or a way to start one.
struct ChallengesSection: View {
    let samples: [RunSample]
    let now: Date
    @Query(sort: \Challenge.endDate) private var challenges: [Challenge]
    @State private var creating = false

    var body: some View {
        let running = challenges.filter { now < $0.endDate }.prefix(3)
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeader(title: "Challenges", route: challenges.isEmpty ? nil : .challenges)
            ForEach(running) { challenge in
                NavigationLink(value: challenge) {
                    ChallengeCard(challenge: challenge, status: challenge.status(samples: samples, now: now), now: now)
                }
                .buttonStyle(.plain)
            }
            if running.isEmpty {
                VStack(alignment: .leading, spacing: Space.x3) {
                    Illustration(name: "challengeMountain", contentMode: .fill)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    Label("Set yourself a challenge", systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("Run 100 km this month, climb a mountain's worth, or make your own.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    Button("New challenge") { creating = true }
                        .buttonStyle(.strideSecondary)
                }
                .raisedCard()
            } else {
                Button {
                    creating = true
                } label: {
                    Label("New challenge", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Dimension.hitMin)
                }
            }
        }
        .sheet(isPresented: $creating) { NewChallengeView() }
    }
}

/// A challenge's progress, time left and whether the runner is on track.
struct ChallengeCard: View {
    let challenge: Challenge
    let status: ChallengeStatus
    let now: Date
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                ChallengeIcon(metric: challenge.metric, state: status.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title).font(.headline).foregroundStyle(.ink)
                    Text(ChallengeText.state(challenge, status: status, now: now))
                        .font(.caption)
                        .foregroundStyle(status.state == .completed ? Color.success : Color.inkMuted)
                }
                Spacer(minLength: 0)
            }
            ProgressBar(progress: status.fraction)
            HStack {
                Text(challenge.metric.progressText(value: status.value, target: status.target, unit: unit))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                Spacer()
                if let pace = ChallengeText.pace(challenge, status: status, unit: unit) {
                    Text(pace.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pace.onTrack ? Color.success : Color.inkMuted)
                }
            }
        }
        .raisedCard()
        .accessibilityElement(children: .combine)
    }
}

struct ChallengeIcon: View {
    let metric: ChallengeMetric
    let state: ChallengeStatus.State

    var body: some View {
        Image(systemName: state == .completed ? "checkmark" : metric.symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(state == .completed ? Color.success : state == .missed ? Color.inkMuted : Color.lane)
            .frame(width: 40, height: 40)
            .background(state == .completed ? Color.success.opacity(0.15) : state == .missed ? Color.surfaceSunken : Color.laneSoft,
                        in: Circle())
            .accessibilityHidden(true)
    }
}

enum ChallengeText {
    /// "6 days left", "Last day", "Starts Oct 1", "Completed Sep 12", "Ended Sep 30".
    static func state(_ challenge: Challenge, status: ChallengeStatus, now: Date) -> String {
        let calendar = Calendar.current
        switch status.state {
        case .completed:
            return status.completedOn.map { "Completed \(shortDate($0))" } ?? "Completed"
        case .missed:
            return "Ended \(shortDate(challenge.endDate.addingTimeInterval(-1)))"
        case .upcoming:
            return "Starts \(shortDate(challenge.startDate))"
        case .active:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: challenge.endDate).day ?? 0
            return days <= 1 ? "Last day" : "\(days) days left"
        }
    }

    /// "On track", or how far behind an even effort the runner is.
    static func pace(_ challenge: Challenge, status: ChallengeStatus, unit: UnitSystem) -> (text: String, onTrack: Bool)? {
        guard status.state == .active, let expected = status.expected else { return nil }
        guard let behind = challenge.metric.behind(value: status.value, expected: expected, unit: unit) else {
            return ("On track", true)
        }
        return (behind, false)
    }
}

/// Every challenge: running, completed and ended.
struct ChallengesView: View {
    @Query(sort: \Challenge.endDate, order: .reverse) private var challenges: [Challenge]
    @Query(sort: \Run.startDate) private var runs: [Run]
    @Environment(\.modelContext) private var context
    @State private var creating = false

    var body: some View {
        let now = Date.now
        let samples = runs.map(\.sample)
        let statuses = Dictionary(challenges.map { ($0.id, $0.status(samples: samples, now: now)) }, uniquingKeysWith: { first, _ in first })
        func items(_ states: Set<ChallengeStatus.State>) -> [Challenge] {
            challenges.filter { statuses[$0.id].map { states.contains($0.state) } ?? false }
        }
        return ScrollView {
            if challenges.isEmpty {
                IllustratedEmptyState(illustration: "challengeMountain", symbol: "flag.checkered", title: "No challenges yet",
                                      message: "Pick a suggested challenge or set your own target.") {
                    Button("New challenge") { creating = true }
                        .buttonStyle(.stridePrimary)
                        .padding(.top, Space.x2)
                }
                .padding(.top, Space.x5)
            } else {
                VStack(alignment: .leading, spacing: Space.x5) {
                    section("Running", items([.active, .upcoming]).sorted { $0.endDate < $1.endDate }, statuses: statuses, now: now)
                    section("Completed", items([.completed]), statuses: statuses, now: now)
                    section("Ended", items([.missed]), statuses: statuses, now: now)
                }
                .padding(Space.x4)
            }
        }
        .background(Color.surface)
        .navigationTitle("Challenges")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New challenge", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) { NewChallengeView() }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Challenge], statuses: [UUID: ChallengeStatus], now: Date) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.x3) {
                Text(title).font(.headline).foregroundStyle(.ink)
                ForEach(items) { challenge in
                    if let status = statuses[challenge.id] {
                        NavigationLink(value: challenge) {
                            ChallengeCard(challenge: challenge, status: status, now: now)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete Challenge", systemImage: "trash", role: .destructive) {
                                context.delete(challenge)
                                try? context.save()
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One challenge: progress over time against an even effort, and the runs that count.
struct ChallengeDetailView: View {
    let challenge: Challenge
    @Query(sort: \Run.startDate) private var runs: [Run]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var confirmingDelete = false

    var body: some View {
        if challenge.isDeleted || challenge.modelContext == nil {
            ContentUnavailableView("Challenge deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        let now = Date.now
        let counted = runs.filter { challenge.interval.containsHalfOpen($0.startDate) && $0.startDate <= now }
        let status = challenge.status(samples: runs.map(\.sample), now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                VStack(alignment: .leading, spacing: Space.x3) {
                    HStack(spacing: Space.x3) {
                        ChallengeIcon(metric: challenge.metric, state: status.state)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateRange).font(.subheadline).foregroundStyle(.inkMuted)
                            Text(ChallengeText.state(challenge, status: status, now: now))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(status.state == .completed ? Color.success : Color.ink)
                        }
                    }
                    MetricView(challenge.metric.title,
                               value: challenge.metric.number(status.value, unit: unit, rounding: .down),
                               unit: "of \(challenge.metric.number(status.target, unit: unit)) \(challenge.metric.targetUnit(status.target, unit: unit))",
                               size: .large)
                    ProgressBar(progress: status.fraction, height: 10)
                    if let pace = ChallengeText.pace(challenge, status: status, unit: unit) {
                        Text(pace.text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(pace.onTrack ? Color.success : Color.inkMuted)
                    }
                }
                .raisedCard()

                if !counted.isEmpty {
                    ChartCard(title: "Progress", summary: "\(counted.count) \(counted.count == 1 ? "run" : "runs")") {
                        progressChart(counted, now: now)
                    }
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Runs that count").font(.headline).foregroundStyle(.ink)
                    if counted.isEmpty {
                        Text(emptyRunsText(status))
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .raisedCard()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(counted.reversed().enumerated()), id: \.element.id) { index, run in
                                if index > 0 { Divider().padding(.leading, Space.x4) }
                                NavigationLink(value: run) {
                                    RunRow(run: run, unit: unit)
                                        .padding(.horizontal, Space.x4)
                                        .padding(.vertical, Space.x3)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                    }
                }
            }
            .padding(Space.x4)
        }
        .background(Color.surface)
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Delete Challenge", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this challenge?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Challenge", role: .destructive) {
                let challenge = self.challenge
                dismiss()
                // Delete after the pop so this screen never renders a deleted model.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    context.delete(challenge)
                    try? context.save()
                }
            }
        } message: {
            Text("Your runs stay as they are.")
        }
    }

    private func emptyRunsText(_ status: ChallengeStatus) -> String {
        switch status.state {
        case .upcoming: "Runs from \(shortDate(challenge.startDate)) will count."
        case .missed: "No runs counted toward this challenge."
        default: "No runs yet. Every run from now until the end counts."
        }
    }

    private var dateRange: String {
        let end = challenge.endDate.addingTimeInterval(-1)
        return "\(challenge.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private struct Point {
        let date: Date
        let value: Double
    }

    /// Cumulative progress as steps, against a dashed line for an even effort to the target.
    private func progressChart(_ counted: [Run], now: Date) -> some View {
        let metric = challenge.metric
        let steps = ChallengeStatus.progression(metric: metric, samples: counted.map(\.sample))
        var points = [Point(date: challenge.startDate, value: 0)]
        points += steps.map { Point(date: $0.date, value: metric.displayValue(fromStored: $0.value, unit: unit)) }
        // Carry the total to today (or the end), so the line doesn't stop at the last run.
        let end = min(now, challenge.endDate)
        if let last = points.last, end > last.date {
            points.append(Point(date: end, value: last.value))
        }
        let target = metric.displayValue(fromStored: challenge.target, unit: unit)

        return Chart {
            LineMark(x: .value("Start", challenge.startDate), y: .value("Even effort", 0), series: .value("Line", "even"))
                .foregroundStyle(Color.inkMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            LineMark(x: .value("End", challenge.endDate), y: .value("Even effort", target), series: .value("Line", "even"))
                .foregroundStyle(Color.inkMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // Indexed: a run at the very start shares its date with the zero point.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value), series: .value("Line", "progress"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.track)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            RuleMark(y: .value("Target", target))
                .foregroundStyle(Color.success.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXScale(domain: challenge.startDate...challenge.endDate)
        .chartYScale(domain: 0...max(target, points.map(\.value).max() ?? 0) * 1.05)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.line.opacity(0.6))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.line.opacity(0.6))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formatted(.number.precision(.fractionLength(0))))
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityLabel("Progress toward \(challenge.metric.number(challenge.target, unit: unit)) \(challenge.metric.targetUnit(challenge.target, unit: unit))")
    }
}

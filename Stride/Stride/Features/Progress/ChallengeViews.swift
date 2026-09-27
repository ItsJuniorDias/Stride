import SwiftUI
import SwiftData
import Charts
import StrideKit
import StrideUI

/// A challenge still running: its name, time left and dates beside the art, progress in large
/// numbers, a bar with where an even pace would be by now, whether the runner is on track and
/// what's left to do each day.
struct ChallengeCard: View {
    let challenge: Challenge
    let status: ChallengeStatus
    let now: Date
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        let metric = challenge.metric
        let completed = status.state == .completed
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.x3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    HStack(spacing: 6) {
                        Image(systemName: completed ? "checkmark" : "stopwatch")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(stateLine)
                    }
                    .font(.footnote)
                    .foregroundStyle(completed ? Color.success : Color.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ArtThumbnail(name: "challengeMountain", width: 56, height: 56)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.number(status.value, unit: unit, rounding: .down))
                    .font(.system(size: 44, weight: .heavy).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("of \(metric.number(status.target, unit: unit)) \(metric.targetUnit(status.target, unit: unit))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
            }
            .padding(.top, Space.x3)
            .accessibilityElement(children: .combine)
            TrackBar(progress: status.fraction, tint: completed ? .success : .lane, height: 10,
                     marker: evenPace, markerLabel: showsEvenPaceLabel ? "Even pace" : nil)
                .padding(.top, 14)
                .accessibilityLabel(barDescription)
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                if let pace = ChallengeText.pace(challenge, status: status, unit: unit) {
                    Text(pace.text)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(pace.onTrack ? Color.success : Color.inkMuted)
                }
                Spacer(minLength: 0)
                if let toGo = ChallengeText.toGo(challenge, status: status, now: now, unit: unit, perDay: true) {
                    Text(toGo)
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.top, 10)
        }
        .raisedCard()
    }

    /// "5 days left · Sep 13 – 30", "Completed Sep 24 · Sep 1 – 30", "Starts Oct 1".
    private var stateLine: String {
        let state = ChallengeText.state(challenge, status: status, now: now)
        return status.state == .upcoming ? state : "\(state) · \(ChallengeText.dateRange(challenge))"
    }

    /// Where an even effort would be by now, as a fraction; nil at the very start or end, where it
    /// would sit on the bar's edge.
    private var evenPace: Double? {
        guard status.state == .active, let expected = status.expected, status.target > 0 else { return nil }
        let fraction = expected / status.target
        return (0.02...0.98).contains(fraction) ? fraction : nil
    }

    /// The caption needs room either side of the tick.
    private var showsEvenPaceLabel: Bool {
        evenPace.map { (0.12...0.88).contains($0) } ?? false
    }

    /// "72.4 of 100 km. An even pace would be at 66.7 km by now."
    private var barDescription: String {
        let metric = challenge.metric
        let progress = metric.progressText(value: status.value, target: status.target, unit: unit)
        guard status.state == .active, let expected = status.expected else { return progress }
        let shown = metric.shownValue(expected, unit: unit, rounding: .down)
        return "\(progress). An even pace would be at \(metric.number(expected, unit: unit, rounding: .down)) \(metric.displayUnit(unit, count: shown)) by now."
    }
}

/// A challenge's symbol in a soft circle: data color while running, a check once completed, muted
/// once ended.
struct ChallengeIcon: View {
    let metric: ChallengeMetric
    let state: ChallengeStatus.State
    var size: CGFloat = 40

    var body: some View {
        switch state {
        case .completed: IconBadge("checkmark", style: .tinted(.success), size: size)
        case .missed: IconBadge(ChallengeText.symbol(metric), style: .muted, size: size)
        case .active, .upcoming: IconBadge(ChallengeText.symbol(metric), style: .lane, size: size)
        }
    }
}

enum ChallengeText {
    /// "6 days left", "Last day", "Starts Oct 1", "Completed Sep 12", "Ended Sep 30".
    static func state(_ challenge: Challenge, status: ChallengeStatus, now: Date) -> String {
        switch status.state {
        case .completed:
            return status.completedOn.map { "Completed \(shortDate($0))" } ?? "Completed"
        case .missed:
            return "Ended \(shortDate(challenge.endDate.addingTimeInterval(-1)))"
        case .upcoming:
            return "Starts \(shortDate(challenge.startDate))"
        case .active:
            let days = daysLeft(challenge, now: now)
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

    /// "27.6 km to go", with what that means each day when `perDay`: "27.6 km to go · 5.5 km a day".
    /// Nil once the target is reached, or when the challenge is over.
    static func toGo(_ challenge: Challenge, status: ChallengeStatus, now: Date, unit: UnitSystem, perDay: Bool) -> String? {
        guard status.state == .active || status.state == .upcoming else { return nil }
        let metric = challenge.metric
        let remaining = status.target - status.value
        let shown = metric.shownValue(remaining, unit: unit)
        guard remaining > 0, shown > 0 else { return nil }
        let text = "\(metric.number(remaining, unit: unit)) \(metric.displayUnit(unit, count: shown)) to go"
        guard perDay, status.state == .active else { return text }
        let days = daysLeft(challenge, now: now)
        guard days > 1 else { return text }
        let daily = remaining / Double(days)
        switch metric {
        case .distance, .elevation:
            let dailyShown = metric.shownValue(daily, unit: unit, rounding: .up)
            guard dailyShown > 0 else { return text }
            return "\(text) · \(metric.number(daily, unit: unit, rounding: .up)) \(metric.displayUnit(unit, count: dailyShown)) a day"
        case .duration:
            return "\(text) · \(Int((daily / 60).rounded(.up))) min a day"
        case .runs, .activeDays:
            return text
        }
    }

    /// Days left, today included: the challenge ends at midnight after its last day.
    static func daysLeft(_ challenge: Challenge, now: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: challenge.endDate).day ?? 0
    }

    /// "Sep 13 – 30", with the year when it isn't this year's.
    static func dateRange(_ challenge: Challenge) -> String {
        let last = max(challenge.endDate.addingTimeInterval(-1), challenge.startDate)
        var style = Date.IntervalFormatStyle.interval.month(.abbreviated).day()
        if !Calendar.current.isDate(last, equalTo: .now, toGranularity: .year) {
            style = style.year()
        }
        return (challenge.startDate..<last).formatted(style)
    }

    /// The metric's symbol in outline, as the challenge designs draw them.
    static func symbol(_ metric: ChallengeMetric) -> String {
        metric == .elevation ? "mountain.2" : metric.symbol
    }
}

/// Every challenge: running now, suggested ones to start with a tap, your own, completed and ended.
struct ChallengesView: View {
    @Query(sort: \Challenge.endDate, order: .reverse) private var challenges: [Challenge]
    @Query(sort: \Run.startDate) private var runs: [Run]
    @Environment(\.modelContext) private var context
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var creating = false
    /// Suggestions started on this visit stay in place, marked Joined.
    @State private var joinedHere: Set<String> = []
    @State private var joinedCount = 0

    var body: some View {
        let now = Date.now
        let samples = runs.map(\.sample)
        let statuses = Dictionary(challenges.map { ($0.id, $0.status(samples: samples, now: now)) }, uniquingKeysWith: { first, _ in first })
        func items(_ states: Set<ChallengeStatus.State>) -> [Challenge] {
            challenges.filter { statuses[$0.id].map { states.contains($0.state) } ?? false }
        }
        let running = items([.active, .upcoming]).sorted { $0.endDate < $1.endDate }
        let suggested = ChallengeTemplate.catalog(unit: unit).filter { !isRunning($0, now: now) || joinedHere.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if challenges.isEmpty {
                    intro
                        .padding(.bottom, Space.x5)
                }
                if !running.isEmpty {
                    SectionHeading("Running now", style: .overline)
                        .padding(.bottom, Space.x2)
                    VStack(spacing: Space.x3) {
                        ForEach(running) { challenge in
                            if let status = statuses[challenge.id] {
                                NavigationLink(value: challenge) {
                                    ChallengeCard(challenge: challenge, status: status, now: now)
                                        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
                                }
                                .buttonStyle(.plain)
                                .contextMenu { deleteButton(challenge) }
                            }
                        }
                    }
                    .padding(.bottom, Space.x5)
                }
                if !suggested.isEmpty {
                    SectionHeading("Suggested", style: .overline)
                        .padding(.bottom, Space.x2)
                    suggestions(suggested, now: now)
                        .padding(.bottom, Space.x5)
                }

                Button {
                    creating = true
                } label: {
                    Label("New challenge", systemImage: "plus")
                }
                .buttonStyle(.stridePrimary)
                Text("Pick what counts, the target and the time frame.")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.x2)

                section("Completed", items([.completed]), statuses: statuses, now: now)
                section("Ended", items([.missed]), statuses: statuses, now: now)
            }
            .padding(.horizontal, Space.x4)
            .padding(.top, Space.x4)
            .padding(.bottom, Space.x5)
        }
        .background(Color.surface)
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $creating) { NewChallengeView() }
        .sensoryFeedback(.success, trigger: joinedCount)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            if Illustration.exists("challengeMountain") {
                ArtThumbnail(name: "challengeMountain", width: nil, height: 150)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No challenges yet")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                Text("Start a suggested one below, or set your own target.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        }
        .raisedCard()
        .accessibilityElement(children: .combine)
    }

    private func isRunning(_ template: ChallengeTemplate, now: Date) -> Bool {
        challenges.contains { $0.templateID == template.id && now < $0.endDate }
    }

    private func suggestions(_ templates: [ChallengeTemplate], now: Date) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.x3) {
                ForEach(templates) { template in
                    let joined = isRunning(template, now: now)
                    SuggestedChallengeCard(template: template, joined: joined) {
                        start(template)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Space.x4, for: .scrollContent)
        .padding(.horizontal, -Space.x4)
    }

    private func start(_ template: ChallengeTemplate) {
        // Suggested challenges are free.
        context.insert(template.makeChallenge())
        try? context.save()
        joinedHere.insert(template.id)
        joinedCount += 1
    }

    private func deleteButton(_ challenge: Challenge) -> some View {
        Button("Delete Challenge", systemImage: "trash", role: .destructive) {
            context.delete(challenge)
            try? context.save()
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Challenge], statuses: [UUID: ChallengeStatus], now: Date) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.x2) {
                SectionHeading(title, style: .overline)
                GroupedCard(dividerInset: 0) {
                    ForEach(items) { challenge in
                        if let status = statuses[challenge.id] {
                            NavigationLink(value: challenge) {
                                ChallengeResultRow(challenge: challenge, status: status, now: now, unit: unit)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { deleteButton(challenge) }
                        }
                    }
                }
            }
            .padding(.top, Space.x5)
        }
    }
}

/// A suggested challenge in the carousel: its symbol, Start or Joined, the name and what it asks.
private struct SuggestedChallengeCard: View {
    let template: ChallengeTemplate
    let joined: Bool
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconBadge(ChallengeText.symbol(template.metric), style: joined ? .tinted(.success) : .lane, size: 36)
                    Spacer(minLength: Space.x2)
                    Text(joined ? "Joined" : "Start")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(joined ? Color.success : Color.lane)
                }
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                    .padding(.top, 10)
                Text(template.detail)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(width: 160, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(joined)
        .accessibilityLabel(joined ? "\(template.title), joined" : "Start \(template.title)")
        .accessibilityHint(template.detail)
    }
}

/// A completed or ended challenge: icon, name, when it finished, and the final count.
private struct ChallengeResultRow: View {
    let challenge: Challenge
    let status: ChallengeStatus
    let now: Date
    let unit: UnitSystem

    var body: some View {
        let completed = status.state == .completed
        HStack(spacing: Space.x3) {
            ChallengeIcon(metric: challenge.metric, state: status.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                Text(ChallengeText.state(challenge, status: status, now: now))
                    .font(.footnote)
                    .foregroundStyle(completed ? Color.success : Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(challenge.metric.progressText(value: status.value, target: status.target, unit: unit))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Space.x4)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
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
                ChallengeCard(challenge: challenge, status: status, now: now)

                if !counted.isEmpty {
                    ChartCard(title: "Progress", summary: "\(counted.count) \(counted.count == 1 ? "run" : "runs")") {
                        progressChart(counted, now: now)
                    }
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    SectionHeading("Runs that count")
                    if counted.isEmpty {
                        Text(emptyRunsText(status))
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .raisedCard()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(counted.reversed().enumerated()), id: \.element.id) { index, run in
                                if index > 0 { Hairline(leadingInset: 84) }
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
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
                    Label("More", systemImage: "ellipsis")
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
                    .foregroundStyle(Color.lane)
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

import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Progress: the headline records, with a way into all of them.
struct RecordsSection: View {
    let records: [RecordKind: PersonalRecord]
    let runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    /// The records shown here, in order of preference.
    private static let highlights: [RecordKind] = [.effort(.fiveK), .effort(.tenK), .effort(.half), .effort(.marathon),
                                                   .longestDistance, .effort(.oneK), .effort(.oneMile)]

    var body: some View {
        let shown = Self.highlights.compactMap { records[$0] }.prefix(3)
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeader(title: "Personal records", route: records.isEmpty ? nil : .records)
            if shown.isEmpty {
                Text("Your fastest times and longest runs show up here after your first run.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .raisedCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Divider().padding(.leading, Space.x4) }
                        RecordRow(record: record, kind: record.kind, run: runs.first { $0.id == record.runID }, unit: unit)
                    }
                }
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }
}

/// A record's title, value and date; links to the run that set it.
struct RecordRow: View {
    let record: PersonalRecord?
    let kind: RecordKind
    let run: Run?
    let unit: UnitSystem

    var body: some View {
        if let run, !run.isDeleted {
            NavigationLink(value: run) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Space.x3) {
            Image(systemName: record == nil ? "trophy" : "trophy.fill")
                .font(.body)
                .foregroundStyle(record == nil ? Color.line : Color.track)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Text(detail).font(.caption).foregroundStyle(.inkMuted)
            }
            Spacer(minLength: Space.x2)
            if let record {
                let formatted = kind.formatted(record.value, unit: unit)
                HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                    Text(formatted.value).font(.metricSmall).monospacedDigit().foregroundStyle(.ink)
                    if let symbol = formatted.unit {
                        Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                    }
                }
            } else {
                Text(RunFormat.empty).font(.metricSmall).foregroundStyle(.inkMuted)
            }
            if run != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
        .frame(minHeight: Dimension.hitMin)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let record else {
            if case .effort(let distance) = kind {
                return "Run \(distance == .oneMile ? "a mile" : distance.title) to set it"
            }
            return "Not set yet"
        }
        var parts = [shortDate(record.date, alwaysYear: true)]
        if case .effort(let distance) = kind {
            let pace = RunFormat.paceSeconds(distance: distance.meters, duration: record.value, unit: unit)
            parts.append("\(RunFormat.pace(pace)) \(unit.paceSymbol)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Every personal record.
struct RecordsView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        let records = PersonalRecords.best(of: runs.map(\.recordEntry))
        let byID = Dictionary(runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                group("Best efforts", kinds: EffortDistance.allCases.map { .effort($0) }, records: records, runs: byID,
                      footer: "The fastest stretch of each distance within any run, with GPS. Runs added by hand count at their average pace.")
                group("Longest", kinds: [.longestDistance, .longestDuration, .mostElevation], records: records, runs: byID, footer: nil)
            }
            .padding(Space.x4)
        }
        .background(Color.surface)
        .navigationTitle("Personal records")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, kinds: [RecordKind], records: [RecordKind: PersonalRecord], runs: [UUID: Run],
                       footer: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(title).font(.headline).foregroundStyle(.ink)
            VStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
                    if index > 0 { Divider().padding(.leading, Space.x4) }
                    let record = records[kind]
                    RecordRow(record: record, kind: kind, run: record.flatMap { runs[$0.runID] }, unit: unit)
                }
            }
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.inkMuted)
            }
        }
    }
}

/// Run summary: the records this run just set.
struct RecordsEarnedCard: View {
    let achievements: [RecordAchievement]
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Label(achievements.count == 1 ? "New personal record" : "\(achievements.count) new personal records",
                  systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(.ink)
                .symbolEffect(.bounce, value: achievements.count)
            ForEach(achievements) { achievement in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RecordBook.title(achievement)).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                        if let improvement = RecordBook.improvement(achievement, unit: unit) {
                            Text(improvement).font(.caption).foregroundStyle(.inkMuted)
                        }
                    }
                    Spacer()
                    let formatted = achievement.kind.formatted(achievement.value, unit: unit)
                    Text([formatted.value, formatted.unit].compactMap { $0 }.joined(separator: " "))
                        .font(.metricSmall)
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .raisedCard(fill: .trackSoft)
    }
}

/// Run detail: the records this run holds now.
struct RecordBadges: View {
    let runID: UUID
    @Query private var runs: [Run]

    var body: some View {
        let held = PersonalRecords.best(of: runs.map(\.recordEntry)).values
            .filter { $0.runID == runID }
            .sorted { order($0.kind) < order($1.kind) }
        if !held.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(held) { record in
                        Label(record.kind.title, systemImage: "trophy.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ink)
                            .padding(.horizontal, Space.x3)
                            .frame(minHeight: 28)
                            .background(Color.trackSoft, in: Capsule())
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Personal records: \(held.map(\.kind.title).joined(separator: ", "))")
        }
    }

    private func order(_ kind: RecordKind) -> Int {
        RecordKind.all.firstIndex(of: kind) ?? 0
    }
}

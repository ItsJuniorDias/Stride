import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Start a suggested challenge, or set a target and time frame of your own.
struct NewChallengeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var challenges: [Challenge]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    enum Frame: String, CaseIterable, Identifiable {
        case thisWeek, thisMonth, nextWeek, nextMonth, custom
        var id: Self { self }
        var title: String {
            switch self {
            case .thisWeek: "This week"
            case .thisMonth: "This month"
            case .nextWeek: "Next 7 days"
            case .nextMonth: "Next 30 days"
            case .custom: "Until a date"
            }
        }
    }

    @State private var metric: ChallengeMetric = .distance
    /// In the unit targets are typed in: km or mi, runs, hours, m or ft, days.
    @State private var target: Double = 50
    @State private var frame: Frame = .thisMonth
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var title = ""
    @State private var upsell: ProFeature?

    /// Suggested challenges are free; making your own comes with Stride Pro.
    private var canMakeOwn: Bool { ProStore.shared.isPro }

    var body: some View {
        NavigationStack {
            Form {
                Section("Suggested") {
                    ForEach(ChallengeTemplate.catalog(unit: unit)) { template in
                        let joined = isRunning(template)
                        Button {
                            create(template.makeChallenge())
                        } label: {
                            HStack(spacing: Space.x3) {
                                ChallengeIcon(metric: template.metric, state: .active)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                                    Text(template.detail).font(.caption).foregroundStyle(.inkMuted)
                                }
                                Spacer(minLength: 0)
                                if joined {
                                    Text("Joined").font(.caption.weight(.semibold)).foregroundStyle(.success)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(joined)
                        .accessibilityHint(joined ? "Already running" : "Starts this challenge")
                    }
                }

                if !canMakeOwn {
                    Section("Your own") {
                        ProUpsellRow(symbol: "slider.horizontal.3", title: "Make your own",
                                     detail: "Pick what counts, the target and the time frame.") { upsell = .challenges }
                    }
                } else {
                Section {
                    Picker("Count", selection: $metric) {
                        ForEach(ChallengeMetric.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    LabeledContent("Target") {
                        HStack(spacing: Space.x1) {
                            TextField("0", value: $target, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(metric.displayUnit(unit, count: target)).foregroundStyle(.inkMuted)
                        }
                    }
                    Picker("Time frame", selection: $frame) {
                        ForEach(Frame.allCases) { Text($0.title).tag($0) }
                    }
                    if frame == .custom {
                        DatePicker("Last day", selection: $endDate, in: Date.now..., displayedComponents: .date)
                    }
                    TextField("Name", text: $title, prompt: Text(metric.defaultTitle(target: storedTarget, unit: unit)))
                } header: {
                    Text("Your own")
                } footer: {
                    Text(ownFooter)
                }

                Section {
                    Button("Start challenge") { create(ownChallenge) }
                        .disabled(storedTarget <= 0)
                }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .proPaywall($upsell)
            .navigationTitle("New challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: metric) { target = defaultTarget(for: metric) }
        }
    }

    private var storedTarget: Double {
        metric.storedValue(fromDisplay: max(target, 0), unit: unit)
    }

    private var interval: DateInterval {
        let now = Date.now
        switch frame {
        case .thisWeek: return ChallengeTemplate.interval(for: .thisWeek, now: now)
        case .thisMonth: return ChallengeTemplate.interval(for: .thisMonth, now: now)
        case .nextWeek: return ChallengeTemplate.interval(for: .days(7), now: now)
        case .nextMonth: return ChallengeTemplate.interval(for: .days(30), now: now)
        case .custom: return ChallengeTemplate.interval(for: .through(endDate), now: now)
        }
    }

    private var ownChallenge: Challenge {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return Challenge(title: trimmed.isEmpty ? metric.defaultTitle(target: storedTarget, unit: unit) : trimmed,
                         metric: metric, target: storedTarget, interval: interval)
    }

    private var ownFooter: String {
        let interval = interval
        let end = interval.end.addingTimeInterval(-1)
        let range = "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        return frame == .thisWeek || frame == .thisMonth
            ? "\(range). Runs you've already done this \(frame == .thisWeek ? "week" : "month") count."
            : "\(range)."
    }

    private func defaultTarget(for metric: ChallengeMetric) -> Double {
        switch metric {
        case .distance: unit == .metric ? 50 : 30
        case .runs: 10
        case .duration: 5
        case .elevation: unit == .metric ? 500 : 1_500
        case .activeDays: 10
        }
    }

    private func isRunning(_ template: ChallengeTemplate) -> Bool {
        let now = Date.now
        return challenges.contains { $0.templateID == template.id && now < $0.endDate }
    }

    private func create(_ challenge: Challenge) {
        // Your own (no template) needs Stride Pro.
        guard challenge.templateID != nil || canMakeOwn else {
            upsell = .challenges
            return
        }
        context.insert(challenge)
        try? context.save()
        dismiss()
    }
}

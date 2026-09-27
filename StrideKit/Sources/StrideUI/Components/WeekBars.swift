import SwiftUI
import StrideKit

/// A week of small bars with the day letters under them, as in Home's weekly card: a bar per day
/// with runs, scaled to the biggest day; a short `line` stub for a day without a run; an outlined
/// stub for days still to come. Today's letter is ink, the others muted. VoiceOver reads the days
/// with runs.
public struct WeekBars: View {
    public struct Day: Identifiable, Hashable, Sendable {
        public let id: Int
        /// "M", "T"…
        public let letter: String
        /// The day's amount (distance in the runner's unit), or nil for a day still to come.
        public let value: Double?
        public let isToday: Bool
        /// "Monday, 11.2 km".
        public let accessibilityLabel: String

        public init(id: Int, letter: String, value: Double?, isToday: Bool = false, accessibilityLabel: String) {
            self.id = id
            self.letter = letter
            self.value = value
            self.isToday = isToday
            self.accessibilityLabel = accessibilityLabel
        }
    }

    let days: [Day]
    let tint: Color
    let maxHeight: CGFloat
    let barWidth: CGFloat
    let title: String

    public init(days: [Day], tint: Color = .lane, maxHeight: CGFloat = 36, barWidth: CGFloat = 10,
                accessibilityLabel: String = "Distance by day") {
        self.days = days
        self.tint = tint
        self.maxHeight = maxHeight
        self.barWidth = barWidth
        self.title = accessibilityLabel
    }

    public var body: some View {
        let peak = max(days.compactMap(\.value).max() ?? 0, .leastNonzeroMagnitude)
        HStack(alignment: .bottom, spacing: Space.x1) {
            ForEach(days) { day in
                VStack(spacing: Space.x1) {
                    bar(day, peak: peak)
                        .frame(maxWidth: .infinity, minHeight: maxHeight, maxHeight: maxHeight, alignment: .bottom)
                    Text(day.letter)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(day.isToday ? Color.ink : Color.inkMuted)
                }
            }
        }
        .animation(.snappy, value: days)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
    }

    @ViewBuilder private func bar(_ day: Day, peak: Double) -> some View {
        if let value = day.value, value > 0 {
            RoundedRectangle(cornerRadius: 4)
                .fill(tint)
                .frame(width: barWidth, height: max(maxHeight * value / peak, 4))
        } else if day.value != nil {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.line)
                .frame(width: barWidth, height: 4)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.line, lineWidth: 1)
                .frame(width: barWidth, height: 4)
        }
    }

    private var summary: String {
        let ran = days.filter { ($0.value ?? 0) > 0 }
        return ran.isEmpty ? "No runs yet" : ran.map(\.accessibilityLabel).joined(separator: ", ")
    }
}

public extension WeekBars.Day {
    /// The seven days of the calendar week around `date`, in the calendar's order: each day's distance
    /// in `unit`, 0 for a past day without a run, nil for days still to come.
    static func week(of runs: [Run], around date: Date = .now, unit: UnitSystem,
                     calendar: Calendar = .current) -> [WeekBars.Day] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let today = calendar.startOfDay(for: date)
        return (0..<7).compactMap { offset -> WeekBars.Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let start = calendar.startOfDay(for: day)
            let meters = runs
                .filter { calendar.isDate($0.startDate, inSameDayAs: start) }
                .reduce(0) { $0 + $1.distance }
            let name = day.formatted(.dateTime.weekday(.wide))
            return WeekBars.Day(
                id: offset,
                letter: day.formatted(.dateTime.weekday(.narrow)),
                value: start > today ? nil : meters / unit.metersPerUnit,
                isToday: start == today,
                accessibilityLabel: meters > 0
                    ? "\(name), \(RunFormat.distance(meters, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
                    : "\(name), no run"
            )
        }
    }
}

/// How a weekly goal splits into runs, for the goal step of onboarding: up to 15 km a week is 2
/// runs, up to 40 km 3, up to 80 km 4, more 5, spread evenly over the week.
public struct WeekPlanSuggestion: Hashable, Sendable {
    public let runs: Int
    /// Per run, in the goal's unit, to the nearest half.
    public let distancePerRun: Double
    /// Calendar weekdays to run on (1 = Sunday … 7 = Saturday).
    public let weekdays: Set<Int>

    /// - Parameter weeklyGoal: in `unit`.
    public init(weeklyGoal: Double, unit: UnitSystem) {
        let kilometers = weeklyGoal * unit.metersPerUnit / 1_000
        let runs = kilometers <= 15 ? 2 : kilometers <= 40 ? 3 : kilometers <= 80 ? 4 : 5
        self.runs = runs
        self.distancePerRun = (max(weeklyGoal, 0) / Double(runs) * 2).rounded() / 2
        // Positions in a Monday-first week, as designed: Tue Sat, Tue Thu Sun, Mon Wed Fri Sun, Mon Tue Thu Fri Sun.
        let positions: [Int] = switch runs {
        case 2: [1, 5]
        case 3: [1, 3, 6]
        case 4: [0, 2, 4, 6]
        default: [0, 1, 3, 4, 6]
        }
        self.weekdays = Set(positions.map { ($0 + 1) % 7 + 1 })
    }

    /// "About 3 runs of 10 km each."
    public func sentence(unit: UnitSystem) -> String {
        "About \(runs) runs of \(distancePerRun.formatted(.number.precision(.fractionLength(0...1)))) \(unit.distanceSymbol) each."
    }
}

/// The week under the onboarding goal: a tall `lane` pill on each suggested run day, a small dot on
/// the others, the calendar's day letters under them. Hidden from VoiceOver: show
/// ``WeekPlanSuggestion/sentence(unit:)`` under it.
public struct WeekPlanStrip: View {
    let weekdays: Set<Int>
    let calendar: Calendar

    public init(weekdays: Set<Int>, calendar: Calendar = .current) {
        self.weekdays = weekdays
        self.calendar = calendar
    }

    public var body: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        HStack(spacing: Space.x2) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let runs = weekdays.contains(weekday)
                VStack(spacing: 6) {
                    Capsule()
                        .fill(runs ? Color.lane : Color.line)
                        .frame(width: runs ? 12 : 6, height: runs ? 32 : 6)
                        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .bottom)
                    Text(symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.9)
                        .foregroundStyle(.inkMuted)
                }
            }
        }
        .animation(.snappy, value: weekdays)
        .accessibilityHidden(true)
    }

    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

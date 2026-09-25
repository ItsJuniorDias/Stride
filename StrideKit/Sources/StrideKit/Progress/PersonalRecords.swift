import Foundation

/// A kind of personal record.
public enum RecordKind: Hashable, Sendable, Identifiable {
    case effort(EffortDistance)
    case longestDistance
    case longestDuration
    case mostElevation

    public static let all: [RecordKind] = EffortDistance.allCases.map { .effort($0) } + [.longestDistance, .longestDuration, .mostElevation]

    public var id: String {
        switch self {
        case .effort(let distance): "effort-\(distance.rawValue)"
        case .longestDistance: "longest-distance"
        case .longestDuration: "longest-duration"
        case .mostElevation: "most-elevation"
        }
    }

    public var title: String {
        switch self {
        case .effort(let distance): "Fastest \(distance.title)"
        case .longestDistance: "Longest run"
        case .longestDuration: "Longest time"
        case .mostElevation: "Most climbing"
        }
    }

    /// Times: lower is better. Distance, duration and climbing: higher is better.
    public var lowerIsBetter: Bool {
        if case .effort = self { return true }
        return false
    }

    /// A value of this kind for display: a time, or a distance or climb in the runner's unit.
    public func formatted(_ value: Double, unit: UnitSystem) -> (value: String, unit: String?) {
        switch self {
        case .effort, .longestDuration: (RunFormat.duration(value), nil)
        case .longestDistance: (RunFormat.distance(value, unit: unit), unit.distanceSymbol)
        case .mostElevation: (Int(unit.elevation(fromMeters: value).rounded()).formatted(), unit.elevationSymbol)
        }
    }
}

/// What records need to know about one run.
public struct RecordEntry: Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var distance: Double
    public var duration: TimeInterval
    public var elevationGain: Double
    public var efforts: [EffortDistance: TimeInterval]

    public init(id: UUID, date: Date, distance: Double, duration: TimeInterval, elevationGain: Double,
                efforts: [EffortDistance: TimeInterval]) {
        self.id = id
        self.date = date
        self.distance = distance
        self.duration = duration
        self.elevationGain = elevationGain
        self.efforts = efforts
    }
}

/// The run holding a record.
public struct PersonalRecord: Hashable, Sendable, Identifiable {
    public let kind: RecordKind
    public let runID: UUID
    public let date: Date
    /// Seconds for times, meters for distance and climbing.
    public let value: Double
    public var id: String { kind.id }
}

/// A record a run set.
public struct RecordAchievement: Hashable, Sendable, Identifiable {
    public let kind: RecordKind
    public let value: Double
    /// The record it beat; nil the first time (a first 10K).
    public let previous: Double?
    public var id: String { kind.id }
}

public enum PersonalRecords {
    public static func value(of kind: RecordKind, in entry: RecordEntry) -> Double? {
        let value: Double? = switch kind {
        case .effort(let distance): entry.efforts[distance]
        case .longestDistance: entry.distance
        case .longestDuration: entry.duration
        case .mostElevation: entry.elevationGain
        }
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    static func isBetter(_ value: Double, than other: Double, for kind: RecordKind) -> Bool {
        kind.lowerIsBetter ? value < other : value > other
    }

    /// The record for every kind that has one. A tie goes to the earlier run: it set the record first.
    public static func best(of entries: [RecordEntry]) -> [RecordKind: PersonalRecord] {
        var records: [RecordKind: PersonalRecord] = [:]
        for entry in entries {
            for kind in RecordKind.all {
                guard let value = value(of: kind, in: entry) else { continue }
                if let current = records[kind] {
                    let better = isBetter(value, than: current.value, for: kind)
                    let tieButEarlier = value == current.value && entry.date < current.date
                    guard better || tieButEarlier else { continue }
                }
                records[kind] = PersonalRecord(kind: kind, runID: entry.id, date: entry.date, value: value)
            }
        }
        return records
    }

    /// Records `entry` set against the runs before it. A first time counts for 5K and longer efforts
    /// (a first 10K is worth celebrating; every first run is a first 1K).
    public static func achievements(of entry: RecordEntry, previous: [RecordEntry]) -> [RecordAchievement] {
        let earlier = previous.filter { $0.id != entry.id && $0.date < entry.date }
        let records = best(of: earlier)
        return RecordKind.all.compactMap { kind in
            guard let value = value(of: kind, in: entry) else { return nil }
            if let record = records[kind] {
                return isBetter(value, than: record.value, for: kind)
                    ? RecordAchievement(kind: kind, value: value, previous: record.value)
                    : nil
            }
            guard case .effort(let distance) = kind, distance.meters >= EffortDistance.fiveK.meters else { return nil }
            return RecordAchievement(kind: kind, value: value, previous: nil)
        }
    }
}

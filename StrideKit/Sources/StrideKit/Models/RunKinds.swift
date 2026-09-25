import Foundation

public enum RunType: String, Codable, CaseIterable, Identifiable, Sendable {
    case free, distance, time, intervals

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .free: "Free run"
        case .distance: "Distance"
        case .time: "Time"
        case .intervals: "Intervals"
        }
    }

    public var systemImage: String {
        switch self {
        case .free: "figure.run"
        case .distance: "ruler"
        case .time: "stopwatch"
        case .intervals: "repeat"
        }
    }
}

/// How the run felt, picked on the post-run screen.
public enum Feeling: Int, Codable, CaseIterable, Identifiable, Sendable {
    case great, good, okay, tough, injured

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .great: "Great"
        case .good: "Good"
        case .okay: "Okay"
        case .tough: "Tough"
        case .injured: "Injured"
        }
    }

    public var emoji: String {
        switch self {
        case .great: "🤩"
        case .good: "🙂"
        case .okay: "😐"
        case .tough: "😩"
        case .injured: "🤕"
        }
    }
}

public enum Surface: String, Codable, CaseIterable, Identifiable, Sendable {
    case road, trail, track, treadmill, beach, mixed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .road: "Road"
        case .trail: "Trail"
        case .track: "Track"
        case .treadmill: "Treadmill"
        case .beach: "Beach"
        case .mixed: "Mixed"
        }
    }

    public var systemImage: String {
        switch self {
        case .road: "road.lanes"
        case .trail: "mountain.2.fill"
        case .track: "circle.circle"
        case .treadmill: "figure.run.treadmill"
        case .beach: "beach.umbrella.fill"
        case .mixed: "square.stack.3d.up.fill"
        }
    }
}

/// The device a run was recorded on.
public enum RunSource: String, Codable, Sendable {
    case iPhone = "iphone"
    case watch
}

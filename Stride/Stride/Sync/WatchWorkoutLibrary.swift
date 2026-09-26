import Foundation
import SwiftData
import StrideKit

/// The structured workouts Stride on Apple Watch can start by itself, sent with the settings in the
/// application context. Every runner gets the list, so the Watch can show what Pro unlocks; only Pro
/// starts them there.
enum WatchWorkoutLibrary {
    /// The application context also carries the week's snapshot and is capped by WatchConnectivity,
    /// so the list stays well under that.
    static let maxBytes = 24_000

    /// The interval presets, then the runner's own workouts newest first, so a list that doesn't fit
    /// leaves off the oldest.
    static func workouts(in context: ModelContext?) -> [Workout] {
        // Custom workouts (part C): see `CustomWorkout.forWatch(in:)` in Features/Workouts.
        IntervalPresets.all + CustomWorkout.forWatch(in: context)
    }

    /// The list as JSON for the context, dropping workouts from the end until it fits.
    static func payload(in context: ModelContext?) -> Data? {
        var workouts = workouts(in: context)
        while !workouts.isEmpty {
            if let data = WatchContext.encode(workouts), data.count <= maxBytes { return data }
            workouts.removeLast()
        }
        return nil
    }
}

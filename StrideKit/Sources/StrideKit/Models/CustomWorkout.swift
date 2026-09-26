import Foundation
import SwiftData

/// An interval workout the runner built (Stride Pro), synced with iCloud. The steps are stored as
/// JSON, so richer workouts later need no schema change. After Pro ends they stay, read-only.
@Model
public final class CustomWorkout {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    /// `[WorkoutStep]` as JSON.
    public var stepsData: Data?

    public init(name: String, steps: [WorkoutStep]) {
        self.name = name
        self.stepsData = try? JSONEncoder().encode(steps)
    }

    public var steps: [WorkoutStep] {
        get { stepsData.flatMap { try? JSONDecoder().decode([WorkoutStep].self, from: $0) } ?? [] }
        set { stepsData = try? JSONEncoder().encode(newValue) }
    }

    /// The builder's shape, or nil for steps it can't edit.
    public var blueprint: WorkoutBlueprint? { WorkoutBlueprint(steps: steps) }

    /// Has something to run: steps from a newer app version that didn't decode don't.
    public var isRunnable: Bool { steps.contains { $0.kind == .run } }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Workout" : trimmed
    }

    /// The ``Workout/id`` it runs under. Stable across edits, so a restored run and Apple Watch
    /// find the same workout.
    public var workoutID: String { Self.workoutIDPrefix + id.uuidString }

    /// Ready to run, with a detail line in the runner's unit.
    public func workout(unit: UnitSystem) -> Workout {
        let steps = self.steps
        let detail = WorkoutBlueprint(steps: steps)?.detail(unit: unit) ?? "\(steps.count) steps"
        return Workout(id: workoutID, name: displayName, detail: detail, steps: steps)
    }
}

public extension CustomWorkout {
    /// Names are short: they sit on a chip on the Run tab and on Apple Watch.
    static let maxNameLength = 30

    static let workoutIDPrefix = "custom-"
}

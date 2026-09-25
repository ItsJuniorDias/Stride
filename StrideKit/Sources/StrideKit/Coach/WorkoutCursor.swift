import Foundation

/// Follows a runner through a workout's steps using a step clock and the run's distance.
/// Codable so a run restored after the app was terminated resumes on the right step.
public struct WorkoutCursor: Codable, Sendable {
    public enum Event: Equatable, Sendable {
        case stepStarted(WorkoutStep)
        case workoutCompleted
    }

    public let workout: Workout
    public private(set) var index = 0
    private var stepStartElapsed: TimeInterval = 0
    private var stepStartDistance: Double = 0

    public init(workout: Workout) {
        self.workout = workout
    }

    public var isFinished: Bool { index >= workout.steps.count }
    public var currentStep: WorkoutStep? { isFinished ? nil : workout.steps[index] }
    public var nextStep: WorkoutStep? { index + 1 < workout.steps.count ? workout.steps[index + 1] : nil }

    /// Moves past every step whose goal is met, returning what happened in order. Several steps can
    /// complete at once when restoring a run, so this loops.
    public mutating func advance(elapsed: TimeInterval, distance: Double) -> [Event] {
        // Auto-pause can roll distance back a little; a step never starts in the future.
        stepStartElapsed = min(stepStartElapsed, elapsed)
        stepStartDistance = min(stepStartDistance, distance)
        var events: [Event] = []
        while let step = currentStep {
            let done: Bool
            switch step.goal {
            case .time(let seconds): done = elapsed - stepStartElapsed >= seconds
            case .distance(let meters): done = distance - stepStartDistance >= meters
            }
            guard done else { break }
            // The next step starts where this one's goal was met, not where we noticed it.
            switch step.goal {
            case .time(let seconds): stepStartElapsed += seconds; stepStartDistance = distance
            case .distance(let meters): stepStartDistance += meters; stepStartElapsed = elapsed
            }
            index += 1
            if let next = currentStep {
                events.append(.stepStarted(next))
            } else {
                events.append(.workoutCompleted)
            }
        }
        return events
    }

    /// Seconds or meters left in the current step.
    public func remaining(elapsed: TimeInterval, distance: Double) -> WorkoutStep.Goal? {
        guard let step = currentStep else { return nil }
        switch step.goal {
        case .time(let seconds): return .time(max(seconds - (elapsed - stepStartElapsed), 0))
        case .distance(let meters): return .distance(max(meters - (distance - stepStartDistance), 0))
        }
    }

    /// 0…1 through the current step.
    public func stepProgress(elapsed: TimeInterval, distance: Double) -> Double {
        guard let step = currentStep else { return 1 }
        switch step.goal {
        case .time(let seconds): return seconds > 0 ? min((elapsed - stepStartElapsed) / seconds, 1) : 1
        case .distance(let meters): return meters > 0 ? min((distance - stepStartDistance) / meters, 1) : 1
        }
    }
}

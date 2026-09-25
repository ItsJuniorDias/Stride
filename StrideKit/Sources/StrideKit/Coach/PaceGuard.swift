import Foundation

/// Decides when to tell the runner they're off their target pace. Avoids nagging: the pace must be
/// off for a while before an alert, alerts are spaced out, and "back on pace" is said only after an alert.
public struct PaceGuard: Sendable {
    public enum Status: Equatable, Sendable {
        case onPace
        /// Seconds per unit slower than the target range.
        case tooSlow(Double)
        /// Seconds per unit faster than the target range.
        case tooFast(Double)
    }

    /// Seconds per unit.
    public let target: Double
    /// Allowed deviation either way, seconds per unit.
    public let tolerance: Double
    /// How long the pace must stay off before an alert.
    public let confirmAfter: TimeInterval
    /// Minimum time between alerts.
    public let cooldown: TimeInterval
    /// After an alert, how long the pace must stay well inside the range before "back on pace".
    public let recoverAfter: TimeInterval

    /// For the live screen; nil until a valid pace arrives.
    public private(set) var status: Status?
    private var offSince: Date?
    private var onSince: Date?
    private var lastAlert: Date?
    private var alerted = false

    public init(target: Double, tolerance: Double = 10, confirmAfter: TimeInterval = 20, cooldown: TimeInterval = 60,
                recoverAfter: TimeInterval = 5) {
        self.target = target
        self.tolerance = tolerance
        self.confirmAfter = confirmAfter
        self.cooldown = cooldown
        self.recoverAfter = recoverAfter
    }

    /// Feed the current pace; returns a status to announce, or nil to stay quiet.
    public mutating func evaluate(currentPace: Double?, at now: Date) -> Status? {
        guard let pace = currentPace, pace.isFinite, pace > 0 else {
            offSince = nil
            onSince = nil
            status = nil
            return nil
        }
        let delta = pace - target
        let newStatus: Status = delta > tolerance ? .tooSlow(delta) : delta < -tolerance ? .tooFast(-delta) : .onPace
        status = newStatus

        if newStatus == .onPace {
            offSince = nil
            // Only after an alert, and only once the pace is clearly back (not just grazing the edge).
            guard alerted, abs(delta) <= tolerance * 0.6 else {
                onSince = nil
                return nil
            }
            guard let onSince else {
                self.onSince = now
                return nil
            }
            guard now.timeIntervalSince(onSince) >= recoverAfter else { return nil }
            alerted = false
            self.onSince = nil
            return .onPace
        }
        onSince = nil
        guard let offSince else {
            self.offSince = now
            return nil
        }
        guard now.timeIntervalSince(offSince) >= confirmAfter,
              lastAlert.map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { return nil }
        lastAlert = now
        alerted = true
        return newStatus
    }
}

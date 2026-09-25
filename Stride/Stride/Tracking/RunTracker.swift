import CoreLocation
import Observation
import SwiftData
import UIKit
import StrideKit

/// Records one run: countdown, GPS route, moving time, pauses (manual and automatic) and saving.
///
/// Distance and time only accumulate while running and not auto-paused. Every resume starts a new
/// route segment, so distance is never counted across a pause. An in-progress run is checkpointed to
/// disk so it survives the app being terminated in the background.
@Observable
final class RunTracker {
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case running
        case paused
        case finished
    }

    struct Configuration: Codable {
        var type: RunType = .free
        /// Meters, for distance runs.
        var targetDistance: Double?
        /// Seconds, for time runs.
        var targetDuration: TimeInterval?
        var workoutName: String?
        var shoeID: UUID?
        var autoPause = true
        /// Structured steps to follow: an interval preset or a training-plan session.
        var workout: Workout?
        /// Seconds per kilometer to hold; the coach says when the runner drifts off it.
        var targetPace: Double?
        /// The training-plan session this run is for.
        var planSessionID: String?
    }

    /// Voice, workout steps and pace alerts for the current run.
    let coach = RunCoach()

    enum GPSQuality {
        case searching, weak, strong

        init(accuracy: CLLocationAccuracy?) {
            guard let accuracy, accuracy >= 0 else { self = .searching; return }
            self = accuracy <= 20 ? .strong : .weak
        }
    }

    // MARK: State read by views

    private(set) var phase: Phase = .idle
    private(set) var configuration = Configuration()
    /// Moving time in seconds.
    private(set) var elapsed: TimeInterval = 0
    /// Meters.
    private(set) var distance: Double = 0
    private(set) var route: [RoutePoint] = []
    /// Smoothed speed in m/s.
    private(set) var currentSpeed: Double = 0
    private(set) var isAutoPaused = false
    private(set) var gpsQuality: GPSQuality = .searching
    private(set) var authorizationDenied = false
    /// Precise Location is off for Stride, so distance can't be measured.
    private(set) var accuracyLimited = false
    private(set) var lastLocation: CLLocation?
    private(set) var finishedRun: Run?
    /// The current run was restored from a checkpoint after the app was terminated.
    private(set) var wasRestored = false
    /// Discarded: recording stopped, the screen keeps its last state while the cover slides away,
    /// and ``reset()`` runs once it's gone.
    private(set) var isDismissing = false

    /// Incremented on events the live screen turns into haptics.
    private(set) var splitEvents = 0
    private(set) var goalEvents = 0
    private(set) var autoPauseEvents = 0

    var isPresented: Bool { phase != .idle && !isDismissing }

    var unit: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: StrideSettings.unitSystem) ?? "") ?? .metric
    }

    var weightKg: Double {
        let stored = UserDefaults.standard.double(forKey: StrideSettings.weightKg)
        return stored > 0 ? stored : 70
    }

    var calories: Double { Run.estimatedCalories(distance: distance, weightKg: weightKg) }

    /// The clock workout steps run on: moving time plus time auto-paused, minus manual pauses.
    private var stepClock: TimeInterval {
        elapsed + autoPausedTime + (autoPausedSince.map { max(Date.now.timeIntervalSince($0), 0) } ?? 0)
    }

    private func endAutoPauseInterval() {
        if let autoPausedSince {
            autoPausedTime += max(Date.now.timeIntervalSince(autoPausedSince), 0)
        }
        autoPausedSince = nil
    }

    var averagePace: Double? {
        RunFormat.paceSeconds(distance: distance, duration: elapsed, unit: unit)
    }

    var currentPace: Double? {
        guard phase == .running, !isAutoPaused, gpsQuality != .searching, currentSpeed > 0.5 else { return nil }
        return unit.metersPerUnit / currentSpeed
    }

    /// 0…1+ toward the distance or time target, nil for free runs.
    var goalProgress: Double? {
        if let target = configuration.targetDistance, target > 0 { return distance / target }
        if let target = configuration.targetDuration, target > 0 { return elapsed / target }
        return nil
    }

    // MARK: Private state

    @ObservationIgnored private var segment = 0
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var segmentStart: Date?
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var completedSplits = 0
    @ObservationIgnored private var goalReached = false
    @ObservationIgnored private var wantsPreview = false
    @ObservationIgnored private var isStationary = false
    @ObservationIgnored private var lastValidAltitude: Double?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var runPendingDeletion: Run?

    // Auto-pause detection: where the runner was when they first slowed down.
    @ObservationIgnored private var slowSince: Date?
    @ObservationIgnored private var distanceAtSlowStart = 0.0
    @ObservationIgnored private var routeCountAtSlowStart = 0
    /// Timestamp of the last fix that passed the accuracy filters; a gap resets the slow window.
    @ObservationIgnored private var lastAcceptedFixTime: Date?
    /// Time spent auto-paused. Workout steps count it (a recovery taken standing still still ends),
    /// moving time doesn't.
    @ObservationIgnored private var autoPausedTime: TimeInterval = 0
    @ObservationIgnored private var autoPausedSince: Date?
    /// The plan session this run marked done, so discarding the run can undo it.
    @ObservationIgnored private var newlyCompletedSessionID: String?
    /// Auto-pause never back-dates further than this, so an old slow window can't erase real running.
    private static let maxAutoPauseBackdate: TimeInterval = 20

    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?

    // MARK: GPS preview (run setup screen)

    /// Starts location updates so the setup screen can show GPS quality before the run.
    func startPreview() {
        wantsPreview = true
        startLocationUpdates()
    }

    func stopPreview() {
        wantsPreview = false
        if phase == .idle { stopLocationUpdates() }
    }

    // MARK: Run lifecycle

    func start(_ configuration: Configuration) {
        guard phase == .idle else { return }
        self.configuration = configuration
        wasRestored = false
        startLocationUpdates()
        // Created now, from the START tap while the app is in use: locking the phone
        // during the countdown must not suspend the app.
        beginBackgroundSession()

        // Deadline-based, so a late wake-up can't shift when the run starts.
        let startAt = Date.now.addingTimeInterval(3)
        phase = .countdown(3)
        countdownTask = Task { [weak self] in
            for number in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.phase = .countdown(number)
                let next = startAt.addingTimeInterval(-Double(number - 1))
                try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0)))
            }
            guard !Task.isCancelled else { return }
            self?.beginRunning(at: startAt)
        }
    }

    /// Skips the rest of the countdown.
    func startNow() {
        guard case .countdown = phase else { return }
        countdownTask?.cancel()
        beginRunning(at: .now)
    }

    func cancelCountdown() {
        guard case .countdown = phase else { return }
        countdownTask?.cancel()
        reset()
    }

    func pause() {
        guard phase == .running, !isDismissing else { return }
        closeSegment(at: .now)
        endAutoPauseInterval()
        coach.sync(stepClock: stepClock, distance: distance)
        isAutoPaused = false
        slowSince = nil
        lastAcceptedFixTime = nil
        currentSpeed = 0
        phase = .paused
        coach.paused()
        checkpoint()
    }

    func resume() {
        guard phase == .paused, !isDismissing else { return }
        // After a restore, location updates and the background session start again here.
        startLocationUpdates()
        beginBackgroundSession()
        if clockTask == nil { startClock() }
        openSegment(at: .now)
        slowSince = nil
        lastAcceptedFixTime = nil
        wasRestored = false
        phase = .running
        coach.resumed()
        checkpoint()
    }

    /// Stops recording, saves the run and shows the summary.
    func finish(in context: ModelContext) {
        guard phase == .running || phase == .paused, !isDismissing else { return }
        closeSegment(at: .now)
        endAutoPauseInterval()
        // The last step may have ended between clock ticks; catch up before checking completion.
        coach.sync(stepClock: stepClock, distance: distance)
        stopRecording()

        let run = Run(startDate: startDate ?? .now, duration: elapsed, distance: distance, type: configuration.type)
        if route.count > 1 {
            run.apply(route: route, weightKg: weightKg)
        }
        // The clock and live distance are the source of truth; the route fills in the rest.
        run.duration = elapsed
        run.distance = distance
        run.calories = calories
        run.workoutName = configuration.workoutName ?? configuration.workout?.name
        run.planSessionID = configuration.planSessionID
        // A plan session counts as done when every step of it was completed.
        if let sessionID = configuration.planSessionID, coach.workoutComplete, !PlanProgress.completed.contains(sessionID) {
            PlanProgress.markCompleted(sessionID)
            newlyCompletedSessionID = sessionID
        }
        coach.finished(distance: distance, elapsed: elapsed)
        if let shoeID = configuration.shoeID {
            let descriptor = FetchDescriptor<Shoe>(predicate: #Predicate { $0.id == shoeID })
            run.shoe = try? context.fetch(descriptor).first
        }
        context.insert(run)
        try? context.save()
        clearCheckpoint()

        finishedRun = run
        phase = .finished
    }

    /// Stops without saving. The state stays frozen until the cover is dismissed and calls ``reset()``.
    func discard() {
        stopRecording()
        clearCheckpoint()
        coach.silence()
        isDismissing = true
    }

    /// Closes the summary and marks its already-saved run for deletion. The run is deleted in
    /// ``takeRunPendingDeletion()`` once the cover has finished dismissing, so no view renders a deleted model.
    func discardSaved(_ run: Run) {
        // A discarded run doesn't count toward the plan.
        if let sessionID = newlyCompletedSessionID, run.planSessionID == sessionID {
            PlanProgress.set(sessionID, done: false)
        }
        runPendingDeletion = run
        reset()
    }

    func takeRunPendingDeletion() -> Run? {
        defer { runPendingDeletion = nil }
        return runPendingDeletion
    }

    /// Clears everything after the summary is closed.
    func reset() {
        countdownTask?.cancel()
        clockTask?.cancel()
        clockTask = nil
        endBackgroundSession()
        phase = .idle
        isDismissing = false
        configuration = Configuration()
        elapsed = 0
        distance = 0
        route = []
        currentSpeed = 0
        isAutoPaused = false
        finishedRun = nil
        wasRestored = false
        segment = 0
        accumulated = 0
        segmentStart = nil
        startDate = nil
        slowSince = nil
        lastAcceptedFixTime = nil
        lastValidAltitude = nil
        completedSplits = 0
        goalReached = false
        autoPausedTime = 0
        autoPausedSince = nil
        newlyCompletedSessionID = nil
        coach.reset(stopVoice: false)
        if !wantsPreview { stopLocationUpdates() }
    }

    // MARK: Clock

    private func beginRunning(at start: Date) {
        guard case .countdown = phase else { return }
        startDate = start
        segmentStart = start
        phase = .running
        coach.begin(configuration, unit: unit)
        startClock()
        checkpoint()
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func tick() {
        elapsed = accumulated + (segmentStart.map { max(Date.now.timeIntervalSince($0), 0) } ?? 0)

        if let progress = goalProgress, progress >= 1, !goalReached {
            goalReached = true
            goalEvents += 1
        }

        if phase == .running {
            if isAutoPaused {
                coach.tickSteps(stepClock: stepClock, distance: distance)
            } else {
                coach.tick(elapsed: elapsed, stepClock: stepClock, distance: distance,
                           currentPace: currentPace, averagePace: averagePace)
            }
        }

        // A stationary report that arrived before this segment (while paused, or during the
        // countdown) is never repeated: pause once the runner has stood still for the grace period.
        if phase == .running, configuration.autoPause, isStationary, !isAutoPaused,
           let segmentStart, Date.now.timeIntervalSince(segmentStart) >= 6 {
            autoPause()
        }

        // Fixes stopped arriving while moving: the chip must not keep saying "strong".
        if phase == .running, !isAutoPaused, !isStationary,
           lastLocation.map({ $0.timestamp.timeIntervalSinceNow < -10 }) ?? true {
            gpsQuality = .searching
        }

        if phase == .running, Date.now.timeIntervalSince(lastCheckpoint) >= 15 {
            checkpoint()
        }
    }

    private func openSegment(at date: Date) {
        if !route.isEmpty { segment += 1 }
        segmentStart = date
    }

    private func closeSegment(at end: Date) {
        if let segmentStart {
            accumulated += max(end.timeIntervalSince(segmentStart), 0)
        }
        segmentStart = nil
        elapsed = accumulated
    }

    private func stopRecording() {
        countdownTask?.cancel()
        clockTask?.cancel()
        clockTask = nil
        endBackgroundSession()
        if !wantsPreview { stopLocationUpdates() }
    }

    private func beginBackgroundSession() {
        if backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func endBackgroundSession() {
        backgroundSession?.invalidate()
        backgroundSession = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Location

    private func startLocationUpdates() {
        guard locationTask == nil else { return }
        // The purpose key asks for temporary full accuracy when Precise Location is off.
        serviceSession = CLServiceSession(authorization: .whenInUse, fullAccuracyPurposeKey: "RunTracking")
        locationTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    self.authorizationDenied = update.authorizationDenied
                        || update.authorizationDeniedGlobally
                        || update.authorizationRestricted
                    self.accuracyLimited = update.accuracyLimited
                    self.isStationary = update.stationary
                    // The system stops sending fixes while the device is still, so standing at a
                    // light never produces the slow fixes auto-pause waits for. Pause on the signal.
                    if update.stationary {
                        self.handleStationary()
                    }
                    if update.locationUnavailable {
                        self.gpsQuality = .searching
                    }
                    if let location = update.location {
                        self.handle(location)
                    }
                }
            } catch {
                self?.gpsQuality = .searching
            }
        }
    }

    private func stopLocationUpdates() {
        locationTask?.cancel()
        locationTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
        gpsQuality = .searching
        isStationary = false
    }

    private func handle(_ location: CLLocation) {
        lastLocation = location
        // Cached fixes delivered at startup don't count as a GPS lock.
        if location.timestamp.timeIntervalSinceNow > -5 {
            gpsQuality = GPSQuality(accuracy: location.horizontalAccuracy)
        }

        guard phase == .running,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 30,
              location.timestamp.timeIntervalSinceNow > -10
        else { return }

        // Slow fixes only count toward auto-pause when they're consecutive.
        if let last = lastAcceptedFixTime, location.timestamp.timeIntervalSince(last) > 5 {
            slowSince = nil
        }
        lastAcceptedFixTime = location.timestamp

        var speed = location.speed
        if speed < 0, let reference = lastPointInSegment {
            if isAutoPaused {
                // Dividing by the whole pause would hide movement for minutes: resume on real displacement.
                speed = location.distance(from: reference.location) > max(20, 2 * location.horizontalAccuracy) ? 2 : 0
            } else {
                let dt = location.timestamp.timeIntervalSince(reference.timestamp)
                speed = dt > 0 ? location.distance(from: reference.location) / dt : 0
            }
        }
        speed = max(speed, 0)
        // A GPS jump: faster than any runner. Ignore the fix entirely, including for current pace.
        guard speed < 12 else { return }
        currentSpeed = currentSpeed == 0 ? speed : currentSpeed * 0.7 + speed * 0.3

        if configuration.autoPause, updateAutoPause(speed: speed, at: location.timestamp) {
            return
        }

        // Looked up after the auto-pause decision: an auto-resume just opened a new segment,
        // and distance is never counted across a pause.
        if let previous = lastPointInSegment {
            let meters = location.distance(from: previous.location)
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0, meters / seconds < 12, meters >= 1 else { return }
            distance += meters
        }

        route.append(RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: sanitizedAltitude(for: location),
            timestamp: location.timestamp,
            segment: segment
        ))

        let splitsDone = Int(distance / unit.metersPerUnit)
        if splitsDone > completedSplits {
            completedSplits = splitsDone
            splitEvents += 1
        }
    }

    private var lastPointInSegment: RoutePoint? {
        route.last.flatMap { $0.segment == segment ? $0 : nil }
    }

    /// Only altitudes with a vertical accuracy of 20 m or better are stored; others repeat the last
    /// good value. Points recorded before the first good altitude are back-filled with it.
    private func sanitizedAltitude(for location: CLLocation) -> Double {
        let isValid = location.verticalAccuracy >= 0 && location.verticalAccuracy <= 20
        guard isValid else { return lastValidAltitude ?? location.altitude }
        if lastValidAltitude == nil {
            for index in route.indices { route[index].altitude = location.altitude }
        }
        lastValidAltitude = location.altitude
        return location.altitude
    }

    /// Returns true while auto-paused, so the location is not recorded.
    private func updateAutoPause(speed: Double, at time: Date) -> Bool {
        if isAutoPaused {
            guard speed > 1.3 else { return true }
            isAutoPaused = false
            endAutoPauseInterval()
            openSegment(at: .now)
            // Start current pace from this fix, not from the standing speeds before the pause.
            currentSpeed = speed
            autoPauseEvents += 1
            coach.autoResumed()
            checkpoint()
            return false
        }
        guard speed < 0.5 else {
            slowSince = nil
            return false
        }
        guard let slowSince else {
            self.slowSince = time
            distanceAtSlowStart = distance
            routeCountAtSlowStart = route.count
            return false
        }
        guard time.timeIntervalSince(slowSince) >= 6 else { return false }
        autoPause()
        return true
    }

    /// The system reported the device as stationary: auto-pause from when the runner stopped.
    private func handleStationary() {
        guard phase == .running, configuration.autoPause, !isAutoPaused else { return }
        autoPause()
    }

    /// Back-dates the pause to when the runner first slowed down (or to the last recorded fix):
    /// the detection window is neither moving time nor distance.
    private func autoPause() {
        let floor = Date.now.addingTimeInterval(-Self.maxAutoPauseBackdate)
        if let slowSince, slowSince >= floor {
            autoPausedSince = slowSince
            closeSegment(at: slowSince)
            distance = distanceAtSlowStart
            if route.count > routeCountAtSlowStart {
                route.removeSubrange(routeCountAtSlowStart...)
            }
        } else {
            // Stationary with no fix yet in this segment means no movement since it opened.
            let stoppedAt = max(lastPointInSegment?.timestamp ?? segmentStart ?? .now, floor)
            autoPausedSince = stoppedAt
            closeSegment(at: stoppedAt)
        }
        // The rollback can undo a split or goal crossed inside the slow window; they fire again later.
        completedSplits = min(completedSplits, Int(distance / unit.metersPerUnit))
        goalReached = (goalProgress ?? 0) >= 1
        isAutoPaused = true
        slowSince = nil
        currentSpeed = 0
        autoPauseEvents += 1
        coach.autoPaused()
        checkpoint()
    }

    // MARK: Checkpoint

    private struct Checkpoint: Codable {
        var configuration: Configuration
        var startDate: Date
        /// Moving time up to `savedAt`.
        var accumulated: TimeInterval
        var segment: Int
        var distance: Double
        var route: [RoutePoint]
        var completedSplits: Int
        var goalReached: Bool
        var lastValidAltitude: Double?
        /// Time auto-paused so far, including an auto-pause still open at `savedAt`.
        var autoPausedTime: TimeInterval?
        var coach: RunCoach.Snapshot?
        var savedAt: Date
    }

    private static var checkpointURL: URL {
        URL.applicationSupportDirectory.appending(path: "active-run.json")
    }

    /// Writes the in-progress run to disk. Called on pause/resume, every 15 s while running,
    /// and when the app moves to the background.
    func checkpoint() {
        guard phase == .running || phase == .paused, !isDismissing, let startDate else { return }
        let now = Date.now
        let checkpoint = Checkpoint(
            configuration: configuration,
            startDate: startDate,
            accumulated: accumulated + (segmentStart.map { max(now.timeIntervalSince($0), 0) } ?? 0),
            segment: segment,
            distance: distance,
            route: route,
            completedSplits: completedSplits,
            goalReached: goalReached,
            lastValidAltitude: lastValidAltitude,
            autoPausedTime: autoPausedTime + (autoPausedSince.map { max(now.timeIntervalSince($0), 0) } ?? 0),
            coach: coach.snapshot,
            savedAt: now
        )
        do {
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(checkpoint).write(to: Self.checkpointURL, options: .atomic)
            lastCheckpoint = now
        } catch {
            // A failed checkpoint only matters if the app is terminated; keep running.
        }
    }

    private func clearCheckpoint() {
        try? FileManager.default.removeItem(at: Self.checkpointURL)
        lastCheckpoint = .distantPast
    }

    /// Restores a run interrupted by the app being terminated, paused, so the runner can resume or finish it.
    func restoreIfNeeded() {
        guard phase == .idle,
              let data = try? Data(contentsOf: Self.checkpointURL),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data)
        else { return }

        configuration = checkpoint.configuration
        startDate = checkpoint.startDate
        accumulated = checkpoint.accumulated
        elapsed = checkpoint.accumulated
        segment = checkpoint.segment
        distance = checkpoint.distance
        route = checkpoint.route
        completedSplits = checkpoint.completedSplits
        goalReached = checkpoint.goalReached
        lastValidAltitude = checkpoint.lastValidAltitude
        segmentStart = nil
        autoPausedTime = checkpoint.autoPausedTime ?? 0
        autoPausedSince = nil
        wasRestored = true
        phase = .paused
        coach.restore(configuration, unit: unit, snapshot: checkpoint.coach,
                      elapsed: accumulated, stepClock: accumulated + autoPausedTime, distance: distance)
        startLocationUpdates()
    }
}

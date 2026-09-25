import HealthKit
import Observation
import WatchConnectivity
import StrideKit

/// A workout running on Apple Watch, mirrored to iPhone. HealthKit hands the mirrored session over
/// even when Stride isn't running, so the handler is installed at launch. Metrics arrive as
/// ``MirrorSnapshot`` messages from the Watch; Pause, Resume and End act on the Watch's workout.
///
/// If the link drops, the Watch keeps recording and mirrors again when it can; iPhone freezes the
/// clock, disables the controls and offers Close. The finished run arrives through ``WatchSync`` either way.
@Observable
final class MirroredWorkout: NSObject {
    static let shared = MirroredWorkout()

    enum Phase: Equatable {
        case idle, running, paused, ended
    }

    private(set) var phase: Phase = .idle
    private(set) var snapshot: MirrorSnapshot?
    private(set) var route = MirroredRoute()
    /// A mirrored session is attached and valid.
    private(set) var isLinked = false
    /// Snapshots are arriving (the last one is less than 10 s old).
    private(set) var isConnected = true
    /// Start on Watch failed or timed out, shown on the Run screen.
    private(set) var error: String?
    /// Pause, Resume or End didn't reach the Watch, shown on the live screen.
    private(set) var controlError: String?
    /// "Start on Watch" is waiting for the Watch to start and mirror a run.
    private(set) var isStartingOnWatch = false
    /// A paired Apple Watch has Stride installed.
    private(set) var canStartOnWatch = false
    /// Done was tapped; state stays until the cover has animated away, then ``reset()`` runs.
    private(set) var isDismissing = false

    var isPresented: Bool { phase != .idle && !isDismissing }

    let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var lastMessage = Date.distantPast
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var startTimeout: Task<Void, Never>?
    @ObservationIgnored private var sessionStartDate: Date?
    @ObservationIgnored private var routeEpoch: UUID?
    @ObservationIgnored private var pendingGoal: (goal: MirrorGoal, requestedAt: Date)?
    @ObservationIgnored private var lastGoalSend = Date.distantPast
    @ObservationIgnored private var isDemo = false

    /// Moving time and moment of the last pause, resume, end or disconnect.
    private var anchor: (elapsed: TimeInterval, date: Date)?

    /// Moving time at a moment, never counting paused time.
    ///
    /// A pause or resume reaches iPhone as a session state change, usually before the Watch's next
    /// snapshot. The state change sets an anchor; snapshots older than the anchor are ignored for time.
    /// While unlinked the clock is frozen at the last thing the Watch told us.
    func elapsed(at date: Date) -> TimeInterval {
        if !isLinked, let anchor { return anchor.elapsed }
        if let snapshot, anchor.map({ snapshot.sentAt >= $0.date }) ?? true {
            return snapshot.elapsed(at: date)
        }
        guard let anchor else { return 0 }
        return phase == .running ? anchor.elapsed + max(date.timeIntervalSince(anchor.date), 0) : anchor.elapsed
    }

    private func setAnchor(at date: Date) {
        anchor = (elapsed(at: date), date)
    }

    // MARK: Setup

    /// Installs the mirroring handler. Call once, as early as possible at launch.
    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirrored in
            Task { @MainActor in self?.attach(mirrored) }
        }
    }

    /// Refreshed by ``WatchSync`` whenever pairing or the Watch app's install state changes.
    func updateWatchAvailability() {
        canStartOnWatch = WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    // MARK: Authorization

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
         HKQuantityType(.distanceWalkingRunning), HKObjectType.workoutType()]
    }

    /// Asks once; HealthKit doesn't show the sheet again after the runner has answered.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: readTypes)
    }

    // MARK: Controls

    /// Opens Stride on Apple Watch and starts a run there with `goal`; it then mirrors back here.
    func startOnWatch(goal: MirrorGoal?) async {
        guard !isStartingOnWatch, phase == .idle else { return }
        isStartingOnWatch = true
        pendingGoal = goal.map { ($0, .now) }
        await requestAuthorization()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        do {
            try await healthStore.startWatchApp(toHandle: configuration)
            error = nil
        } catch {
            isStartingOnWatch = false
            pendingGoal = nil
            self.error = "Couldn't open Stride on Apple Watch. Make sure it's nearby and unlocked."
            return
        }
        // Opening the app isn't a run yet: wait for the mirrored session.
        startTimeout?.cancel()
        startTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled, self.isStartingOnWatch, self.phase == .idle else { return }
            self.isStartingOnWatch = false
            self.pendingGoal = nil
            self.error = "Stride on Apple Watch didn't start a run. Open Stride on your Watch and start it there."
        }
    }

    func pause() {
        if let session { session.pause() } else if isDemo { setAnchor(at: .now); phase = .paused }
    }

    func resume() {
        if let session { session.resume() } else if isDemo { setAnchor(at: .now); phase = .running }
    }

    func end() {
        if let session { session.end() } else if isDemo { setAnchor(at: .now); phase = .ended }
    }

    /// Closes the live screen. The state stays until the cover is gone and RootView calls ``reset()``.
    func dismiss() {
        watchdog?.cancel()
        isDismissing = true
    }

    func reset() {
        watchdog?.cancel()
        watchdog = nil
        session = nil
        snapshot = nil
        anchor = nil
        route = MirroredRoute()
        routeEpoch = nil
        sessionStartDate = nil
        isLinked = false
        isConnected = true
        isDemo = false
        isDismissing = false
        controlError = nil
        phase = .idle
    }

    func clearError() {
        error = nil
    }

    func clearControlError() {
        controlError = nil
    }

    /// A Watch run was imported. If the live screen lost the Watch, this run is the one it was
    /// showing: move to the finished screen so it can be closed.
    func watchRunImported(startDate: Date) {
        guard phase == .running || phase == .paused, !isLinked || !isConnected else { return }
        if let sessionStartDate, abs(sessionStartDate.timeIntervalSince(startDate)) > 120 { return }
        watchdog?.cancel()
        phase = .ended
    }

    // MARK: Session

    private func attach(_ mirrored: HKWorkoutSession) {
        // A replacement session mid-run (the Watch mirrored again after a drop) keeps what we have;
        // the Watch resends any route we missed.
        let continuing = (phase == .running || phase == .paused) && !isDismissing
        session = mirrored
        mirrored.delegate = self
        isLinked = true
        isConnected = true
        isDismissing = false
        lastMessage = .now
        startTimeout?.cancel()
        isStartingOnWatch = false
        if !continuing {
            route = MirroredRoute()
            routeEpoch = nil
            snapshot = nil
            anchor = nil
            sessionStartDate = mirrored.startDate
        } else {
            // Unfreeze the clock from where it stopped.
            if let frozen = anchor { anchor = (frozen.elapsed, .now) }
        }
        phase = mirrored.state == .paused ? .paused : .running
        startWatchdog()
        sendPendingGoalIfNeeded()
    }

    /// Updates the connection state every 2 s. A minute of silence counts as a lost link,
    /// in case the disconnect callback never comes.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.phase == .running || self.phase == .paused else { continue }
                let silence = Date.now.timeIntervalSince(self.lastMessage)
                self.isConnected = self.isLinked && silence < 10
                if self.isLinked, !self.isDemo, silence > 60 { self.unlink() }
            }
        }
    }

    private func unlink() {
        anchor = (elapsed(at: lastMessage), lastMessage)
        session = nil
        isLinked = false
        isConnected = false
    }

    fileprivate func handleState(_ state: HKWorkoutSessionState, of mirrored: HKWorkoutSession, date: Date) {
        guard mirrored === session else { return }
        switch state {
        case .running:
            setAnchor(at: date)
            phase = .running
        case .paused:
            setAnchor(at: date)
            phase = .paused
        case .ended, .stopped:
            setAnchor(at: date)
            phase = .ended
            watchdog?.cancel()
        default: break
        }
    }

    fileprivate func handleData(_ data: [Data], from mirrored: HKWorkoutSession) {
        guard mirrored === session else { return }
        let decoder = JSONDecoder()
        for item in data {
            guard let snapshot = try? decoder.decode(MirrorSnapshot.self, from: item) else { continue }
            lastMessage = .now
            isConnected = true
            if let epoch = snapshot.routeEpoch, epoch != routeEpoch {
                // The Watch recovered from a crash and restarted its route indices.
                if routeEpoch != nil { route.truncate(to: snapshot.routeEpochBase) }
                routeEpoch = epoch
            }
            if !route.merge(snapshot.coordinates, startingAt: snapshot.firstCoordinateIndex) {
                requestResend(from: route.coordinates.count)
            }
            // Snapshots can arrive out of order after a reconnect; keep the newest.
            if (self.snapshot?.sentAt ?? .distantPast) <= snapshot.sentAt {
                self.snapshot = snapshot
            }
            if snapshot.goalName != nil {
                pendingGoal = nil
            } else {
                sendPendingGoalIfNeeded()
            }
        }
    }

    fileprivate func handleDisconnect(of mirrored: HKWorkoutSession) {
        guard mirrored === session, phase != .ended else { return }
        unlink()
    }

    fileprivate func handleFailure(of mirrored: HKWorkoutSession) {
        guard mirrored === session else { return }
        controlError = "Apple Watch didn't respond. Use your Watch to pause or end the run."
    }

    /// The Watch sent coordinates after a gap (iPhone joined mid-run): ask it to resend.
    private func requestResend(from index: Int) {
        guard let session, let data = try? JSONEncoder().encode(MirrorRequest(resendFrom: index)) else { return }
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    /// Sends the goal chosen for "Start on Watch" until a snapshot shows the Watch applied it.
    private func sendPendingGoalIfNeeded() {
        guard let pending = pendingGoal, let session else { return }
        guard Date.now.timeIntervalSince(pending.requestedAt) < 60 else {
            pendingGoal = nil
            return
        }
        guard Date.now.timeIntervalSince(lastGoalSend) >= 2,
              let data = try? JSONEncoder().encode(MirrorCommand(goal: pending.goal)) else { return }
        lastGoalSend = .now
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }
}

extension MirroredWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.handleState(toState, of: workoutSession, date: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.handleFailure(of: workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.handleData(data, from: workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.handleDisconnect(of: workoutSession) }
    }
}

#if DEBUG
extension MirroredWorkout {
    /// Launch with `-demoMirroredWorkout` to preview the live screen with a simulated Watch run.
    func startDemo() {
        isDemo = true
        isLinked = true
        phase = .running
        isConnected = true
        route = MirroredRoute()
        let center = Coordinate(latitude: -23.5874, longitude: -46.6576)
        var elapsed: TimeInterval = 1_284
        watchdog = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                // Like a real Watch: nothing moves while paused.
                guard self.phase == .running || self.snapshot == nil else {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                elapsed += 1
                let points = (tick * 3..<(tick * 3 + 3)).map { i -> Coordinate in
                    let angle = Double(i) * 0.02
                    return Coordinate(latitude: center.latitude + 0.004 * sin(angle), longitude: center.longitude + 0.006 * cos(angle))
                }
                self.route.merge(points, startingAt: tick * 3)
                self.lastMessage = .now
                self.snapshot = MirrorSnapshot(
                    elapsed: elapsed, isPaused: self.phase == .paused, distance: elapsed * 3.2,
                    heartRate: 152 + Double(tick % 7), averageHeartRate: 148, calories: elapsed * 0.19,
                    currentSpeed: 3.25, zoneSeconds: [2: 240, 3: 780, 4: Double(260 + tick)],
                    goalName: "10 km", goalDistance: 10_000)
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Launch with `-demoMirroredWorkout -demoDisconnect` to see the lost-link state after 5 s.
    func simulateDisconnect() {
        watchdog?.cancel()
        unlink()
    }
}
#endif

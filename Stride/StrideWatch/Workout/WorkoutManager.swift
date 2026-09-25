import CoreLocation
import HealthKit
import WidgetKit
import Observation
import WatchKit
import StrideKit

/// Runs one workout on Apple Watch: an HKWorkoutSession with a live builder for heart rate,
/// distance and energy, GPS for the route, heart-rate zones, and handing the result to iPhone.
///
/// Every HealthKit callback is checked against the current session and builder, so a late callback
/// from a cancelled or finished workout can never change the state of the next one.
@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case running
        case paused
        case ended
    }

    struct Goal: Equatable, Codable {
        var type: RunType = .free
        /// Meters, for distance runs.
        var distance: Double?
        /// Seconds, for time runs.
        var duration: TimeInterval?
        var name: String?
    }

    // MARK: State read by views

    private(set) var phase: Phase = .idle
    private(set) var goal = Goal()
    /// Set when the activity starts; Cancel is no longer offered after that.
    private(set) var startDate: Date?
    private(set) var heartRate: Double?
    private(set) var averageHeartRate: Double?
    private(set) var maxHeartRateSeen: Double?
    /// Meters, from the live builder.
    private(set) var distance: Double = 0
    /// Kilocalories.
    private(set) var activeEnergy: Double = 0
    /// Smoothed GPS speed in m/s.
    private(set) var currentSpeed: Double = 0
    private(set) var zoneSeconds: [HeartRateZone: TimeInterval] = [:]
    private(set) var summary: RunTransfer?
    /// The workout was saved to Apple Health (shown on the summary).
    private(set) var savedToHealth = false
    /// End was tapped and the workout is being saved.
    private(set) var isEnding = false
    /// Health access problem, shown on the start list.
    private(set) var authorizationError: String?
    /// A workout failed to start or stopped unexpectedly, shown as an alert.
    private(set) var workoutError: String?
    /// Title of that alert; missing Health access gets its own.
    private(set) var workoutErrorTitle = "Workout problem"
    /// A start is waiting for Health access; the start list disables its buttons meanwhile.
    private(set) var isCheckingAccess = false
    private(set) var locationDenied = false

    let healthStore = HKHealthStore()

    var maxHeartRate: Double {
        let stored = UserDefaults.standard.double(forKey: StrideSettings.maxHeartRate)
        return stored > 0 ? stored : HeartRateZone.defaultMaxHeartRate
    }

    var currentZone: HeartRateZone? {
        heartRate.flatMap { HeartRateZone.zone(for: $0, maxHeartRate: maxHeartRate) }
    }

    /// Moving time, from the builder so pauses are excluded.
    func elapsedTime(at date: Date = .now) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    /// Nil while paused, before a speed is known, or when the last speed is more than 5 s old.
    func currentPace(unit: UnitSystem, at date: Date = .now) -> Double? {
        guard phase == .running, let last = lastSpeedFixDate,
              date.timeIntervalSince(last) <= 5, currentSpeed > 0.5 else { return nil }
        return unit.metersPerUnit / currentSpeed
    }

    func goalProgress(at date: Date = .now) -> Double? {
        if let target = goal.distance, target > 0 { return distance / target }
        if let target = goal.duration, target > 0 { return elapsedTime(at: date) / target }
        return nil
    }

    func clearWorkoutError() {
        workoutError = nil
    }

    // MARK: Private state

    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var routeBuilder: HKWorkoutRouteBuilder?
    @ObservationIgnored private var route: [RoutePoint] = []
    @ObservationIgnored private var segment = 0
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var lastHeartRateDate: Date?
    @ObservationIgnored private var lastSpeedFixDate: Date?
    @ObservationIgnored private var lastValidAltitude: Double?
    @ObservationIgnored private var splitUnit: UnitSystem = .metric
    @ObservationIgnored private var completedSplits = 0
    @ObservationIgnored private var goalReached = false
    @ObservationIgnored private var isFinishing = false
    @ObservationIgnored private var lastJournalWrite = Date.distantPast
    @ObservationIgnored private var mirrorTask: Task<Void, Never>?
    @ObservationIgnored private var remirrorTask: Task<Void, Never>?
    @ObservationIgnored private var sendFailures = 0
    /// Route coordinates the iPhone has confirmed receiving.
    @ObservationIgnored private var sentCoordinateCount = 0
    /// Route indices restart after a recovery; iPhone keeps the first `routeEpochBase` of the old epoch.
    @ObservationIgnored private var routeEpoch = UUID()
    @ObservationIgnored private var routeEpochBase = 0
    /// Started from iPhone's "Start on Watch": the goal chosen there may follow over the mirrored session.
    @ObservationIgnored private var startedFromCompanion = false
    /// The Health and location request in flight; every caller shares it.
    @ObservationIgnored private var authorizationRequest: Task<Void, Never>?

    // MARK: Authorization

    /// Workout sharing as Health reports it. Stays `.notDetermined` while a request waits for an
    /// answer that hasn't arrived, e.g. one watchOS handed to the paired iPhone.
    private var workoutAccess: HKAuthorizationStatus {
        healthStore.authorizationStatus(for: .workoutType())
    }

    private var canSaveWorkouts: Bool {
        workoutAccess == .sharingAuthorized
    }

    /// What to do about missing Health access, for the start list and the alert.
    private var healthAccessMessage: String {
        workoutAccess == .notDetermined
            ? "Stride needs Health access to record runs. Open Stride on your iPhone and allow it, then try again."
            : "Health access is off. On iPhone, open Health › your picture › Privacy › Apps › Stride and turn on Workouts."
    }

    /// Asks for Health and location access from the start list, so no prompt appears over a countdown.
    /// Calls made while a request is out wait for that one.
    func requestAuthorization() async {
        await authorizationRequestTask().value
    }

    private func authorizationRequestTask() -> Task<Void, Never> {
        if let authorizationRequest { return authorizationRequest }
        let task = Task { [weak self] in
            await self?.askForAccess()
            self?.authorizationRequest = nil
        }
        authorizationRequest = task
        return task
    }

    private func askForAccess() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKObjectType.workoutType(),
        ]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
        // Denying doesn't throw, and a request handed to iPhone can return before it's answered:
        // check the result instead of the call.
        authorizationError = canSaveWorkouts ? nil : healthAccessMessage

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        updateLocationAccess()
    }

    /// Re-reads access when the app becomes active, e.g. after the runner allowed it on iPhone or in Settings.
    func updateAccess() {
        if authorizationError != nil {
            authorizationError = canSaveWorkouts ? nil : healthAccessMessage
        }
        updateLocationAccess()
    }

    func updateLocationAccess() {
        locationDenied = [.denied, .restricted].contains(locationManager.authorizationStatus)
    }

    /// True once workouts can be saved. An unanswered request is asked again, and an answer given on
    /// iPhone gets up to `patience` to reach the Watch. Anything else ends in an alert that says how
    /// to allow access, so a start never fails silently.
    private func ensureWorkoutAccess(patience: Duration = .zero) async -> Bool {
        if canSaveWorkouts, locationManager.authorizationStatus != .notDetermined { return true }
        isCheckingAccess = true
        defer { isCheckingAccess = false }
        if workoutAccess == .notDetermined || locationManager.authorizationStatus == .notDetermined {
            // A request handed to iPhone may only return once it's answered there, so it isn't
            // awaited: waiting stops at an answer, when the request returns, or after 15 s.
            _ = authorizationRequestTask()
            let requestDeadline = ContinuousClock.now + .seconds(15)
            while authorizationRequest != nil, workoutAccess == .notDetermined, ContinuousClock.now < requestDeadline {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        let answerDeadline = ContinuousClock.now + patience
        while workoutAccess == .notDetermined, ContinuousClock.now < answerDeadline {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard canSaveWorkouts else {
            authorizationError = healthAccessMessage
            fail(healthAccessMessage, title: "Allow Health access")
            return false
        }
        authorizationError = nil
        return true
    }

    // MARK: Lifecycle

    /// Starts a run from the start list once Health access is there (see ``ensureWorkoutAccess(patience:)``).
    func start(_ goal: Goal) async {
        guard phase == .idle, session == nil, !isCheckingAccess else { return }
        guard await ensureWorkoutAccess() else { return }
        // iPhone may have started a run while access was being checked.
        guard phase == .idle, session == nil else { return }
        begin(goal)
    }

    /// The countdown, then the workout. Callers have checked Health access.
    private func begin(_ goal: Goal) {
        self.goal = goal
        splitUnit = UnitSystem(rawValue: UserDefaults.standard.string(forKey: StrideSettings.unitSystem) ?? "") ?? .metric
        do {
            try prepareSession()
        } catch {
            fail("Couldn't start the workout.")
            return
        }
        // Sensors warm up during the countdown, so heart rate and GPS are ready at zero.
        session?.prepare()
        startLocationUpdates()
        let session = self.session
        countdownTask = Task { [weak self] in
            for number in [3, 2, 1] {
                guard let self, !Task.isCancelled, self.session === session else { return }
                self.phase = .countdown(number)
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            await self?.beginWorkout()
        }
    }

    /// Only possible before the activity has started.
    func cancelCountdown() {
        guard case .countdown = phase, startDate == nil else { return }
        countdownTask?.cancel()
        session?.end()
        builder?.discardWorkout()
        reset()
    }

    func pause() {
        guard phase == .running, !isEnding else { return }
        session?.pause()
    }

    func resume() {
        guard phase == .paused, !isEnding else { return }
        session?.resume()
    }

    func end() {
        guard !isEnding, let session, phase == .running || phase == .paused else { return }
        isEnding = true
        WKInterfaceDevice.current().play(.stop)
        session.end()
    }

    /// Returns to the start list after the summary.
    func reset() {
        countdownTask?.cancel()
        mirrorTask?.cancel()
        mirrorTask = nil
        remirrorTask?.cancel()
        remirrorTask = nil
        sendFailures = 0
        sentCoordinateCount = 0
        routeEpoch = UUID()
        routeEpochBase = 0
        startedFromCompanion = false
        stopLocationUpdates()
        session = nil
        builder = nil
        routeBuilder = nil
        route = []
        segment = 0
        phase = .idle
        goal = Goal()
        startDate = nil
        heartRate = nil
        averageHeartRate = nil
        maxHeartRateSeen = nil
        distance = 0
        activeEnergy = 0
        currentSpeed = 0
        zoneSeconds = [:]
        summary = nil
        savedToHealth = false
        isEnding = false
        isFinishing = false
        lastHeartRateDate = nil
        lastSpeedFixDate = nil
        lastValidAltitude = nil
        completedSplits = 0
        goalReached = false
        clearJournal()
    }

    private func prepareSession() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        attach(session: session, builder: builder)
    }

    private func attach(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        // The builder's own route series is tied to the workout when it finishes, and survives recovery.
        routeBuilder = builder.seriesBuilder(for: .workoutRoute()) as? HKWorkoutRouteBuilder
    }

    private func beginWorkout() async {
        guard let session, let builder else { return }
        let start = Date.now
        startDate = start
        session.startActivity(with: start)
        do {
            try await builder.beginCollection(at: start)
        } catch {
            guard self.session === session else { return }
            session.end()
            builder.discardWorkout()
            reset()
            fail("Couldn't record this workout.")
            return
        }
        guard self.session === session else { return }
        WKInterfaceDevice.current().play(.start)
        startMirroring(session)
    }

    /// Called when iPhone asked to start a workout ("Start on Watch").
    func startFromCompanion() async {
        switch phase {
        case .running, .paused:
            // Already running: the iPhone lost the live view, so mirror again.
            if let session { startMirroring(session) }
        case .countdown:
            return
        case .ended, .idle:
            if phase == .ended { reset() }
            // A start from the list may be checking access: let it finish, then start here if it didn't.
            while isCheckingAccess {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard phase == .idle, session == nil else { return }
            // iPhone asked for access just before opening this app, and its answer takes a moment
            // to arrive.
            guard await ensureWorkoutAccess(patience: .seconds(10)) else { return }
            guard phase == .idle, session == nil else { return }
            begin(Goal())
            // phase only changes once the countdown task runs; a session means the start went through.
            startedFromCompanion = session != nil
        }
    }

    private func finish(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder, at end: Date) async {
        guard !isFinishing else { return }
        isFinishing = true
        isEnding = true
        countdownTask?.cancel()
        stopLocationUpdates()
        accumulateZoneTime(until: end)

        try? await builder.endCollection(at: end)
        let workout = try? await builder.finishWorkout()
        guard self.builder === builder else { return }

        let duration = builder.elapsedTime(at: end)
        let transfer = RunTransfer(
            startDate: startDate ?? end,
            duration: duration,
            distance: distance,
            calories: activeEnergy,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRateSeen,
            zoneSeconds: Dictionary(uniqueKeysWithValues: zoneSeconds.map { ($0.key.rawValue, $0.value) }),
            route: route,
            type: goal.type,
            workoutName: goal.name
        )
        savedToHealth = workout != nil
        summary = transfer
        phase = .ended
        mirrorTask?.cancel()
        mirrorTask = nil
        remirrorTask?.cancel()
        remirrorTask = nil
        clearJournal()
        // A workout that never collected anything isn't worth a Run on iPhone.
        if builder.startDate != nil, duration > 0 {
            WatchConnector.shared.send(transfer)
            // Complications count the run now, before iPhone sends back its own copy of the week.
            let unit = UnitSystem(rawValue: UserDefaults.standard.string(forKey: StrideSettings.unitSystem) ?? "") ?? .metric
            let run = WidgetSnapshot.RunSummary(date: transfer.startDate, distance: transfer.distance, duration: transfer.duration,
                                                title: transfer.workoutName ?? Run.timeOfDayTitle(for: transfer.startDate))
            WidgetStore.addLocalRun(run, unit: unit)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func fail(_ message: String, title: String = "Workout problem") {
        workoutErrorTitle = title
        workoutError = message
        WKInterfaceDevice.current().play(.failure)
    }

    // MARK: Recovery

    /// Called when watchOS relaunches the app during a workout after a crash or termination.
    func recoverActiveWorkout() async {
        guard phase == .idle,
              let session = try? await healthStore.recoverActiveWorkoutSession()
        else { return }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
        attach(session: session, builder: builder)
        restoreJournal()
        // The recovered route may be shorter than what iPhone already has: start a new epoch at its length.
        routeEpoch = UUID()
        routeEpochBase = route.count
        sentCoordinateCount = route.count
        startDate = builder.startDate ?? startDate
        splitUnit = UnitSystem(rawValue: UserDefaults.standard.string(forKey: StrideSettings.unitSystem) ?? "") ?? .metric
        completedSplits = Int(distance / splitUnit.metersPerUnit)
        switch session.state {
        case .paused:
            phase = .paused
        case .ended, .stopped:
            await finish(session: session, builder: builder, at: session.endDate ?? .now)
            return
        default:
            phase = .running
            lastHeartRateDate = .now
        }
        startLocationUpdates()
        startMirroring(session)
    }

    /// Route, zones and goal on disk, so a recovered workout keeps what it had collected.
    private struct Journal: Codable {
        var goal: Goal
        var startDate: Date?
        var route: [RoutePoint]
        var zoneSeconds: [Int: TimeInterval]
        var segment: Int
    }

    private var journalURL: URL {
        URL.documentsDirectory.appending(path: "active-workout.json")
    }

    private func writeJournalIfNeeded() {
        guard Date.now.timeIntervalSince(lastJournalWrite) >= 15 else { return }
        lastJournalWrite = .now
        let journal = Journal(goal: goal, startDate: startDate, route: route,
                              zoneSeconds: Dictionary(uniqueKeysWithValues: zoneSeconds.map { ($0.key.rawValue, $0.value) }),
                              segment: segment)
        try? JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }

    private func restoreJournal() {
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(Journal.self, from: data) else { return }
        goal = journal.goal
        startDate = journal.startDate
        route = journal.route
        segment = journal.segment + 1
        lastValidAltitude = journal.route.last?.altitude
        zoneSeconds = Dictionary(uniqueKeysWithValues: journal.zoneSeconds.compactMap { key, value in
            HeartRateZone(rawValue: key).map { ($0, value) }
        })
    }

    private func clearJournal() {
        try? FileManager.default.removeItem(at: journalURL)
        lastJournalWrite = .distantPast
    }

    // MARK: Live data

    fileprivate func handleState(_ state: HKWorkoutSessionState, of session: HKWorkoutSession, date: Date) {
        guard session === self.session else { return }
        switch state {
        case .running:
            guard phase != .idle, phase != .ended else { return }
            if phase == .paused { segment += 1 }
            lastHeartRateDate = date
            phase = .running
            sendSnapshot()
        case .paused:
            guard phase == .running else { return }
            accumulateZoneTime(until: date)
            lastHeartRateDate = nil
            lastSpeedFixDate = nil
            currentSpeed = 0
            phase = .paused
            sendSnapshot()
        case .ended, .stopped:
            guard let builder else { return }
            isEnding = true
            Task { await finish(session: session, builder: builder, at: date) }
        default:
            break
        }
    }

    fileprivate func handleFailure(of session: HKWorkoutSession) {
        guard session === self.session else { return }
        if case .countdown = phase {
            countdownTask?.cancel()
            builder?.discardWorkout()
            reset()
            fail("Couldn't start the workout.")
        } else {
            fail("The workout stopped unexpectedly.")
        }
    }

    fileprivate func apply(from builder: HKLiveWorkoutBuilder, heartRate: Double?, average: Double?,
                           maximum: Double?, distance: Double?, energy: Double?) {
        guard builder === self.builder, phase == .running || phase == .paused else { return }
        if let heartRate {
            // Time since the last reading counts toward the zone of that reading.
            accumulateZoneTime(until: .now)
            self.heartRate = heartRate
        }
        if let average { averageHeartRate = average }
        if let maximum { maxHeartRateSeen = maximum }
        if let energy { activeEnergy = energy }
        if let distance {
            self.distance = distance
            let done = Int(distance / splitUnit.metersPerUnit)
            if done > completedSplits {
                completedSplits = done
                WKInterfaceDevice.current().play(.notification)
            }
        }
        if let progress = goalProgress(), progress >= 1, !goalReached {
            goalReached = true
            WKInterfaceDevice.current().play(.success)
        }
        writeJournalIfNeeded()
    }

    private func accumulateZoneTime(until date: Date) {
        defer { lastHeartRateDate = phase == .running ? date : nil }
        guard phase == .running, let last = lastHeartRateDate, let zone = currentZone else { return }
        zoneSeconds[zone, default: 0] += max(date.timeIntervalSince(last), 0)
    }

    // MARK: Mirroring to iPhone

    /// Shows the workout live on iPhone. Without a reachable iPhone this fails quietly;
    /// the finished run still reaches iPhone through WatchConnector.
    private func startMirroring(_ session: HKWorkoutSession) {
        Task { [weak self] in
            try? await session.startMirroringToCompanionDevice()
            guard let self, self.session === session else { return }
            self.mirrorTask?.cancel()
            self.mirrorTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.sendSnapshot()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func sendSnapshot() {
        guard let session, phase == .running || phase == .paused else { return }
        // At most 100 coordinates per snapshot keeps well under HealthKit's 100 KB / 10 s limit.
        let start = min(sentCoordinateCount, route.count)
        let end = min(start + 100, route.count)
        let batch = route[start..<end].map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let snapshot = MirrorSnapshot(
            elapsed: elapsedTime(),
            isPaused: phase == .paused,
            distance: distance,
            heartRate: heartRate,
            averageHeartRate: averageHeartRate,
            calories: activeEnergy,
            currentSpeed: currentPace(unit: .metric).map { 1_000 / $0 },
            zoneSeconds: Dictionary(uniqueKeysWithValues: zoneSeconds.map { ($0.key.rawValue, $0.value) }),
            coordinates: batch,
            firstCoordinateIndex: start,
            routeEpoch: routeEpoch,
            routeEpochBase: routeEpochBase,
            goalName: goal.name,
            goalDistance: goal.distance,
            goalDuration: goal.duration
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        Task { [weak self] in
            do {
                try await session.sendToRemoteWorkoutSession(data: data)
                guard let self, self.session === session else { return }
                self.sentCoordinateCount = max(self.sentCoordinateCount, end)
                self.sendFailures = 0
            } catch {
                // Not mirroring right now; the next snapshot retries from the same coordinate.
                guard let self, self.session === session else { return }
                self.sendFailures += 1
                if self.sendFailures >= 5 { self.scheduleRemirror(for: session) }
            }
        }
    }

    fileprivate func handleRemoteData(_ data: [Data], from session: HKWorkoutSession) {
        guard session === self.session else { return }
        let decoder = JSONDecoder()
        for item in data {
            if let request = try? decoder.decode(MirrorRequest.self, from: item) {
                sentCoordinateCount = min(max(request.resendFrom, 0), route.count)
            } else if let command = try? decoder.decode(MirrorCommand.self, from: item) {
                applyCompanionGoal(command.goal)
            }
        }
    }

    /// The goal picked on iPhone for a run started with "Start on Watch". Only replaces a free run
    /// the Watch started for that request, never a goal the runner picked on the Watch.
    private func applyCompanionGoal(_ companionGoal: MirrorGoal) {
        guard startedFromCompanion, goal.type == .free else { return }
        switch phase {
        case .countdown, .running, .paused: break
        default: return
        }
        goal = Goal(type: companionGoal.type, distance: companionGoal.distance,
                    duration: companionGoal.duration, name: companionGoal.name)
        goalReached = false
        lastJournalWrite = .distantPast
        sendSnapshot()
    }

    /// The mirrored session dropped (iPhone out of range, or its app was closed): mirror again,
    /// backing off, until it works or the run ends.
    fileprivate func scheduleRemirror(for session: HKWorkoutSession) {
        guard session === self.session, phase == .running || phase == .paused, !isEnding, remirrorTask == nil else { return }
        remirrorTask = Task { [weak self] in
            let delays: [Double] = [5, 15, 30, 60]
            var attempt = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delays[min(attempt, delays.count - 1)]))
                attempt += 1
                guard let self, self.session === session, self.phase == .running || self.phase == .paused else { return }
                do {
                    try await session.startMirroringToCompanionDevice()
                    self.sendFailures = 0
                    self.remirrorTask = nil
                    return
                } catch {
                    continue
                }
            }
        }
    }

    // MARK: Location

    private func startLocationUpdates() {
        guard locationTask == nil else { return }
        serviceSession = CLServiceSession(authorization: .whenInUse)
        locationTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    if update.stationary { self.currentSpeed = 0 }
                    if update.locationUnavailable { self.lastSpeedFixDate = nil }
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        self.locationDenied = true
                    }
                    if let location = update.location {
                        await self.handle(location)
                    }
                }
            } catch {}
        }
    }

    private func stopLocationUpdates() {
        locationTask?.cancel()
        locationTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    private func handle(_ location: CLLocation) async {
        guard phase == .running,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30,
              location.timestamp.timeIntervalSinceNow > -10
        else { return }

        let previous = route.last.flatMap { $0.segment == segment ? $0 : nil }
        if let previous {
            // A GPS jump: skip it for the route and for Health.
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0, location.distance(from: previous.location) / seconds < 12 else { return }
        }

        var speed = location.speed
        if speed < 0, let previous {
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            speed = location.distance(from: previous.location) / seconds
        }
        if speed >= 0, speed < 12 {
            currentSpeed = currentSpeed == 0 ? speed : currentSpeed * 0.7 + speed * 0.3
            lastSpeedFixDate = location.timestamp
        }

        route.append(RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: sanitizedAltitude(for: location),
            timestamp: location.timestamp,
            segment: segment,
            heartRate: heartRate
        ))
        try? await routeBuilder?.insertRouteData([location])
    }

    /// Only altitudes with a vertical accuracy of 20 m or better are stored; others repeat the last good
    /// value. Points recorded before the first good altitude are back-filled with it.
    private func sanitizedAltitude(for location: CLLocation) -> Double {
        guard location.verticalAccuracy >= 0, location.verticalAccuracy <= 20 else {
            return lastValidAltitude ?? route.last?.altitude ?? location.altitude
        }
        if lastValidAltitude == nil {
            for index in route.indices { route[index].altitude = location.altitude }
        }
        lastValidAltitude = location.altitude
        return location.altitude
    }
}

// MARK: - HealthKit delegates

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in self.handleState(toState, of: workoutSession, date: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.handleFailure(of: workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.handleRemoteData(data, from: workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.scheduleRemirror(for: workoutSession) }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var heartRate: Double?, average: Double?, maximum: Double?, distance: Double?, energy: Double?
        if collectedTypes.contains(HKQuantityType(.heartRate)), let stats = workoutBuilder.statistics(for: HKQuantityType(.heartRate)) {
            heartRate = stats.mostRecentQuantity()?.doubleValue(for: bpm)
            average = stats.averageQuantity()?.doubleValue(for: bpm)
            maximum = stats.maximumQuantity()?.doubleValue(for: bpm)
        }
        if collectedTypes.contains(HKQuantityType(.distanceWalkingRunning)) {
            distance = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
        }
        if collectedTypes.contains(HKQuantityType(.activeEnergyBurned)) {
            energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        Task { @MainActor in
            self.apply(from: workoutBuilder, heartRate: heartRate, average: average, maximum: maximum,
                       distance: distance, energy: energy)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

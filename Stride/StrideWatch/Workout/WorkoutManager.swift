import CoreLocation
import HealthKit
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

    // MARK: Authorization

    private var canSaveWorkouts: Bool {
        healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    /// Asks for Health and location access from the start list, so no prompt appears over a countdown.
    func requestAuthorization() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKObjectType.workoutType(),
        ]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
        // Denying doesn't throw, so check the result instead of the call.
        authorizationError = canSaveWorkouts ? nil : "Allow Stride to save workouts in Settings › Health › Data Access."

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        updateLocationAccess()
    }

    func updateLocationAccess() {
        locationDenied = [.denied, .restricted].contains(locationManager.authorizationStatus)
    }

    // MARK: Lifecycle

    func start(_ goal: Goal) {
        guard phase == .idle else { return }
        guard canSaveWorkouts else {
            authorizationError = "Allow Stride to save workouts in Settings › Health › Data Access."
            return
        }
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
        clearJournal()
        // A workout that never collected anything isn't worth a Run on iPhone.
        if builder.startDate != nil, duration > 0 {
            WatchConnector.shared.send(transfer)
        }
    }

    private func fail(_ message: String) {
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
        case .paused:
            guard phase == .running else { return }
            accumulateZoneTime(until: date)
            lastHeartRateDate = nil
            lastSpeedFixDate = nil
            currentSpeed = 0
            phase = .paused
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

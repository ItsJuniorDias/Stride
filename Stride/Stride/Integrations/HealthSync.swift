import Foundation
import CoreLocation
import HealthKit
import SwiftData
import StrideKit

/// Saves runs recorded on iPhone and added by hand to Apple Health, with their route, and removes
/// them when they're deleted in Stride. Apple Watch saves its own runs while recording.
@MainActor
final class HealthSync {
    static let shared = HealthSync()

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var isEnabled: Bool { StrideSettings.bool(StrideSettings.healthSave, default: false) }

    nonisolated private static var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    nonisolated private static var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), Self.distanceType, Self.energyType]
    }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.bodyMass), HKCharacteristicType(.dateOfBirth)]
    }

    /// Whether Stride may save workouts; false when the runner said no in Health.
    var canSave: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    var wasDenied: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied
    }

    /// Shows Health's permission sheet the first time; later calls return right away.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return canSave
        } catch {
            return false
        }
    }

    /// Saves every iPhone and manual run that isn't in Health yet, from the moment saving was turned
    /// on (or all of them with `includingEarlier`). Returns how many were saved. Calls run one after
    /// another, so a request made while another is running still gets its turn.
    @discardableResult
    func exportPending(in context: ModelContext, includingEarlier: Bool = false) async -> Int {
        let previous = exportTask
        let task = Task {
            await previous?.value
            return await runExport(in: context, includingEarlier: includingEarlier)
        }
        exportTask = task
        return await task.value
    }

    private var exportTask: Task<Int, Never>?

    private func runExport(in context: ModelContext, includingEarlier: Bool) async -> Int {
        guard isEnabled, isAvailable, canSave else { return 0 }
        let since = includingEarlier ? .distantPast
            : (UserDefaults.standard.object(forKey: StrideSettings.healthSaveSince) as? Date ?? .distantPast)
        let watch = RunSource.watch.rawValue
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate {
            $0.healthWorkoutID == nil && $0.sourceRaw != watch && $0.startDate >= since
        })
        guard let runs = try? context.fetch(descriptor) else { return 0 }
        var saved = 0
        for run in runs {
            // Saving turned off (or permission taken away) partway through: stop.
            guard isEnabled, canSave else { break }
            if await save(run, in: context) { saved += 1 }
        }
        return saved
    }

    /// Saves one run (any date) and records its workout id. False if it wasn't saved. Only called
    /// from tasks in the export queue.
    private func save(_ run: Run, in context: ModelContext) async -> Bool {
        guard isEnabled, isAvailable, canSave else { return false }
        // Deleted while an earlier run was being saved: its data can't be read anymore.
        guard !run.isDeleted, run.modelContext != nil, run.healthWorkoutID == nil,
              run.duration > 0, run.distance > 0, let input = WorkoutInput(run, samples: authorizedSampleTypes)
        else { return false }
        guard let id = try? await Self.write(input, to: store) else { return false }
        guard !run.isDeleted, run.modelContext != nil else {
            _ = await Self.deleteWorkout(id, from: store)
            return false
        }
        // Edited while it was being written: write it again with the new numbers.
        if run.startDate != input.start || run.duration != input.duration || run.distance != input.distance {
            _ = await Self.deleteWorkout(id, from: store)
            return await save(run, in: context)
        }
        run.healthWorkoutID = id
        // Recorded right away, so a crash later in the pass can't lead to saving it twice.
        try? context.save()
        return true
    }

    /// Replaces a run's workout after it was edited (a Health workout can't be changed in place).
    /// Runs as one step of the export queue, so no export can pick up the old workout meanwhile.
    /// Nothing changes when saving is off or not allowed: the runner's workout stays as it is.
    func replace(_ run: Run, in context: ModelContext) async {
        let previous = exportTask
        let task = Task { () -> Int in
            await previous?.value
            guard isEnabled, isAvailable, canSave, !run.isDeleted, run.modelContext != nil,
                  let old = run.healthWorkoutID
            else { return 0 }
            // The id is only forgotten once the old workout is really gone.
            guard await Self.deleteWorkout(old, from: store) else { return 0 }
            run.healthWorkoutID = nil
            try? context.save()
            // Back in Health with the new numbers, whatever its date.
            return await save(run, in: context) ? 1 : 0
        }
        exportTask = task
        _ = await task.value
    }

    /// The sample types the runner allowed; a workout is still saved without the others.
    private var authorizedSampleTypes: Set<String> {
        var types: Set<String> = []
        if store.authorizationStatus(for: Self.distanceType) == .sharingAuthorized { types.insert(Self.distanceType.identifier) }
        if store.authorizationStatus(for: Self.energyType) == .sharingAuthorized { types.insert(Self.energyType.identifier) }
        if store.authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingAuthorized { types.insert(HKSeriesType.workoutRoute().identifier) }
        return types
    }

    /// Removes a run's workout from Health (the workout, its route and its samples).
    func delete(workoutID: UUID?) {
        guard let workoutID, isAvailable else { return }
        let store = store
        Task { _ = await Self.deleteWorkout(workoutID, from: store) }
    }

    /// The latest weight and the runner's age, to fill in calories and heart-rate zones.
    func readBody() async -> (weightKg: Double?, age: Int?) {
        guard isAvailable else { return (nil, nil) }
        _ = try? await store.requestAuthorization(toShare: [], read: readTypes)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let weight = (try? await descriptor.result(for: store))?.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
        var age: Int?
        // Health returns Gregorian components, whatever calendar the phone uses.
        let gregorian = Calendar(identifier: .gregorian)
        if let birth = try? store.dateOfBirthComponents(), let date = gregorian.date(from: birth) {
            age = gregorian.dateComponents([.year], from: date, to: .now).year
        }
        return (weight, age)
    }

    // MARK: Writing

    /// Everything a workout needs, copied off the model so it can be written away from the main actor.
    struct WorkoutInput: Sendable {
        var runID: UUID
        var start: Date
        var duration: TimeInterval
        var distance: Double
        var calories: Double
        var elevationGain: Double
        var isManual: Bool
        var isIndoor: Bool
        /// Decoded off the main actor, when the workout is written.
        var routeData: Data?
        /// Identifiers of the sample types the runner allowed.
        var samples: Set<String>

        init?(_ run: Run, samples: Set<String>) {
            guard run.duration > 0 else { return nil }
            runID = run.id
            start = run.startDate
            duration = run.duration
            distance = run.distance
            calories = run.calories
            elevationGain = run.elevationGain
            isManual = run.isManual
            isIndoor = run.surface == .treadmill
            routeData = run.isManual ? nil : run.routeData
            self.samples = samples
        }
    }

    @concurrent
    private static func write(_ input: WorkoutInput, to store: HKHealthStore) async throws -> UUID {
        // Saved already (the app stopped before it could note the id): use that workout.
        if let existing = await workout(for: input.runID, in: store) { return existing }

        let route = input.routeData.flatMap { try? JSONDecoder().decode([RoutePoint].self, from: $0) } ?? []
        let timeline = WorkoutTimeline(start: input.start, duration: input.duration, route: route)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = input.isIndoor ? .indoor : (input.isManual ? .unknown : .outdoor)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: timeline.start)

            var samples: [HKSample] = []
            if input.samples.contains(distanceType.identifier) {
                samples.append(HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: input.distance),
                                                start: timeline.start, end: timeline.end))
            }
            if input.calories > 0, input.samples.contains(energyType.identifier) {
                samples.append(HKQuantitySample(type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: input.calories),
                                                start: timeline.start, end: timeline.end))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }

            let events = timeline.pauses.flatMap { pause in
                [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil),
                 HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil)]
            }
            if !events.isEmpty { try await builder.addWorkoutEvents(events) }

            var metadata: [String: Any] = [
                HKMetadataKeyIndoorWorkout: input.isIndoor,
                HKMetadataKeyExternalUUID: input.runID.uuidString,
            ]
            if input.isManual { metadata[HKMetadataKeyWasUserEntered] = true }
            if input.elevationGain > 0 {
                metadata[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: input.elevationGain)
            }
            try await builder.addMetadata(metadata)
            try await builder.endCollection(at: timeline.end)
            guard let workout = try await builder.finishWorkout() else { throw CocoaError(.coderInvalidValue) }

            if route.count > 1, input.samples.contains(HKSeriesType.workoutRoute().identifier) {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                try? await routeBuilder.insertRouteData(route.map(\.location))
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
            return workout.uuid
        } catch {
            // Nothing half-saved: the samples added so far go too, so a retry doesn't count them twice.
            builder.discardWorkout()
            throw error
        }
    }

    /// The workout already saved for a run, found by the run id in its metadata.
    @concurrent
    private static func workout(for runID: UUID, in store: HKHealthStore) async -> UUID? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                              allowedValues: [runID.uuidString]))],
            sortDescriptors: [],
            limit: 1
        )
        return (try? await descriptor.result(for: store))?.first?.uuid
    }

    /// Deletes a workout with its samples and route. True when it's gone (or was already), false
    /// when Health refused.
    @concurrent
    private static func deleteWorkout(_ id: UUID, from store: HKHealthStore) async -> Bool {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: []
        )
        guard let workouts = try? await descriptor.result(for: store) else { return false }
        guard !workouts.isEmpty else { return true }
        for workout in workouts {
            let associated = HKQuery.predicateForObjects(from: workout)
            _ = try? await store.deleteObjects(of: distanceType, predicate: associated)
            _ = try? await store.deleteObjects(of: energyType, predicate: associated)
            _ = try? await store.deleteObjects(of: HKSeriesType.workoutRoute(), predicate: associated)
        }
        do {
            try await store.delete(workouts)
            return true
        } catch {
            return false
        }
    }
}

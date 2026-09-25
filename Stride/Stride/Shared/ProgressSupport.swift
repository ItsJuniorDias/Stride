import Foundation
import SwiftData
import StrideKit

enum RunMaintenance {
    /// Best efforts for runs saved before records existed, or with an older algorithm. Routes are
    /// decoded and analyzed off the main actor, one run at a time.
    static func backfillBestEfforts(in context: ModelContext) async {
        let version = BestEfforts.version
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.effortsVersion < version })
        guard let runs = try? context.fetch(descriptor), !runs.isEmpty else { return }
        var results: [(run: Run, distance: Double, duration: TimeInterval, efforts: [EffortDistance: TimeInterval])] = []

        // Applied and saved in batches: screens showing records redraw a handful of times rather than
        // once per run, and finished work survives the app being closed halfway.
        func apply() {
            for result in results {
                let run = result.run
                // The run may have been deleted or edited while its route was analyzed.
                guard !run.isDeleted, run.modelContext != nil, run.distance == result.distance, run.duration == result.duration else { continue }
                run.bestEfforts = result.efforts
                run.effortsVersion = version
            }
            results.removeAll()
            try? context.save()
        }

        for run in runs {
            guard !Task.isCancelled else { break }
            // Deleted while an earlier run was analyzed: its data can't be read anymore.
            guard !run.isDeleted, run.modelContext != nil else { continue }
            let distance = run.distance, duration = run.duration
            let efforts = await BestEfforts.compute(routeData: run.routeData, distance: distance, duration: duration, typed: run.isManual)
            results.append((run, distance, duration, efforts))
            if results.count == 25 { apply() }
        }
        apply()
    }
}

/// The shoe new runs use, kept in settings so the Run tab, Apple Watch imports and manual entries agree.
enum ShoeDefaults {
    static var id: UUID? {
        UUID(uuidString: UserDefaults.standard.string(forKey: StrideSettings.defaultShoeID) ?? "")
    }

    static func isDefault(_ shoe: Shoe) -> Bool {
        id == shoe.id
    }

    static func set(_ shoe: Shoe?) {
        UserDefaults.standard.set(shoe?.id.uuidString ?? "", forKey: StrideSettings.defaultShoeID)
    }

    /// The default shoe, if it still exists and isn't retired.
    static func shoe(in context: ModelContext) -> Shoe? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Shoe>(predicate: #Predicate { $0.id == id && !$0.isRetired })
        return try? context.fetch(descriptor).first
    }

    /// Retires or restores a shoe. A retired shoe stops being the default.
    static func setRetired(_ shoe: Shoe, _ retired: Bool) {
        shoe.isRetired = retired
        if retired, isDefault(shoe) { set(nil) }
    }
}

enum RecordBook {
    /// The records `run` set against every earlier run.
    static func achievements(for run: Run, in context: ModelContext) -> [RecordAchievement] {
        let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        let entry = run.recordEntry
        return PersonalRecords.achievements(of: entry, previous: runs.filter { $0.id != entry.id }.map(\.recordEntry))
    }

    /// "0:42 faster", "+1.20 km", "+4:10", "+35 m": how far a record moved.
    static func improvement(_ achievement: RecordAchievement, unit: UnitSystem) -> String? {
        guard let previous = achievement.previous else { return nil }
        let delta = abs(achievement.value - previous)
        switch achievement.kind {
        case .effort: return "\(RunFormat.duration(delta)) faster than \(RunFormat.duration(previous))"
        case .longestDuration: return "\(RunFormat.duration(delta)) longer than \(RunFormat.duration(previous))"
        case .longestDistance:
            return "\(RunFormat.distance(delta, unit: unit)) \(unit.distanceSymbol) farther than \(RunFormat.distance(previous, unit: unit)) \(unit.distanceSymbol)"
        case .mostElevation:
            return "\(Int(unit.elevation(fromMeters: delta).rounded())) \(unit.elevationSymbol) more than \(Int(unit.elevation(fromMeters: previous).rounded())) \(unit.elevationSymbol)"
        }
    }

    /// "Fastest 5K", or "First 10K" the first time.
    static func title(_ achievement: RecordAchievement) -> String {
        if achievement.previous == nil, case .effort(let distance) = achievement.kind {
            return "First \(distance.title)"
        }
        return achievement.kind.title
    }
}

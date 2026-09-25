import Foundation
import SwiftData
import StrideKit

/// Finding and removing a run's heart rate, which lives apart from the run (see ``RunVitals``).
@MainActor
enum Vitals {
    static func of(_ runID: UUID, in context: ModelContext) -> RunVitals? {
        var descriptor = FetchDescriptor<RunVitals>(predicate: #Predicate { $0.runID == runID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Heart rate whose run is gone: deleted on another device, the deletion arriving through iCloud.
    static func removeOrphans(in context: ModelContext) {
        guard let vitals = try? context.fetch(FetchDescriptor<RunVitals>()), !vitals.isEmpty else { return }
        var runs = FetchDescriptor<Run>()
        runs.propertiesToFetch = [\.id]
        let ids = Set(((try? context.fetch(runs)) ?? []).map(\.id))
        let orphans = vitals.filter { !ids.contains($0.runID) }
        guard !orphans.isEmpty else { return }
        orphans.forEach(context.delete)
        try? context.save()
    }

    /// Deletes a run and its heart rate.
    static func delete(_ run: Run, in context: ModelContext) {
        if let vitals = of(run.id, in: context) { context.delete(vitals) }
        context.delete(run)
    }
}

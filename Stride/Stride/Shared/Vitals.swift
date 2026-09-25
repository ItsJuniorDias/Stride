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

    /// Deletes a run and its heart rate.
    static func delete(_ run: Run, in context: ModelContext) {
        if let vitals = of(run.id, in: context) { context.delete(vitals) }
        context.delete(run)
    }
}

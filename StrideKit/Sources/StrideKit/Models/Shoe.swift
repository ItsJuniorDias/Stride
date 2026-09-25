import Foundation
import SwiftData

@Model
public final class Shoe {
    public var id: UUID = UUID()
    public var name: String = ""
    public var brand: String = ""
    /// Meters already on the shoe before it was added to Stride.
    public var initialDistance: Double = 0
    /// Meters after which the shoe should be replaced.
    public var maxDistance: Double = 800_000
    public var isRetired: Bool = false
    public var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Run.shoe)
    public var runs: [Run]? = []

    public init(name: String, brand: String = "", initialDistance: Double = 0, maxDistance: Double = 800_000) {
        self.name = name
        self.brand = brand
        self.initialDistance = initialDistance
        self.maxDistance = maxDistance
    }

    public var totalDistance: Double {
        initialDistance + (runs ?? []).reduce(0) { $0 + $1.distance }
    }

    /// 0…1+, how much of the shoe's life is used.
    public var wear: Double {
        maxDistance > 0 ? totalDistance / maxDistance : 0
    }
}

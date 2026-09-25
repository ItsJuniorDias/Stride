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
    /// Index into the shoe colors of the design system.
    public var colorIndex: Int = 0
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

    /// From 90% of its life on, a shoe is due for replacing.
    public var isWornOut: Bool { wear >= 0.9 }

    /// Meters left before the replacement distance; negative once past it.
    public var remainingDistance: Double { maxDistance - totalDistance }

    /// The shoe's name, or its brand when the name is empty.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (brand.isEmpty ? "Shoe" : brand) : trimmed
    }
}

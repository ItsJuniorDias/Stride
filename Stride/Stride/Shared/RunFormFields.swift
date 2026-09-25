import SwiftUI
import StrideKit
import StrideUI

/// Hours, minutes and seconds wheels bound to a duration in seconds.
struct DurationPicker: View {
    @Binding var seconds: TimeInterval

    var body: some View {
        HStack(spacing: 0) {
            wheel(0..<24, "h", value: Int(seconds) / 3_600) { set(hours: $0) }
            wheel(0..<60, "min", value: Int(seconds) % 3_600 / 60) { set(minutes: $0) }
            wheel(0..<60, "s", value: Int(seconds) % 60) { set(seconds: $0) }
        }
        .frame(height: 130)
    }

    private func wheel(_ range: Range<Int>, _ label: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            Picker(label, selection: Binding(get: { value }, set: set)) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func set(hours: Int? = nil, minutes: Int? = nil, seconds newSeconds: Int? = nil) {
        let total = Int(seconds)
        let h = hours ?? total / 3_600
        let m = minutes ?? total % 3_600 / 60
        let s = newSeconds ?? total % 60
        seconds = TimeInterval(h * 3_600 + m * 60 + s)
    }
}

/// A distance typed in the runner's unit, stored in meters.
struct DistanceField: View {
    var label = "Distance"
    @Binding var meters: Double
    let unit: UnitSystem

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: Space.x1) {
                // Optional, so clearing the field sets 0 (and disables Save) instead of keeping the old value.
                TextField("0", value: Binding<Double?>(
                    get: { meters > 0 ? meters / unit.metersPerUnit : nil },
                    set: { meters = max($0 ?? 0, 0) * unit.metersPerUnit }
                ), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit.distanceSymbol).foregroundStyle(.inkMuted)
            }
        }
    }
}

/// A shoe choice limited to active shoes, plus the run's current shoe even if it's retired.
struct ShoePicker: View {
    let shoes: [Shoe]
    @Binding var selection: Shoe?
    /// The shoe saved on the run, kept in the list while picking another.
    var current: Shoe?

    var body: some View {
        Picker("Shoe", selection: $selection) {
            Text("None").tag(Shoe?.none)
            ForEach(shoes.filter { !$0.isRetired || $0.id == current?.id || $0.id == selection?.id }) { shoe in
                Text(shoe.name).tag(Shoe?.some(shoe))
            }
        }
    }
}

/// Pace readout for a manual run, with a warning when it can't be right.
struct PaceCheck: View {
    let meters: Double
    let seconds: TimeInterval
    let unit: UnitSystem

    /// Faster than 2'00" per km isn't a running pace.
    static func isPlausible(meters: Double, seconds: TimeInterval) -> Bool {
        guard meters > 0, seconds > 0 else { return false }
        return seconds / (meters / 1_000) >= 120
    }

    var body: some View {
        if meters > 0, seconds > 0 {
            let pace = RunFormat.paceSeconds(distance: meters, duration: seconds, unit: unit)
            if Self.isPlausible(meters: meters, seconds: seconds) {
                Text("Pace \(RunFormat.pace(pace)) \(unit.paceSymbol)")
            } else {
                Text("That's faster than any runner. Check the distance and time.")
                    .foregroundStyle(.warning)
            }
        }
    }
}

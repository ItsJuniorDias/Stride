import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Name and shoe for any run; date, distance and time too for manual runs (GPS runs keep what was recorded).
struct EditRunView: View {
    @Bindable var run: Run
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weightKg) private var weightKg = 70.0

    @State private var name = ""
    @State private var shoe: Shoe?
    @State private var date = Date.now
    @State private var meters: Double = 0
    @State private var seconds: TimeInterval = 0

    private var canSave: Bool {
        !run.isManual || PaceCheck.isPlausible(meters: meters, seconds: seconds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(Run.timeOfDayTitle(for: date)))
                } footer: {
                    Text("Leave empty to name it by the time of day.")
                }

                if run.isManual {
                    Section {
                        DatePicker("Date", selection: $date, in: ...Date.now)
                        DistanceField(meters: $meters, unit: unit)
                        DurationPicker(seconds: $seconds)
                    } header: {
                        Text("Distance and time")
                    } footer: {
                        PaceCheck(meters: meters, seconds: seconds, unit: unit)
                    }
                }

                Section("Gear") {
                    ShoePicker(shoes: shoes, selection: $shoe, current: run.shoe)
                }
            }
            .navigationTitle("Edit run")
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear {
                name = run.workoutName ?? ""
                shoe = run.shoe
                date = run.startDate
                meters = run.distance
                seconds = run.duration
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        run.workoutName = trimmed.isEmpty ? nil : trimmed
        run.shoe = shoe
        if run.isManual {
            // Calories follow the distance, keeping the weight the run was logged with.
            if meters != run.distance {
                run.calories = run.distance > 0
                    ? run.calories * meters / run.distance
                    : Run.estimatedCalories(distance: meters, weightKg: weightKg)
            }
            run.startDate = date
            run.distance = meters
            run.duration = seconds
        }
        try? context.save()
        dismiss()
    }
}

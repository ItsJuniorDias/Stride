import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Adds a run recorded without GPS: a treadmill session, or a run tracked elsewhere.
struct ManualRunView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weightKg) private var weightKg = 70.0

    /// Started half an hour ago, so a run logged right after it ends doesn't end in the future.
    @State private var date = Date.now.addingTimeInterval(-1_800)
    @State private var meters: Double = 5_000
    @State private var seconds: TimeInterval = 1_800
    @State private var name = ""
    @State private var surface: Surface? = .treadmill
    @State private var feeling: Feeling?
    @State private var shoe: Shoe?
    @State private var notes = ""

    private var canSave: Bool { PaceCheck.isPlausible(meters: meters, seconds: seconds) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(surface == .treadmill ? "Treadmill Run" : Run.timeOfDayTitle(for: date)))
                    DatePicker("Date", selection: $date, in: ...Date.now)
                }

                Section {
                    DistanceField(meters: $meters, unit: unit)
                    DurationPicker(seconds: $seconds)
                } header: {
                    Text("Distance and time")
                } footer: {
                    PaceCheck(meters: meters, seconds: seconds, unit: unit)
                }

                Section("How it went") {
                    Picker("Surface", selection: $surface) {
                        Text("None").tag(Surface?.none)
                        ForEach(Surface.allCases) { Text($0.title).tag(Surface?.some($0)) }
                    }
                    Picker("Feeling", selection: $feeling) {
                        Text("None").tag(Feeling?.none)
                        ForEach(Feeling.allCases) { Text("\($0.emoji) \($0.title)").tag(Feeling?.some($0)) }
                    }
                    ShoePicker(shoes: shoes, selection: $shoe)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .onAppear {
                if shoe == nil { shoe = shoes.first { ShoeDefaults.isDefault($0) && !$0.isRetired } }
            }
            .navigationTitle("Add run")
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
        }
    }

    private func save() {
        let run = Run(startDate: date, duration: seconds, distance: meters,
                      calories: Run.estimatedCalories(distance: meters, weightKg: weightKg),
                      type: .free, isManual: true)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        run.workoutName = trimmed.isEmpty ? (surface == .treadmill ? "Treadmill Run" : nil) : trimmed
        run.surface = surface
        run.feeling = feeling
        run.shoe = shoe
        run.notes = notes
        run.updateBestEfforts(route: [])
        context.insert(run)
        try? context.save()
        dismiss()
    }
}

#Preview {
    ManualRunView()
        .modelContainer(for: [Run.self, Shoe.self, Challenge.self], inMemory: true)
}

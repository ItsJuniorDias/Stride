import SwiftUI
import SwiftData
import StrideKit
import StrideUI

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @State private var confirmingDeleteAll = false
    @AppStorage(StrideSettings.userName) private var userName = ""
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weeklyGoal) private var weeklyGoal = 20.0
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    @AppStorage(StrideSettings.weightKg) private var weightKg = 70.0
    @AppStorage(StrideSettings.maxHeartRate) private var maxHeartRate = HeartRateZone.defaultMaxHeartRate

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("Your name", text: $userName)
                            .textContentType(.givenName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Goals") {
                    Stepper(value: $weeklyGoal, in: 5...300, step: 5) {
                        LabeledContent("Weekly distance", value: "\(Int(weeklyGoal)) \(unit.distanceSymbol)")
                    }
                }

                Section("Running") {
                    Picker("Units", selection: $unit) {
                        Text("Kilometers").tag(UnitSystem.metric)
                        Text("Miles").tag(UnitSystem.imperial)
                    }
                    Toggle("Auto-pause", isOn: $autoPause)
                        .tint(.track)
                }

                Section {
                    Stepper(value: $weightKg, in: 30...200) {
                        LabeledContent("Weight", value: "\(Int(weightKg)) kg")
                    }
                    Stepper(value: $maxHeartRate, in: 140...220) {
                        LabeledContent("Max heart rate", value: "\(Int(maxHeartRate)) bpm")
                    }
                } footer: {
                    Text("Weight is used to estimate calories. Max heart rate sets your five heart-rate zones on iPhone and Apple Watch.")
                }

                #if DEBUG
                Section("Developer") {
                    NavigationLink("Design System") { DesignSystemGallery() }
                    Button("Load sample runs") {
                        Task { await SampleData.insert(into: context, weightKg: weightKg) }
                    }
                    Button("Delete all runs", role: .destructive) { confirmingDeleteAll = true }
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Profile")
            .onChange(of: unit) { WatchSync.shared.pushSettings() }
            .onChange(of: maxHeartRate) { WatchSync.shared.pushSettings() }
            .confirmationDialog("Delete all runs and shoes?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    try? context.delete(model: Run.self)
                    try? context.delete(model: Shoe.self)
                }
            }
        }
    }
}

#Preview {
    ProfileView()
}

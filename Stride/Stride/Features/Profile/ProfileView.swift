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
    @AppStorage(StrideSettings.voiceCoach) private var voiceCoach = true
    @AppStorage(StrideSettings.voiceInterval) private var voiceInterval = 1.0
    @AppStorage(StrideSettings.voiceIncludePace) private var voiceIncludePace = true
    @AppStorage(StrideSettings.voiceIncludeTime) private var voiceIncludeTime = true
    @Environment(RunTracker.self) private var tracker

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

                Section("Training") {
                    NavigationLink("Training plans", value: PlanRoute.list)
                }

                Section {
                    Toggle("Voice coach", isOn: $voiceCoach)
                        .tint(.track)
                    if voiceCoach {
                        Picker("Announce every", selection: $voiceInterval) {
                            ForEach([0.5, 1, 2, 5], id: \.self) { value in
                                Text("\(value.formatted()) \(unit.distanceSymbol)").tag(value)
                            }
                        }
                        Toggle("Time", isOn: $voiceIncludeTime).tint(.track)
                        Toggle("Pace", isOn: $voiceIncludePace).tint(.track)
                        Button("Test voice") {
                            // The run's own voice, so a test line and a coach line never fight over the audio session.
                            tracker.coach.voice.speak(CoachScript.split(
                                distance: 5 * unit.metersPerUnit, elapsed: 1_642, averagePace: 328.4, lastSplitPace: 321,
                                unit: unit, splitLength: voiceInterval, includeTime: voiceIncludeTime, includePace: voiceIncludePace
                            ), force: true)
                        }
                    }
                } header: {
                    Text("Coach")
                } footer: {
                    Text("Spoken over your music: splits, workout steps, goal progress and target-pace alerts.")
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
            .planDestinations()
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

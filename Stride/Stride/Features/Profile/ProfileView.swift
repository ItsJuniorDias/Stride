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
    @AppStorage(StrideSettings.yearlyGoal) private var yearlyGoal = 1_000.0
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    @AppStorage(StrideSettings.weightKg) private var weightKg = 70.0
    @AppStorage(StrideSettings.maxHeartRate) private var maxHeartRate = HeartRateZone.defaultMaxHeartRate
    @AppStorage(StrideSettings.voiceCoach) private var voiceCoach = true
    @AppStorage(StrideSettings.voiceInterval) private var voiceInterval = 1.0
    @AppStorage(StrideSettings.voiceIncludePace) private var voiceIncludePace = true
    @AppStorage(StrideSettings.voiceIncludeTime) private var voiceIncludeTime = true
    @Environment(RunTracker.self) private var tracker
    @AppStorage(StrideSettings.healthSave) private var healthSave = false
    @State private var healthMessage: String?
    @State private var healthDenied = false

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
                    Stepper(value: $yearlyGoal, in: 100...10_000, step: 50) {
                        LabeledContent("Yearly distance", value: "\(Int(yearlyGoal).formatted()) \(unit.distanceSymbol)")
                    }
                }

                Section("Training") {
                    NavigationLink("Friends", value: ProgressRoute.friends)
                    NavigationLink("Training plans", value: PlanRoute.list)
                    NavigationLink("Challenges", value: ProgressRoute.challenges)
                    NavigationLink("Shoes", value: ProgressRoute.shoes)
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

                if HealthSync.shared.isAvailable {
                    Section {
                        Toggle("Save runs to Apple Health", isOn: Binding(get: { healthSave }, set: setHealthSave))
                            .tint(.track)
                        if healthSave {
                            Button("Save earlier runs too") {
                                Task {
                                    let saved = await HealthSync.shared.exportPending(in: context, includingEarlier: true)
                                    healthMessage = saved == 0 ? "Every run is already in Health." : "Saved \(saved) \(saved == 1 ? "run" : "runs") to Health."
                                }
                            }
                        }
                        Button("Update weight and age from Health") { Task { await updateFromHealth() } }
                        if healthDenied {
                            Text("Stride isn't allowed to save workouts. Turn it on in the Health app, under Sharing › Apps › Stride.")
                                .font(.footnote)
                                .foregroundStyle(.warning)
                        } else if let healthMessage {
                            Text(healthMessage).font(.footnote).foregroundStyle(.inkMuted)
                        }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Runs from iPhone and runs you add are saved with their route. Apple Watch saves its runs to Health itself.")
                    }
                }

                Section {
                    LabeledContent {
                        Text(iCloudStatus.value).foregroundStyle(.inkMuted)
                    } label: {
                        Label("iCloud sync", systemImage: iCloudStatus.on ? "icloud.fill" : "icloud.slash")
                    }
                } footer: {
                    Text(iCloudStatus.footer)
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
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .planDestinations()
            .progressDestinations()
            .onAppear { healthDenied = healthSave && HealthSync.shared.wasDenied }
            .task { await FriendsService.shared.checkAccount() }
            .onChange(of: unit) { WatchSync.shared.pushSettings() }
            .onChange(of: maxHeartRate) { WatchSync.shared.pushSettings() }
            .confirmationDialog("Delete all runs, shoes and challenges?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    // One by one: batch deletes don't reach iCloud.
                    (try? context.fetch(FetchDescriptor<Run>()))?.forEach(context.delete)
                    (try? context.fetch(FetchDescriptor<RunVitals>()))?.forEach(context.delete)
                    (try? context.fetch(FetchDescriptor<Shoe>()))?.forEach(context.delete)
                    (try? context.fetch(FetchDescriptor<Challenge>()))?.forEach(context.delete)
                    try? context.save()
                    ShoeDefaults.set(nil)
                }
            }
        }
    }
}

extension ProfileView {
    /// What the iCloud row says: syncing needs both the capability and a signed-in account.
    private var iCloudStatus: (on: Bool, value: String, footer: String) {
        let account = FriendsService.shared.account
        guard CloudStore.syncsWithICloud else {
            return (false, "Off", "Runs are kept on this iPhone only.")
        }
        switch account {
        case .noAccount:
            return (false, "Signed out", "Sign in to iCloud in Settings to keep your runs on all your iPhones.")
        case .restricted, .unavailable:
            return (false, "Unavailable", "iCloud isn't available right now. Runs sync once it is.")
        case .available, .unknown:
            return (true, "On", "Runs, shoes, challenges and settings stay in step on every iPhone signed in to your iCloud account. Heart rate stays on this iPhone.")
        }
    }

    private func setHealthSave(_ on: Bool) {
        healthSave = on
        healthMessage = nil
        guard on else {
            healthDenied = false
            return
        }
        // Runs from now on; earlier ones (including any recorded while saving was off) only when asked.
        UserDefaults.standard.set(Date.now, forKey: StrideSettings.healthSaveSince)
        Task {
            _ = await HealthSync.shared.requestAuthorization()
            healthDenied = HealthSync.shared.wasDenied
            await HealthSync.shared.exportPending(in: context)
        }
    }

    private func updateFromHealth() async {
        let body = await HealthSync.shared.readBody()
        var updated: [String] = []
        if let weight = body.weightKg, weight >= 30, weight <= 200 {
            weightKg = weight.rounded()
            updated.append("weight \(Int(weightKg)) kg")
        }
        if let age = body.age, age >= 10, age <= 100 {
            // Tanaka: 208 − 0.7 × age, closer than 220 − age for adults.
            maxHeartRate = min(max((208 - 0.7 * Double(age)).rounded(), 140), 220)
            updated.append("max heart rate \(Int(maxHeartRate)) bpm")
        }
        healthMessage = updated.isEmpty ? "Health has no weight or birthday to read. Check Health's permissions for Stride."
                                        : "Updated \(updated.joined(separator: " and "))."
    }
}

#Preview {
    ProfileView()
}

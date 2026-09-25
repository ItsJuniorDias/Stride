import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Shown right after a run is finished. The run is already saved; this screen adds how it felt.
struct RunSummaryView: View {
    @Bindable var run: Run
    /// Records this run set; passed in so they stay while the cover slides away after the tracker resets.
    let achievements: [RecordAchievement]
    @Environment(RunTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var route: [RoutePoint] = []
    @State private var splits: [Split] = []
    @State private var confirmingDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.success)
                        .symbolEffect(.bounce, value: splits.count)
                        .padding(.bottom, Space.x1)
                        .accessibilityHidden(true)
                    Text("Run complete")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.ink)
                    Text(run.startDate.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }

                if !achievements.isEmpty {
                    RecordsEarnedCard(achievements: achievements, unit: unit)
                }

                RunReport(run: run, route: route, splits: splits, unit: unit)

                if let shoe = run.shoe, shoe.isWornOut, !shoe.isRetired {
                    ShoeWearNotice(shoe: shoe, unit: unit)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("How did it feel?").font(.headline).foregroundStyle(.ink)
                    FeelingPicker(selection: $run.feeling)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Surface").font(.headline).foregroundStyle(.ink)
                    SurfacePicker(selection: $run.surface)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Notes").font(.headline).foregroundStyle(.ink)
                    TextField("How did it go?", text: $run.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(Space.x4)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                }
            }
            .padding(Space.x4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.surface)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Space.x3) {
                Button("Discard") { confirmingDiscard = true }
                    .buttonStyle(.strideSecondary)
                    .fixedSize(horizontal: true, vertical: false)
                Button("Save run") {
                    try? context.save()
                    tracker.reset()
                }
                .buttonStyle(.stridePrimary)
            }
            .padding(.horizontal, Space.x4)
            .padding(.vertical, Space.x3)
            .background(alignment: .top) {
                // Fade the scrolling content into the bar instead of cutting it off.
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.surface.opacity(0), Color.surface], startPoint: .top, endPoint: .bottom)
                        .frame(height: Space.x5)
                    Color.surface
                }
                .padding(.top, -Space.x5)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .confirmationDialog("Discard this run?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Run", role: .destructive) {
                // Deleted by RootView once the cover is gone, so this screen never shows a deleted run.
                tracker.discardSaved(run)
            }
        } message: {
            Text("It will be deleted and won't count toward your stats.")
        }
        .task(id: unit) {
            if route.isEmpty { route = run.route }
            splits = unit == .metric ? run.splits : RouteAnalysis.splits(from: route, unit: unit)
        }
    }
}

/// Shown after a run that took a shoe close to (or past) its replacement distance.
struct ShoeWearNotice: View {
    let shoe: Shoe
    let unit: UnitSystem

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            ShoeIcon(shoe: shoe)
            VStack(alignment: .leading, spacing: Space.x2) {
                Text(shoe.wear >= 1 ? "Time for new shoes" : "\(shoe.displayName) is nearly worn out")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                Text("\(shoe.displayName) has \(ShoeWear.distance(shoe.totalDistance, unit: unit)) \(unit.distanceSymbol) on it. You planned to replace it at \(ShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol).")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
                Button("Retire shoe") { ShoeDefaults.setRetired(shoe, true) }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .raisedCard()
    }
}

struct FeelingPicker: View {
    @Binding var selection: Feeling?

    var body: some View {
        HStack(spacing: Space.x2) {
            ForEach(Feeling.allCases) { feeling in
                let isSelected = selection == feeling
                Button {
                    selection = isSelected ? nil : feeling
                } label: {
                    VStack(spacing: Space.x1) {
                        Text(feeling.emoji).font(.title2)
                        Text(feeling.title).font(.caption.weight(.medium)).foregroundStyle(.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(isSelected ? Color.trackSoft : Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.track, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feeling.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct SurfacePicker: View {
    @Binding var selection: Surface?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x2) {
                ForEach(Surface.allCases) { surface in
                    SelectableChip(surface.title, isSelected: selection == surface) {
                        selection = selection == surface ? nil : surface
                    }
                }
            }
        }
    }
}

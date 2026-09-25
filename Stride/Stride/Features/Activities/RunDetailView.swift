import SwiftUI
import SwiftData
import StrideKit
import StrideUI

struct RunDetailView: View {
    @Bindable var run: Run
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var route: [RoutePoint] = []
    @State private var splits: [Split] = []
    @State private var confirmingDelete = false

    var body: some View {
        // The run can be deleted elsewhere (another tab) while this screen is still in a stack.
        if run.isDeleted || run.modelContext == nil {
            ContentUnavailableView("Run deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                Text(run.startDate.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)

                RunReport(run: run, route: route, splits: splits, unit: unit)

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
        .navigationTitle(run.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Delete Run", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this run?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Run", role: .destructive) {
                let run = self.run
                dismiss()
                // Delete after the pop so this screen never renders a deleted model.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    context.delete(run)
                    try? context.save()
                }
            }
        }
        .task(id: unit) {
            if route.isEmpty { route = run.route }
            splits = unit == .metric ? run.splits : RouteAnalysis.splits(from: route, unit: unit)
        }
    }
}

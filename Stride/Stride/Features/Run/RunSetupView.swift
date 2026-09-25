import SwiftUI
import StrideUI

/// Placeholder for the run setup screen. GPS tracking arrives in phase 1.
struct RunSetupView: View {
    private enum RunType: String, CaseIterable {
        case free = "Free run", distance = "Distance", time = "Time", intervals = "Intervals"
    }

    @State private var runType: RunType = .free

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.x5) {
                Spacer()
                StatusChip("GPS arrives in phase 1", indicator: .warning)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.x2) {
                        ForEach(RunType.allCases, id: \.self) { type in
                            SelectableChip(type.rawValue, isSelected: runType == type) { runType = type }
                        }
                    }
                    .padding(.horizontal, Space.x4)
                }
                RunControlButton(.start) {}
                    .padding(.bottom, Space.x6)
            }
            .frame(maxWidth: .infinity)
            .background(Color.surface)
            .navigationTitle("Run")
        }
    }
}

#Preview {
    RunSetupView()
}

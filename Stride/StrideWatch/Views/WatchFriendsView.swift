import SwiftUI
import StrideKit
import StrideUI

/// This week against friends, from the snapshot iPhone sends.
struct WatchFriendsView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let unit = snapshot.unit
        List {
            ForEach(snapshot.leaderboard()) { row in
                HStack(spacing: Space.x2) {
                    Text("\(row.rank)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(row.rank == 1 && row.distance > 0 ? Color.track : Color.inkMuted)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 2) {
                            Text(row.isMe ? "You" : row.name).font(.headline).lineLimit(1)
                            if row.cheeredMe { Text("👏").font(.caption2) }
                        }
                        Text("\(RunFormat.distance(row.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(row.isMe ? Color.track : Color.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Friends")
    }
}

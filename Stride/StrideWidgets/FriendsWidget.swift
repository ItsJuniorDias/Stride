import WidgetKit
import SwiftUI
import StrideKit
import StrideUI

/// This week against friends: where you stand and who's ahead.
struct FriendsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.friendsKind, provider: WeeklyProvider()) { entry in
            FriendsWidgetView(entry: entry)
                .widgetURL(URL(string: "stride://progress"))
        }
        .configurationDisplayName("Friends")
        .description("This week's distance against your friends.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct FriendsWidgetView: View {
    let entry: WeeklyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let rows = entry.snapshot?.leaderboard(at: entry.date) ?? []
        let unit = entry.snapshot?.unit ?? .metric
        if rows.count < 2 {
            VStack(alignment: .leading, spacing: Space.x1) {
                Label("Friends", systemImage: "person.2.fill").font(.caption.weight(.semibold)).foregroundStyle(.lane)
                Text("Add friends in Stride to see their week here.").font(.caption).foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { family == .systemMedium ? Color.surfaceRaised : Color.clear }
        } else if family == .accessoryRectangular {
            let me = rows.first(where: \.isMe)
            VStack(alignment: .leading, spacing: 1) {
                Label("Friends", systemImage: "person.2.fill").font(.caption.weight(.semibold)).widgetAccentable()
                if let me { Text("You're #\(me.rank) of \(rows.count)").font(.headline) }
                if let leader = rows.first, !leader.isMe {
                    Text("\(leader.name.split(separator: " ").first.map(String.init) ?? leader.name) leads · \(RunFormat.distance(leader.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)")
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        } else {
            VStack(alignment: .leading, spacing: Space.x1) {
                HStack {
                    Text("Friends this week").font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                    Spacer()
                    Image(systemName: "person.2.fill").font(.caption).foregroundStyle(.lane)
                }
                ForEach(Array(rows.prefix(3))) { row in
                    HStack(spacing: Space.x2) {
                        Text("\(row.rank)").font(.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(row.rank == 1 && row.distance > 0 ? Color.track : Color.inkMuted)
                            .frame(width: 14)
                        Text(row.isMe ? "You" : row.name).font(.subheadline.weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                        if row.cheeredMe { Text("👏").font(.caption2) }
                        Spacer()
                        Text("\(RunFormat.distance(row.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(row.isMe ? Color.track : Color.ink)
                    }
                }
                if let me = rows.first(where: \.isMe), me.rank > 3 {
                    Text("You're #\(me.rank) · \(RunFormat.distance(me.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)")
                        .font(.caption)
                        .foregroundStyle(.track)
                }
            }
            .containerBackground(for: .widget) { Color.surfaceRaised }
        }
    }
}

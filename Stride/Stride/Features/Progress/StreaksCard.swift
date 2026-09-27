import SwiftUI
import StrideKit
import StrideUI

/// Weeks and days in a row with a run, and a heatmap of the last weeks.
struct StreaksCard: View {
    let samples: [RunSample]
    let now: Date

    var body: some View {
        let streaks = Streaks.summary(of: samples.map(\.date), now: now)
        VStack(alignment: .leading, spacing: Space.x3) {
            Text("Streaks")
                .font(.headline)
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: Space.x4) {
                HStack(alignment: .top, spacing: Space.x3) {
                    StatTile("Weekly", value: "\(streaks.currentWeeks)",
                             unit: streaks.currentWeeks == 1 ? "week" : "weeks", size: .medium)
                    StatTile("Daily", value: "\(streaks.currentDays)",
                             unit: streaks.currentDays == 1 ? "day" : "days", size: .medium)
                }
                if streaks.currentWeeks > 0 || streaks.currentDays > 0 {
                    ArtThumbnail(name: "streakFlame", width: 52, height: 52, cornerRadius: Radius.md)
                }
            }
            Text("Longest: \(streaks.longestWeeks) \(streaks.longestWeeks == 1 ? "week" : "weeks") · \(streaks.longestDays) \(streaks.longestDays == 1 ? "day" : "days") in a row")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
            ActivityHeatmap(daily: RunStats.dailyDistance(of: samples), now: now)
                .padding(.top, Space.x1)
        }
        .raisedCard()
    }
}

/// One square per day for the last weeks, in four shades of the data color by distance. Columns are
/// weeks, oldest first; days still to come are left empty.
struct ActivityHeatmap: View {
    let daily: [Date: Double]
    let now: Date
    var weeks = 26

    /// No run, then the four shades from shortest to longest.
    private static let shades: [Double] = [0.3, 0.55, 0.8, 1]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let columns = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        let shown = columns.flatMap { week in (0..<7).map { day(week, $0, calendar) } }
        let distances = shown.compactMap { daily[$0] }.filter { $0 > 0 }
        // The longest day shown sets the darkest shade, so one ultra doesn't wash the rest out.
        let reference = distances.sorted().dropLast(distances.count / 10).last ?? 1

        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: 3) {
                ForEach(columns, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { offset in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: day(week, offset, calendar), today: today, reference: reference))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            HStack(spacing: Space.x1) {
                Text("Last \(weeks) weeks")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Less").padding(.trailing, 2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.surfaceSunken)
                    .frame(width: 10, height: 10)
                ForEach(Self.shades, id: \.self) { shade in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.lane.opacity(shade))
                        .frame(width: 10, height: 10)
                }
                Text("More").padding(.leading, 2)
            }
            .font(.caption2)
            .foregroundStyle(.inkMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity over the last \(weeks) weeks")
        .accessibilityValue("Ran on \(distances.count) \(distances.count == 1 ? "day" : "days")")
    }

    /// The start of the day `offset` days into `week`, matching the keys of `daily` even where
    /// daylight saving skips midnight.
    private func day(_ week: Date, _ offset: Int, _ calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: week) ?? week)
    }

    private func color(for day: Date, today: Date, reference: Double) -> Color {
        guard day <= today else { return .clear }
        guard let distance = daily[day], distance > 0 else { return .surfaceSunken }
        let level = min(max(Int((distance / max(reference, 1) * Double(Self.shades.count)).rounded(.up)), 1), Self.shades.count)
        return Color.lane.opacity(Self.shades[level - 1])
    }
}

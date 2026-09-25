import SwiftUI
import StrideKit
import StrideUI

/// Map, headline metrics and splits for a finished run. Used by the summary and the detail screen.
struct RunReport: View {
    let run: Run
    let route: [RoutePoint]
    let splits: [Split]
    let unit: UnitSystem

    private struct Tile: Identifiable {
        let label: String
        let value: String
        let unit: String?
        var id: String { label }
    }

    private var tiles: [Tile] {
        var tiles = [
            Tile(label: "Time", value: RunFormat.duration(run.duration), unit: nil),
            Tile(label: "Avg pace", value: RunFormat.pace(run.averagePace(in: unit)), unit: unit.paceSymbol),
            Tile(label: "Calories", value: "\(Int(run.calories))", unit: "kcal"),
            Tile(label: "Elevation", value: "\(Int(unit.elevation(fromMeters: run.elevationGain)))", unit: unit.elevationSymbol),
        ]
        if let fastest = Split.fastest(in: splits, unit: unit) {
            tiles.append(Tile(label: "Fastest \(unit.distanceSymbol)", value: RunFormat.pace(fastest.pace(in: unit)), unit: unit.paceSymbol))
        }
        if let heartRate = run.averageHeartRate {
            tiles.append(Tile(label: "Avg heart rate", value: "\(Int(heartRate))", unit: "bpm"))
        }
        return tiles
    }

    /// Tiles in pairs; a lone last tile spans the full width instead of sitting beside a gap.
    private var tileRows: [[Tile]] {
        stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            if route.count > 1 {
                RouteMapView(points: route)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }

            MetricView("Distance", value: RunFormat.distance(run.distance, unit: unit), unit: unit.distanceSymbol, size: .large)

            Grid(horizontalSpacing: Space.x3, verticalSpacing: Space.x3) {
                ForEach(tileRows.indices, id: \.self) { index in
                    let row = tileRows[index]
                    GridRow {
                        ForEach(row) { tile in
                            MetricTile(tile.label, value: tile.value, unit: tile.unit)
                                .gridCellColumns(row.count == 1 ? 2 : 1)
                        }
                    }
                }
            }

            if !splits.isEmpty {
                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Splits").font(.headline).foregroundStyle(.ink)
                    SplitTable(splits: splits, unit: unit)
                }
            }

            let zones = run.zoneSeconds
            if !zones.isEmpty {
                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Heart rate zones").font(.headline).foregroundStyle(.ink)
                    ZoneBars(seconds: zones)
                }
            }
        }
    }
}

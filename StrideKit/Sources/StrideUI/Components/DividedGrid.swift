import SwiftUI

/// Which hairlines a ``DividedGrid`` draws between its cells.
public enum GridDividers: Sendable {
    /// Between rows and between columns: the run summary's 2 × 2 card, the run setup settings strip.
    case all
    /// Only between rows: the live run metrics.
    case rows
    /// None.
    case hidden
}

/// Cells in equal columns with `line` hairlines between them, on a raised card unless `fill` is nil.
/// Pass the cells as separate views, usually ``StatTile``s; a last row that isn't full is padded.
///
///     DividedGrid(columns: 2) {
///         StatTile("Avg pace", value: "5'16\"", unit: "/km", size: .medium)
///         StatTile("Avg heart rate", value: "158", unit: "bpm", size: .medium)
///         StatTile("Calories", value: "548", unit: "kcal", size: .medium)
///         StatTile("Elevation", value: "24", unit: "m", size: .medium)
///     }
public struct DividedGrid<Content: View>: View {
    let columns: Int
    let dividers: GridDividers
    let alignment: HorizontalAlignment
    let cellPadding: EdgeInsets
    let fill: Color?
    let content: Content

    public init(columns: Int = 2, dividers: GridDividers = .all, alignment: HorizontalAlignment = .leading,
                cellPadding: EdgeInsets = EdgeInsets(top: 14, leading: Space.x4, bottom: 14, trailing: Space.x4),
                fill: Color? = .surfaceRaised, @ViewBuilder content: () -> Content) {
        self.columns = max(columns, 1)
        self.dividers = dividers
        self.alignment = alignment
        self.cellPadding = cellPadding
        self.fill = fill
        self.content = content()
    }

    public var body: some View {
        Group(subviews: content) { subviews in
            let rowCount = (subviews.count + columns - 1) / columns
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<rowCount, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            Group {
                                if index < subviews.count {
                                    subviews[index]
                                } else {
                                    Color.clear
                                }
                            }
                            .padding(cellPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: Alignment(horizontal: alignment, vertical: .top))
                            .overlay(alignment: .top) {
                                if row > 0, dividers != .hidden {
                                    Rectangle().fill(Color.line).frame(height: 1)
                                }
                            }
                            .overlay(alignment: .leading) {
                                if column > 0, dividers == .all {
                                    Rectangle().fill(Color.line).frame(width: 1)
                                }
                            }
                        }
                    }
                }
            }
            // Its own height, even where the parent offers more (the live run screen), so rows don't stretch.
            .fixedSize(horizontal: false, vertical: true)
            .background {
                if let fill {
                    RoundedRectangle(cornerRadius: Radius.md).fill(fill)
                }
            }
        }
    }
}

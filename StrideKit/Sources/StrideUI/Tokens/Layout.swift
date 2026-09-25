import CoreGraphics

/// Spacing scale (design tokens space-1 … space-7).
public enum Space {
    /// 4 — icon-to-label, number-to-unit.
    public static let x1: CGFloat = 4
    /// 8 — inside chips, label-to-value.
    public static let x2: CGFloat = 8
    /// 12 — between tiles in a grid.
    public static let x3: CGFloat = 12
    /// 16 — screen gutter, card padding.
    public static let x4: CGFloat = 16
    /// 24 — between sections.
    public static let x5: CGFloat = 24
    /// 32 — above the run controls.
    public static let x6: CGFloat = 32
    /// 48 — top breathing room on the live run screen.
    public static let x7: CGFloat = 48
}

/// Corner radii.
public enum Radius {
    /// Split bars, badges, thumbnails.
    public static let sm: CGFloat = 8
    /// Tiles, cards, text fields.
    public static let md: CGFloat = 14
    /// Sheets, the run setup panel, the share card.
    public static let lg: CGFloat = 24
}

/// Control and hit-target sizes.
public enum Dimension {
    /// Start, Pause, Resume, Finish.
    public static let runControl: CGFloat = 96
    /// Full-width capsule buttons.
    public static let control: CGFloat = 52
    /// Minimum tappable size.
    public static let hitMin: CGFloat = 44
}

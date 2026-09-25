import SwiftUI
import StrideKit
#if canImport(UIKit)
import UIKit
#endif

// Color tokens from the Stride design system. Each token has a Light, Dark and Watch value;
// iOS resolves Light/Dark from the trait collection, watchOS always uses the Watch value.
public extension ShapeStyle where Self == Color {
    /// Screen background.
    static var surface: Color { Palette.surface }
    /// Cards, sheets, list rows.
    static var surfaceRaised: Color { Palette.surfaceRaised }
    /// Progress-bar tracks, ring backgrounds, input wells.
    static var surfaceSunken: Color { Palette.surfaceSunken }
    /// Decorative hairlines between rows.
    static var line: Color { Palette.line }
    /// Control borders; 3:1 on surface and surfaceRaised.
    static var lineStrong: Color { Palette.lineStrong }
    /// Primary text and live metrics.
    static var ink: Color { Palette.ink }
    /// Labels, units, metadata.
    static var inkMuted: Color { Palette.inkMuted }
    /// Brand color: the one action on a screen.
    static var track: Color { Palette.track }
    static var trackSoft: Color { Palette.trackSoft }
    static var onTrack: Color { Palette.onTrack }
    /// Data color: charts, links, focus.
    static var lane: Color { Palette.lane }
    static var laneSoft: Color { Palette.laneSoft }
    static var onLane: Color { Palette.onLane }
    static var success: Color { Palette.success }
    static var warning: Color { Palette.warning }
    static var danger: Color { Palette.danger }
    static var onDanger: Color { Palette.onDanger }
    static var focus: Color { Palette.lane }
}

public extension HeartRateZone {
    /// Blue-to-orange effort scale; always pair it with the zone number or name.
    var color: Color {
        switch self {
        case .recovery: Palette.zone1
        case .easy: Palette.zone2
        case .aerobic: Palette.zone3
        case .threshold: Palette.zone4
        case .maximum: Palette.zone5
        }
    }
}

enum Palette {
    static let surface = Color(light: 0xF3F4F1, dark: 0x101419, watch: 0x000000)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x1A2029, watch: 0x1C1F24)
    static let surfaceSunken = Color(light: 0xE6E8E3, dark: 0x0B0E12, watch: 0x0E1013)
    static let line = Color(light: 0xC9CDC4, dark: 0x3A4452, watch: 0x3A3F47)
    static let lineStrong = Color(light: 0x7E8691, dark: 0x6B7684, watch: 0x6B7684)
    static let ink = Color(light: 0x12161C, dark: 0xF2F4F0, watch: 0xFFFFFF)
    static let inkMuted = Color(light: 0x5A6270, dark: 0x9BA5B3, watch: 0xA1A8B3)
    static let track = Color(light: 0xC8401F, dark: 0xFF6B47, watch: 0xFF6B47)
    static let trackSoft = Color(light: 0xFBE3DA, dark: 0x3A1A12, watch: 0x3A1A12)
    static let onTrack = Color(light: 0xFFFFFF, dark: 0x12161C, watch: 0x000000)
    static let lane = Color(light: 0x1D5FC4, dark: 0x74AEFF, watch: 0x74AEFF)
    static let laneSoft = Color(light: 0xDCE8FA, dark: 0x132A4A, watch: 0x132A4A)
    static let onLane = Color(light: 0xFFFFFF, dark: 0x101419, watch: 0x000000)
    static let zone1 = Color(light: 0x7A8CA6, dark: 0x8C9DB5, watch: 0x8C9DB5)
    static let zone2 = Color(light: 0x3A7FE0, dark: 0x5B9BFF, watch: 0x5B9BFF)
    static let zone3 = Color(light: 0x23915F, dark: 0x3FC286, watch: 0x3FC286)
    static let zone4 = Color(light: 0xB07400, dark: 0xF2B53A, watch: 0xF2B53A)
    static let zone5 = Color(light: 0xD23F22, dark: 0xFF6B47, watch: 0xFF6B47)
    static let success = Color(light: 0x1E7A4C, dark: 0x4CC38A, watch: 0x4CC38A)
    static let warning = Color(light: 0x8F5B00, dark: 0xF2B53A, watch: 0xF2B53A)
    static let danger = Color(light: 0xB3261E, dark: 0xFF8A80, watch: 0xFF8A80)
    static let onDanger = Color(light: 0xFFFFFF, dark: 0x12161C, watch: 0x000000)
}

extension Color {
    init(light: UInt32, dark: UInt32, watch: UInt32) {
        #if os(watchOS)
        self.init(hex: watch)
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #endif
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

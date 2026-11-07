import SwiftUI
import AppKit

/// Palette from the redesign. Each token resolves per-appearance, so light /
/// dark switching costs nothing at runtime.
enum PT {
    static let panel    = dyn(hex(0xFFFFFF), hex(0x252528))
    static let border   = dyn(black(0.12), white(0.11))
    static let text     = dyn(hex(0x1D1D1F), hex(0xF5F5F7))
    static let text2    = dyn(hex(0x6B6B70), hex(0xA1A1A6))
    static let ph       = dyn(hex(0x76767B), hex(0x8E8E93))
    static let field    = dyn(hex(0xF1F1F3), hex(0x323236))
    static let seg      = dyn(hex(0xEDEDF0), hex(0x323236))
    static let segOn    = dyn(hex(0xFFFFFF), hex(0x58585D))
    static let segShadow = dyn(black(0.14), .clear)
    static let chip     = dyn(black(0.07), white(0.10))
    static let line     = dyn(black(0.08), white(0.07))
    static let hover    = dyn(black(0.045), white(0.06))
    static let red      = dyn(hex(0xC4122A), hex(0xFF7A70))
    static let redBg    = dyn(hex(0xFDECEE), NSColor(srgbRed: 1, green: 69 / 255, blue: 58 / 255, alpha: 0.17))
    static let orange   = dyn(hex(0xA04800), hex(0xFFB340))
    static let orangeBg = dyn(hex(0xFFF0E0), NSColor(srgbRed: 1, green: 159 / 255, blue: 10 / 255, alpha: 0.16))
    static let green    = dyn(hex(0x1B7A36), hex(0x5BD97A))
    static let killRed  = Color(nsColor: hex(0xD70015))

    static let mono = "SF Mono"

    // Motion: one spring for structure, one quick ease for hover.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let quick  = Animation.easeOut(duration: 0.12)

    private static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    private static func black(_ a: CGFloat) -> NSColor { NSColor(white: 0, alpha: a) }
    private static func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }
}

extension Font {
    static func ptMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Subtle press feedback shared by every button in the popover.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(PT.quick, value: configuration.isPressed)
    }
}

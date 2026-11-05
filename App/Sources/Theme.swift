import SwiftUI

/// The palette and metrics of SpektraLab's editor, carried over to a phone.
///
/// Values are the ones its `Theme.swift` uses: a neutral gray surround
/// (`ground`), a near-black panel (`card`), warm off-white ink, and a single
/// amber accent that is reserved for state. Type is small and bold, and every
/// number is monospaced so a column of values lines up.
enum Theme {
    // MARK: surfaces

    /// The canvas surround — the photo sits on this, not on a card.
    static let ground = Color(hex: 0x5F5F5F)
    /// Panels and rails.
    static let card = Color(hex: 0x2D2D2C)
    /// Wells: the navigator, the histogram plot, list backgrounds.
    static let well = Color(hex: 0x1A1A19)
    /// Hairlines between sections.
    static let rule = Color(hex: 0x3A3B39)

    // MARK: ink

    enum Ink {
        static let text = Color(hex: 0xF9F7F3)
        static let secondary = Color(hex: 0xDAD8D4)
        static let tertiary = Color(hex: 0x898989)
        static let onSelection = Color(hex: 0x0F0E0E)
    }

    /// Amber. Selection borders, active toggles, the one filled button.
    static let accent = Color(hex: 0xE1A95F)
    static let selection = Color(hex: 0xFFFFFF)
    static let knob = Color(hex: 0xFBF8F3)
    static let disabledOpacity: Double = 0.38

    // MARK: type

    enum Type_ {
        static let sectionTitle = Font.system(size: 12, weight: .bold)
        static let label = Font.system(size: 11, weight: .semibold)
        static let sublabel = Font.system(size: 9, weight: .regular)
        static let value = Font.system(size: 10.5, weight: .bold).monospacedDigit()
        static let stock = Font.system(size: 12, weight: .semibold)
        static let caption = Font.system(size: 10, weight: .medium)
        static let navTitle = Font.system(size: 13, weight: .bold)
    }

    // MARK: metrics
    //
    // SpektraLab's row is 22 pt with a 1.36 pt track; a phone needs a slightly
    // taller row and a track you can see, so the shape is kept and the numbers
    // are nudged.

    enum Metric {
        static let hairline: CGFloat = 1
        static let rowHeight: CGFloat = 26
        static let trackHeight: CGFloat = 2
        static let knob: CGFloat = 13
        static let labelWidth: CGFloat = 78
        static let valueWidth: CGFloat = 58
        static let headerHeight: CGFloat = 30
        static let sectionGap: CGFloat = 10
        static let panelPadding: CGFloat = 12
        static let disclosure = CGSize(width: 9, height: 6)
    }
}

extension Color {
    /// `Color(hex: 0x2D2D2C)` — the form the whole theme is written in.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// A 1 pt rule, the way the rails separate sections: a line, not a card.
struct Hairline: View {
    var color: Color = Theme.rule
    var body: some View {
        Rectangle().fill(color).frame(height: Theme.Metric.hairline)
    }
}

/// The disclosure triangle from the rails, drawn rather than an SF Symbol so
/// it keeps the drawn weight at 9 × 6.
struct DisclosureTriangle: View {
    var expanded: Bool
    var body: some View {
        Triangle()
            .stroke(Theme.Ink.text, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
            .frame(width: Theme.Metric.disclosure.width, height: Theme.Metric.disclosure.height)
            .rotationEffect(.degrees(expanded ? 0 : -90))
            .frame(width: 18, height: 18)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

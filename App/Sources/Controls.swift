import SwiftUI

/// A titled block that folds away, with the rail's hairline underneath.
///
/// SpektraLab puts every group of controls behind one of these: a 9 × 6
/// triangle, a small bold title, an optional note at the trailing end, and a
/// rule below — never a rounded card.
struct SectionBlock<Content: View>: View {
    let title: String
    @Binding var expanded: Bool
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    DisclosureTriangle(expanded: expanded)
                    Text(title)
                        .font(Theme.Type_.sectionTitle)
                        .tracking(0.4)
                        .foregroundStyle(Theme.Ink.text)
                    Spacer(minLength: 8)
                    if let note {
                        Text(note)
                            .font(Theme.Type_.caption)
                            .foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                .frame(height: Theme.Metric.headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 2) { content() }
                    .padding(.bottom, Theme.Metric.sectionGap)
            }
            Hairline()
        }
    }
}

/// The rail's parameter row: label, thin track, value — with an optional
/// sublabel that says what the direction does ("→ blue").
///
/// The track is drawn rather than using `Slider` so the gradient form from the
/// enlarger head survives; `Slider` cannot tint its track with a gradient.
struct ScrubRow: View {
    let label: String
    var sublabel: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var snap: Double = 0
    var gradient: [Color]? = nil
    var format: (Double) -> String = { String(format: "%+.2f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 10) {
                Text(label)
                    .font(Theme.Type_.label)
                    .foregroundStyle(Theme.Ink.text)
                    .frame(width: Theme.Metric.labelWidth, alignment: .leading)

                track

                Text(format(value))
                    .font(Theme.Type_.value)
                    .foregroundStyle(Theme.Ink.secondary)
                    .frame(width: Theme.Metric.valueWidth, alignment: .trailing)
            }
            .frame(height: Theme.Metric.rowHeight)

            if let sublabel {
                Text(sublabel)
                    .font(Theme.Type_.sublabel)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .padding(.leading, Theme.Metric.labelWidth + 10)
                    .frame(height: 14, alignment: .leading)
            }
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let clamped = min(max(fraction, 0), 1)
            let knob = Theme.Metric.knob
            let x = min(max(width * CGFloat(clamped), knob / 2), width - knob / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(fill)
                    .frame(height: Theme.Metric.trackHeight)
                Circle()
                    .fill(Theme.knob)
                    .frame(width: knob, height: knob)
                    .offset(x: x - knob / 2)
            }
            .frame(height: Theme.Metric.rowHeight, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let position = min(max(gesture.location.x, 0), width)
                        var newValue = range.lowerBound + Double(position / width) * span
                        if snap > 0 { newValue = (newValue / snap).rounded() * snap }
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(height: Theme.Metric.rowHeight)
    }

    private var fill: AnyShapeStyle {
        if let gradient, gradient.count >= 2 {
            return AnyShapeStyle(LinearGradient(colors: gradient,
                                                startPoint: .leading,
                                                endPoint: .trailing))
        }
        return AnyShapeStyle(Theme.rule)
    }
}

/// A film or paper chip. The selected one is the rail's inverted row: white
/// block, dark text, no rounding worth mentioning.
struct StockChip: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(Theme.Type_.stock)
            .foregroundStyle(selected ? Theme.Ink.onSelection : Theme.Ink.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Theme.selection : Color.clear)
            .overlay(Rectangle().stroke(Theme.rule, lineWidth: 1))
    }
}

/// A small square button, the size the rail uses for its "•••" and reset.
struct GlyphButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Ink.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
    }
}

import SwiftUI

/// The noboard design tokens (Paper file "noboard - mobile"): colours, type scale and the few shared pieces.
enum Theme {
    static let background = Color.black
    static let surface = Color(hex: 0x0F0F0F)
    static let border = Color(hex: 0x1F1F1F)
    static let field = Color(hex: 0x1C1C1E)
    static let key = Color(hex: 0x3A3A3C)
    static let pill = Color(hex: 0x2C2C2E)
    static let hairline = Color(hex: 0x2E2E2E)
    static let stripBorder = Color(hex: 0x262628)
    static let dashed = Color(hex: 0x333336)
    static let secondary = Color(hex: 0xA1A1A6)
    static let tertiary = Color(hex: 0x8E8E93)
    static let faint = Color(hex: 0x6E6E73)
    static let accent = Color(hex: 0x0B84F5)
    static let tint = Color(hex: 0xA6EDFF)
    static let tintPale = Color(hex: 0xDCF5FF)
    static let edit = Color(hex: 0xAF6EFF)
    static let editStroke = Color(hex: 0xB98CFF)
    static let editText = Color(hex: 0xC9B0FF)
    static let mic = Color(hex: 0xFF9F0A)
    static let success = Color(hex: 0x30D158)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: Layout

/// True at regular width (≥ 700 pt): the iPad layouts, a centred column and the larger type scale.
extension EnvironmentValues {
    @Entry var wide = false
}

/// Measures the width once at the root and publishes `wide` to everything below.
struct AdaptiveRoot<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var wide = false

    var body: some View {
        content
            .environment(\.wide, wide)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide = $0 }
    }
}

// MARK: Type

/// One step of the type scale. `tracking` is in em, as in the design.
struct TextStyle {
    var size: CGFloat
    var weight: Font.Weight = .regular
    var tracking: CGFloat = 0
    var lineHeight: CGFloat? = nil
    var mono = false
    var caps = false
    var italic = false

    static func display(_ wide: Bool) -> Self { .init(size: wide ? 96 : 64, weight: .bold, tracking: wide ? -0.05 : -0.045, lineHeight: wide ? 96 : 64) }
    static func title(_ wide: Bool) -> Self { .init(size: wide ? 64 : 40, weight: .bold, tracking: -0.035, lineHeight: wide ? 68 : 44) }
    static func tagline(_ wide: Bool) -> Self { .init(size: wide ? 28 : 22, tracking: wide ? -0.015 : -0.01, lineHeight: wide ? 36 : 30) }
    static func body(_ wide: Bool) -> Self { .init(size: wide ? 20 : 17, tracking: -0.01, lineHeight: wide ? 28 : 24) }
    static func button(_ wide: Bool) -> Self { .init(size: wide ? 18 : 17, weight: .semibold, tracking: -0.01) }
    /// Monospaced caps labels; 12/13 above titles, 11 inside cards.
    static func overline(_ wide: Bool) -> Self { .init(size: wide ? 13 : 12, weight: .medium, tracking: 0.08, lineHeight: 16, mono: true, caps: true) }
    static let label = TextStyle(size: 11, weight: .medium, tracking: 0.08, lineHeight: 16, mono: true, caps: true)
    static let row = TextStyle(size: 15, tracking: -0.01, lineHeight: 20)
    static let rowStrong = TextStyle(size: 15, weight: .semibold, tracking: -0.01, lineHeight: 20)
    static let caption = TextStyle(size: 13, lineHeight: 18)
}

extension View {
    func textStyle(_ style: TextStyle, _ color: Color = .white) -> some View {
        font(.system(size: style.size, weight: style.weight, design: style.mono ? .monospaced : .default))
            .italic(style.italic)
            .tracking(style.size * style.tracking)
            .lineHeight(style.lineHeight.map { .exact(points: $0) })
            .textCase(style.caps ? .uppercase : nil)
            .foregroundStyle(color)
    }

    /// The dark card: #0F0F0F with a 1 pt #1F1F1F border.
    func card(radius: CGFloat) -> some View {
        background(Theme.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border))
    }
}

// MARK: Shared pieces

/// The white pill button: 56 pt (60 on iPad), fully rounded, black label.
struct PrimaryButton: View {
    @Environment(\.wide) private var wide
    @Environment(\.isEnabled) private var enabled
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(.button(wide), .black)
                .frame(maxWidth: .infinity)
                .frame(height: wide ? 60 : 56)
                .background(.white.opacity(enabled ? 1 : 0.35), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
    }
}

/// Dims slightly while pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The noboard mark: a wave curling over a line (1024-unit artboard in the design).
struct LogoMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(905, 775))
        path.addCurve(to: p(625, 250), control1: p(845, 600), control2: p(795, 360))
        path.addCurve(to: p(252, 362), control1: p(485, 160), control2: p(292, 210))
        path.addCurve(to: p(364, 475), control1: p(230, 452), control2: p(302, 506))
        path.addCurve(to: p(362, 385), control1: p(414, 449), control2: p(406, 385))
        path.move(to: p(115, 775))
        path.addLine(to: p(300, 775))
        path.addCurve(to: p(565, 432), control1: p(470, 775), control2: p(565, 625))
        return path
    }
}

struct Logo: View {
    var size: CGFloat
    /// Stroke width in the mark's 1024 units: 52 large, 72 at small sizes.
    var weight: CGFloat = 52

    var body: some View {
        LogoMark()
            .stroke(.white, style: StrokeStyle(lineWidth: weight * size / 1024, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// The static orb gradient, for small decorative dots (tips, previews). Live orbs use `Orb`.
struct OrbDot: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: Color(hex: 0xE9F4FA), location: 0),
                .init(color: Color(hex: 0xC8E9F8), location: 0.28),
                .init(color: Theme.accent, location: 0.68),
                .init(color: Color(hex: 0x0A5CB5), location: 1),
            ], center: UnitPoint(x: 0.32, y: 0.3), startRadius: 0, endRadius: size * 0.9))
            .frame(width: size, height: size)
    }
}

/// Small check in a filled circle (success) or an exclamation mark (needs attention).
struct StatusBadge: View {
    var ok: Bool
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: ok ? "checkmark" : "exclamationmark")
            .font(.system(size: size * 0.45, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(ok ? Theme.success : Theme.mic, in: .circle)
    }
}

/// A dot + caps label, e.g. "● MIC ON".
struct DotLabel: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).textStyle(.label, color)
        }
    }
}

/// A two-column spec row between hairlines: caps label left, value right.
struct SpecRow: View {
    var label: String
    var value: String
    var valueColor: Color = .white

    var body: some View {
        HStack {
            Text(label).textStyle(.overline(false), Theme.tertiary)
            Spacer()
            Text(value).textStyle(TextStyle(size: 15, weight: .medium, lineHeight: 20), valueColor)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Theme.border.frame(height: 1) }
    }
}

/// The big blue switch from the mic screen and Home.
struct BigSwitch: View {
    @Binding var isOn: Bool
    var width: CGFloat = 88
    var height: CGFloat = 52

    var body: some View {
        let inset: CGFloat = height > 40 ? 4 : 3
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Theme.accent : Theme.key)
                .frame(width: width, height: height)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .padding(inset)
                }
                .animation(.spring(duration: 0.3), value: isOn)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityRepresentation { Toggle("Microphone", isOn: $isOn) }
    }
}

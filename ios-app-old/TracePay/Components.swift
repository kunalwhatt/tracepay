import SwiftUI
import UIKit

// MARK: - NeoPOP elevated button (CRED style)

enum NPKind {
    case ink, violet, white, danger, lime
    var face: Color { switch self { case .ink: TP.ink; case .violet: TP.violet; case .white: .white; case .danger: TP.bad; case .lime: TP.lime } }
    var right: Color { switch self { case .ink, .violet: TP.violetD; case .white: Color(hex: 0xDCD6EA); case .danger: Color(hex: 0xB42A1B); case .lime: Color(hex: 0x98CC1E) } }
    var bottom: Color { switch self { case .ink, .violet: TP.violetDD; case .white: Color(hex: 0xC6BDDD); case .danger: Color(hex: 0x8A1D12); case .lime: Color(hex: 0x739C10) } }
    var fg: Color { switch self { case .white, .lime: TP.ink; default: .white } }
}

/// Flat face with 4 pt right and bottom "plunk" edges. Pressing pushes the face into the edges.
struct NeoPopStyle: ButtonStyle {
    var kind: NPKind = .ink
    var full = true
    var height: CGFloat = 56
    @Environment(\.isEnabled) private var enabled
    private let d: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        let face = enabled ? kind.face : Color(hex: 0xEEEBF5)
        let er = enabled ? kind.right : Color(hex: 0xE2DDEE)
        let eb = enabled ? kind.bottom : Color(hex: 0xD5CEE6)
        let fg = enabled ? kind.fg : Color(hex: 0xABA5C2)
        return configuration.label
            .font(.lexend(15.5, .medium)).tracking(0.155)
            .foregroundStyle(fg)
            .padding(.horizontal, 24)
            .frame(maxWidth: full ? .infinity : nil)
            .frame(height: height)
            .background(face)
            .overlay { if kind == .white { Rectangle().strokeBorder(TP.hair, lineWidth: 1) } }
            .background(alignment: .topLeading) {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height, e = pressed ? 0 : d
                    ZStack(alignment: .topLeading) {
                        // ::before: bottom edge, skewX(45°)
                        Path { p in
                            p.move(to: CGPoint(x: d / 2, y: h)); p.addLine(to: CGPoint(x: w + d / 2, y: h))
                            p.addLine(to: CGPoint(x: w + d / 2 + e, y: h + e)); p.addLine(to: CGPoint(x: d / 2 + e, y: h + e)); p.closeSubpath()
                        }.fill(eb)
                        // ::after: right edge, skewY(45°)
                        Path { p in
                            p.move(to: CGPoint(x: w, y: d / 2)); p.addLine(to: CGPoint(x: w + e, y: d / 2 + e))
                            p.addLine(to: CGPoint(x: w + e, y: h + d / 2 + e)); p.addLine(to: CGPoint(x: w, y: h + d / 2)); p.closeSubpath()
                        }.fill(er)
                    }
                }
            }
            .offset(x: pressed ? d : 0, y: pressed ? d : 0)
            .padding(.trailing, d).padding(.bottom, d)
            .animation(.easeOut(duration: 0.07), value: pressed)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.tap() } }
    }
}

/// Label helper: optional leading icon and trailing arrow.
struct NPLabel: View {
    let title: String
    var icon: String? = nil
    var arrow = false
    var body: some View {
        HStack(spacing: 10) {
            if let icon { Image(systemName: icon).font(.system(size: 16, weight: .medium)) }
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
            if arrow { Text("→").font(.lexend(18, .light)) }
        }
    }
}

struct NPButton: View {
    let title: String
    var icon: String? = nil
    var kind: NPKind = .ink
    var arrow = false
    var busy = false
    let action: () -> Void
    init(_ title: String, icon: String? = nil, kind: NPKind = .ink, arrow: Bool = false, busy: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.kind = kind; self.arrow = arrow; self.busy = busy; self.action = action
    }
    var body: some View {
        Button(action: action) {
            if busy { ProgressView().tint(kind.fg) } else { NPLabel(title: title, icon: icon, arrow: arrow) }
        }
        .buttonStyle(NeoPopStyle(kind: kind))
        .allowsHitTesting(!busy)
    }
}

// MARK: - Icon button 44 × 44, radius 14, hairline border

struct IconButton: View {
    let icon: String
    var label: String
    var dot = false
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Ico(icon, iconSize).foregroundStyle(TP.ink)
                .frame(width: size, height: size)
                .background(TP.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(TP.hair))
                .overlay(alignment: .topTrailing) {
                    if dot {
                        RoundedRectangle(cornerRadius: 2).fill(TP.bad).frame(width: 8, height: 8)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 2).frame(width: 12, height: 12))
                            .offset(x: -11, y: 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct BackButton: View {
    var icon = Icon.back
    let action: () -> Void
    var body: some View { IconButton(icon: icon, label: icon == Icon.x ? "Close" : "Back", action: action) }
}

/// Header row: back button, centred caption, optional trailing control (prototype `.row.between`).
struct TopRow<Trailing: View>: View {
    var icon = Icon.back
    var title: String = ""
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            BackButton(icon: icon, action: onBack)
            Spacer()
            Text(title).tp(.b2)
            Spacer()
            trailing().frame(minWidth: 44)
        }
    }
}

extension TopRow where Trailing == Color {
    init(icon: String = Icon.back, title: String = "", onBack: @escaping () -> Void) {
        self.icon = icon; self.title = title; self.onBack = onBack; self.trailing = { Color.clear }
    }
}

// MARK: - Inputs: 58 high, radius 16, canvas fill, violet 1.5 pt border on focus

struct FieldBox<Content: View>: View {
    var focused: Bool
    var height: CGFloat = 58
    var fill: Color = TP.canvas
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 18)
            .frame(height: height)
            .background(focused ? TP.white : fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? TP.violet : .clear, lineWidth: 1.5))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct TPTextField: View {
    var icon: String? = nil
    var prefix: String? = nil
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalize: TextInputAutocapitalization = .never
    var fill: Color = TP.canvas
    var trailing: AnyView? = nil
    @FocusState private var focused: Bool
    var body: some View {
        FieldBox(focused: focused, fill: fill) {
            if let icon { Ico(icon, 22).foregroundStyle(TP.faint) }
            if let prefix {
                Text(prefix).font(.lexend(16, .medium)).foregroundStyle(TP.muted).padding(.trailing, 12)
                    .overlay(alignment: .trailing) { Rectangle().fill(TP.hair).frame(width: 1, height: 22) }
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(TP.faint))
                .font(.lexend(16, .medium)).foregroundStyle(TP.ink)
                .keyboardType(keyboard).textContentType(contentType)
                .textInputAutocapitalization(capitalize).autocorrectionDisabled()
                .focused($focused)
            if let trailing { trailing }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

struct TPPasswordField: View {
    let placeholder: String
    @Binding var text: String
    var showEye = true
    var contentType: UITextContentType = .password
    @State private var visible = false
    @FocusState private var focused: Bool
    var body: some View {
        FieldBox(focused: focused) {
            Ico(Icon.lock, 22).foregroundStyle(TP.faint)
            Group {
                if visible { TextField("", text: $text, prompt: Text(placeholder).foregroundColor(TP.faint)) }
                else { SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(TP.faint)) }
            }
            .font(.lexend(16, .medium)).foregroundStyle(TP.ink)
            .textContentType(contentType).textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focused)
            if showEye {
                Button { visible.toggle() } label: { Ico(visible ? Icon.eyeOff : Icon.eye, 22).foregroundStyle(TP.faint) }
                    .buttonStyle(.plain).accessibilityLabel(visible ? "Hide password" : "Show password")
            }
        }
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View { Text(text).tp(.cap).padding(.leading, 2).padding(.bottom, 8) }
}

// MARK: - Segmented switch: canvas track, white selected pill

struct SegmentedSwitch<T: Hashable>: View {
    struct Item { let value: T; let title: String; let icon: String? }
    let items: [Item]
    @Binding var selection: T
    var onTap: ((T) -> Void)? = nil
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i], on = item.value == selection
                Button {
                    if let onTap { onTap(item.value) } else { withAnimation(.easeOut(duration: 0.2)) { selection = item.value } }
                } label: {
                    HStack(spacing: 8) {
                        if let icon = item.icon { Ico(icon, 17) }
                        Text(item.title).font(.lexend(14, .medium))
                    }
                    .foregroundStyle(on ? TP.ink : TP.muted)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background {
                        if on { RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white).shadow(color: TP.ink.opacity(0.08), radius: 5, y: 2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(TP.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Surfaces

struct CardBox<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TP.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(TP.hair))
    }
}

struct SoftBox<Content: View>: View {
    var padding: CGFloat = 20
    var fill: Color = TP.canvas
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Rows separated by a hairline (prototype `.x + .x { border-top }`).
struct Divided<Content: View>: View {
    var inset: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        _VariadicView.Tree(DividedLayout(inset: inset)) { content() }
    }
}

private struct DividedLayout: _VariadicView_MultiViewRoot {
    let inset: CGFloat
    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != children.last?.id { Rectangle().fill(TP.hair).frame(height: 1).padding(.horizontal, inset) }
            }
        }
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var fg: Color
    var bg: Color
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Ico(icon, 14) }
            Text(text).font(.lexend(12, .medium)).num()
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(bg, in: Capsule())
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 46
    var fg: Color = TP.violet
    var bg: Color = TP.violetSoft
    var body: some View {
        Text(Fmt.initials(name))
            .font(.lexend((size / 2.9).rounded(), .semibold))
            .foregroundStyle(fg)
            .frame(width: size, height: size)
            .background(bg, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct TPToggle: View {
    let isOn: Bool
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? TP.violet : TP.hair).frame(width: 52, height: 32)
                Circle().fill(.white).frame(width: 26, height: 26).shadow(color: TP.ink.opacity(0.2), radius: 3, y: 2).padding(3)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Settings row (`.setting`): 40 × 40 icon tile, title + subtitle, trailing content.
struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconFg: Color = TP.violet
    var iconBg: Color = TP.violetSoft
    var titleKind: TextStyleKind = .t2
    var alignTop = false
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: alignTop ? .top : .center, spacing: 14) {
            Ico(icon, 20).foregroundStyle(iconFg)
                .frame(width: 40, height: 40)
                .background(iconBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).tp(titleKind)
                if let subtitle { Text(subtitle).tp(.b2).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

struct Chevron: View { var body: some View { Ico(Icon.chev, 22).foregroundStyle(TP.faint) } }

/// Section heading row (`.shead`).
struct SectionHead: View {
    let title: String
    var link: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).tp(.d3)
            Spacer()
            if let link, let action {
                Button(link, action: action).font(.lexend(13.5, .medium)).foregroundStyle(TP.violet).buttonStyle(.plain)
            }
        }
        .padding(.bottom, 14)
    }
}

/// Category / filter chips (`.chips`).
struct ChipRow: View {
    let items: [(String, String?)]
    @Binding var selected: Int
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                let on = i == selected
                Button { selected = i } label: {
                    HStack(spacing: 7) {
                        if let icon = items[i].1 { Ico(icon, 16) }
                        Text(items[i].0).font(.lexend(13.5, .medium))
                    }
                    .foregroundStyle(on ? .white : TP.ink)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(on ? TP.ink : TP.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height); width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}

// MARK: - Floating tab bar: 16 pt inset, 70 high, radius 24, translucent white; raised violet Scan button

enum MainTab: Hashable { case home, activity, check, profile }

struct FloatingTabBar: View {
    @Binding var tab: MainTab
    let onScan: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            item(.home, Icon.home, "Home")
            item(.activity, Icon.list, "Activity")
            Button(action: onScan) {
                VStack(spacing: 5) {
                    Ico(Icon.scan, 22).foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(TP.violet, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .shadow(color: TP.violet.opacity(0.6), radius: 13, y: 14)
                        .padding(.top, -34)
                    Text("Scan").font(.lexend(10.5, .medium)).foregroundStyle(TP.faint)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan")
            item(.check, Icon.shield, "Check")
            item(.profile, Icon.user, "Profile")
        }
        .padding(.horizontal, 6)
        .frame(height: 70)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(TP.hair))
        .shadow(color: TP.ink.opacity(0.22), radius: 20, y: 20)
        .padding(.horizontal, 16)
    }

    private func item(_ t: MainTab, _ icon: String, _ label: String) -> some View {
        let on = tab == t
        return Button { tab = t; Haptics.tap() } label: {
            VStack(spacing: 4) {
                Ico(icon, 22).foregroundStyle(on ? TP.violet : TP.faint)
                Text(label).font(.lexend(10.5, .medium)).foregroundStyle(on ? TP.ink : TP.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func lock() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Press feedback for plain tiles

struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? scale : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

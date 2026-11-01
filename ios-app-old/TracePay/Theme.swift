import SwiftUI

// MARK: - Colour tokens (BUILD_SPEC §1, prototype :root)

enum TP {
    static let white = Color(hex: 0xFFFFFF)
    static let canvas = Color(hex: 0xF7F5FD)
    static let ink = Color(hex: 0x120A2B)
    static let ink2 = Color(hex: 0x2B2347)
    static let muted = Color(hex: 0x6B6585)
    static let faint = Color(hex: 0xA39DBB)
    static let hair = Color(hex: 0xECE8F5)
    static let violet = Color(hex: 0x5B2EFF)
    static let violetD = Color(hex: 0x3A17C9)
    static let violetDD = Color(hex: 0x24108A)
    static let violetL = Color(hex: 0x8F6BFF)
    static let violetSoft = Color(hex: 0xF1EDFF)
    static let lime = Color(hex: 0xC6FF3D)
    static let good = Color(hex: 0x0A9D5A)
    static let goodBg = Color(hex: 0xE6F6EE)
    static let warn = Color(hex: 0xE59A00)
    static let warnBg = Color(hex: 0xFFF4DC)
    static let warnText = Color(hex: 0x9A6200)
    static let bad = Color(hex: 0xE03E2D)
    static let badBg = Color(hex: 0xFDEAE7)
    static let scrim = Color(hex: 0x0A0618)
    static let scanDark = Color(hex: 0x0B061D)
}

// MARK: - Lexend type scale

enum LexendWeight: String {
    case light = "Lexend-Light", regular = "Lexend-Regular", medium = "Lexend-Medium", semibold = "Lexend-SemiBold", bold = "Lexend-Bold"
}

extension Font {
    static func lexend(_ size: CGFloat, _ weight: LexendWeight = .regular) -> Font { .custom(weight.rawValue, fixedSize: size) }
}

enum TextStyleKind { case d1, d2, d3, t1, t2, b1, b2, cap }

struct TPText: ViewModifier {
    let kind: TextStyleKind
    func body(content: Content) -> some View {
        switch kind {
        case .d1: content.font(.lexend(34, .semibold)).tracking(-1.02).foregroundStyle(TP.ink)
        case .d2: content.font(.lexend(26, .semibold)).tracking(-0.65).foregroundStyle(TP.ink)
        case .d3: content.font(.lexend(20, .semibold)).tracking(-0.4).foregroundStyle(TP.ink)
        case .t1: content.font(.lexend(16, .medium)).tracking(-0.16).foregroundStyle(TP.ink)
        case .t2: content.font(.lexend(14.5, .medium)).foregroundStyle(TP.ink)
        case .b1: content.font(.lexend(14.5)).lineSpacing(4.2).foregroundStyle(TP.muted)
        case .b2: content.font(.lexend(12.5)).lineSpacing(2.4).foregroundStyle(TP.muted)
        case .cap: content.font(.lexend(11, .medium)).tracking(1.54).textCase(.uppercase).foregroundStyle(TP.faint)
        }
    }
}

extension View {
    func tp(_ kind: TextStyleKind) -> some View { modifier(TPText(kind: kind)) }
    /// Tabular figures for amounts.
    func num() -> some View { monospacedDigit() }
}

// MARK: - Screen background: white with a violet glow top-right and a faint lime glow top-left

struct ScreenBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                TP.white
                EllipticalGradient(colors: [TP.violetL.opacity(0.13), TP.violetL.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.7)
                    .frame(width: w * 2.4, height: h * 0.68).position(x: w, y: 0)
                EllipticalGradient(colors: [TP.lime.opacity(0.10), TP.lime.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.7)
                    .frame(width: w * 1.6, height: h * 0.44).position(x: 0, y: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Motion

/// Screen content rises in: 18 pt, 0.55 s, 50 ms stagger (prototype `.rise`).
struct RiseIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55).delay(Double(min(index, 7)) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func rise(_ index: Int) -> some View { modifier(RiseIn(index: index)) }
}

extension Animation {
    static let tpSheet = Animation.timingCurve(0.2, 1, 0.3, 1, duration: 0.45)
    static let tpSpring = Animation.spring(response: 0.42, dampingFraction: 0.68)
}

// MARK: - Brand signature: the logo's four corner squares

struct CornerSquares: ViewModifier {
    var color: Color = TP.violetL
    var size: CGFloat = 10
    var outset: CGFloat = 5
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                let w = geo.size.width + outset * 2, h = geo.size.height + outset * 2
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(color).frame(width: size, height: size)
                            .offset(x: i % 2 == 0 ? 0 : w - size, y: i < 2 ? 0 : h - size)
                    }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .offset(x: -outset, y: -outset)
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func cornerSquares(_ color: Color = TP.violetL, size: CGFloat = 10, outset: CGFloat = 5) -> some View {
        modifier(CornerSquares(color: color, size: size, outset: outset))
    }
}

// MARK: - Logo, drawn as vectors so it stays sharp at every size

/// Cells of the pixel "t" on a 7 × 6 grid (column, row); the last one is the lime pixel.
private let tCells: [(Int, Int)] = [(2, 0), (3, 0), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (2, 3), (3, 3), (5, 4), (6, 4), (2, 4), (3, 4), (3, 5), (4, 5), (5, 5)]

/// The app mark: violet rounded square, white pixel "t", lime pixel and the four light-violet corner squares.
struct BrandMark: View {
    var size: CGFloat = 40
    var corners = true
    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width
            let inset = corners ? s * 0.06 : 0
            let box = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
            ctx.fill(Path(roundedRect: box, cornerRadius: box.width * 0.24, style: .continuous), with: .color(TP.violet))
            let cell = box.width * 0.0846 * 1.06
            let gridW = cell * 7, gridH = cell * 6
            let x0 = box.minX + (box.width - gridW) / 2 + cell * 0.06
            let y0 = box.minY + (box.height - gridH) / 2 + cell * 0.12
            var white = Path()
            for (c, r) in tCells { white.addRect(CGRect(x: x0 + CGFloat(c) * cell, y: y0 + CGFloat(r) * cell, width: cell + 0.4, height: cell + 0.4)) }
            ctx.fill(white, with: .color(.white))
            ctx.fill(Path(CGRect(x: x0 + 6 * cell, y: y0 + 5 * cell, width: cell, height: cell)), with: .color(TP.lime))
            if corners {
                let q = s * 0.105
                for (x, y) in [(0, 0), (s - q, 0), (0, s - q), (s - q, s - q)] {
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: q, height: q), cornerRadius: q * 0.08), with: .color(TP.violetL))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("trace.pay")
    }
}

/// Mark + "trace.pay" word mark (the dot is violet).
struct BrandLockup: View {
    var height: CGFloat = 30
    var body: some View {
        HStack(spacing: height * 0.26) {
            BrandMark(size: height)
            (Text("trace").foregroundColor(TP.ink) + Text(".").foregroundColor(TP.violet) + Text("pay").foregroundColor(TP.ink))
                .font(.lexend(height * 0.72, .semibold)).tracking(-height * 0.02)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("trace.pay")
    }
}

/// The logo's pixel "t" as a faint white texture (balance card, identity card).
struct PixelT: View {
    var body: some View {
        Canvas { ctx, size in
            let cell = min(size.width / 8, size.height / 7)
            var p = Path()
            let px: [(Int, Int)] = [(3, 1), (4, 1), (3, 2), (4, 2), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (3, 4), (4, 4), (3, 5), (4, 5), (6, 5), (7, 5), (4, 6), (5, 6), (6, 6), (7, 6)]
            for (x, y) in px { p.addRect(CGRect(x: (CGFloat(x) - 0.5) * cell, y: (CGFloat(y) - 0.5) * cell, width: cell * 0.94, height: cell * 0.94)) }
            ctx.fill(p, with: .color(.white))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Icons (SF Symbols equivalents of the prototype's stroke icons)

enum Icon {
    static let home = "house", list = "list.bullet", scan = "viewfinder", shield = "checkmark.shield", user = "person", users = "person.2"
    static let send = "paperplane", search = "magnifyingglass", sos = "exclamationmark.circle", zap = "bolt", swap = "arrow.left.arrow.right"
    static let trend = "chart.line.uptrend.xyaxis", flag = "flag", store = "storefront", badge = "checkmark.seal", rupee = "indianrupeesign"
    static let clock = "clock", qmark = "questionmark.circle", doc = "doc.text", globe = "globe", gauge = "gauge.with.dots.needle.33percent"
    static let volume = "speaker.wave.2", bulb = "lightbulb", alert = "exclamationmark.triangle", check = "checkmark", checkc = "checkmark.circle"
    static let circle = "circle", x = "xmark", back = "chevron.left", chev = "chevron.right", up = "arrow.up.right", down = "arrow.down.left"
    static let image = "photo", qr = "qrcode", lock = "lock", mail = "envelope", mobile = "iphone", eye = "eye", eyeOff = "eye.slash"
    static let phone = "phone", bank = "building.columns", brief = "briefcase", hour = "hourglass", face = "faceid", finger = "touchid"
    static let pin = "ellipsis.rectangle", share = "square.and.arrow.up", link = "link", torch = "flashlight.off.fill", torchOn = "flashlight.on.fill"
    static let bell = "bell", plus = "plus", copy = "doc.on.doc", logout = "rectangle.portrait.and.arrow.right", devices = "laptopcomputer.and.iphone"
    static let file = "doc.plaintext", calendar = "calendar"
}

struct Ico: View {
    let name: String
    var size: CGFloat = 22
    var weight: Font.Weight = .regular
    init(_ name: String, _ size: CGFloat = 22, weight: Font.Weight = .regular) { self.name = name; self.size = size; self.weight = weight }
    var body: some View {
        Image(systemName: name).font(.system(size: size * 0.86, weight: weight)).frame(width: size, height: size)
    }
}

// MARK: - Formatting helpers

enum Fmt {
    private static let inr: NumberFormatter = {
        let f = NumberFormatter(); f.locale = Locale(identifier: "en_IN"); f.numberStyle = .decimal
        f.maximumFractionDigits = 2; f.minimumFractionDigits = 0; return f
    }()
    static func rupees(_ value: Double) -> String { "₹" + (inr.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)) }
    static func rupees(_ value: Decimal) -> String { rupees(NSDecimalNumber(decimal: value).doubleValue) }
    static func rupees(_ value: String) -> String { rupees(Double(value) ?? 0) }
    static func compact(_ value: Double) -> String {
        if value >= 100_000 { return String(format: "₹%.1fL", value / 100_000) }
        if value >= 1000 { return String(format: "₹%.1fk", value / 1000) }
        return rupees(value)
    }
    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { " .@_-".contains($0) }).prefix(2)
        let s = parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return s.isEmpty ? "TP" : s
    }
    /// "meera.iyer@tracepay" → "Meera Iyer"
    static func nameFromVPA(_ vpa: String) -> String {
        let local = vpa.split(separator: "@").first.map(String.init) ?? vpa
        let words = local.split(whereSeparator: { "._-".contains($0) }).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? vpa : words.joined(separator: " ")
    }
    static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) ? "EEE" : "d MMM"
        return f.string(from: date)
    }
    static func when(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; f.amSymbol = "am"; f.pmSymbol = "pm"
        return "\(dayLabel(date)), \(f.string(from: date))"
    }
}

// MARK: - Risk bands (0–24 Excellent, 25–49 Average, 50–100 Poor)

enum RiskBand {
    case excellent, average, poor
    init(score: Int) { self = score >= 50 ? .poor : score >= 25 ? .average : .excellent }
    var color: Color { switch self { case .excellent: TP.good; case .average: TP.warn; case .poor: TP.bad } }
    var background: Color { switch self { case .excellent: TP.goodBg; case .average: TP.warnBg; case .poor: TP.badBg } }
    var label: String { switch self { case .excellent: "Excellent"; case .average: "Average"; case .poor: "Poor" } }
    var verdict: String { switch self { case .excellent: "Safe to pay"; case .average: "Be careful"; case .poor: "High risk" } }
}

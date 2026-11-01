import SwiftUI

/// One place for sheets, dialogs and toasts, so at most one of each is ever on screen.
@MainActor
final class OverlayCenter: ObservableObject {
    struct Sheet: Identifiable { let id = UUID(); let body: AnyView; let actions: AnyView? }
    struct DialogButton { let label: String; var kind: NPKind = .ink; var run: (() -> Void)? = nil }
    struct Dialog: Identifiable { let id = UUID(); let title: String; let text: String; let buttons: [DialogButton] }
    struct Toast: Identifiable, Equatable { let id = UUID(); let icon: String; let text: String; static func == (a: Toast, b: Toast) -> Bool { a.id == b.id } }

    @Published private(set) var sheet: Sheet?
    @Published private(set) var dialog: Dialog?
    @Published private(set) var toast: Toast?
    @Published var burstID: UUID?

    func present<B: View>(@ViewBuilder _ body: () -> B) {
        sheet = Sheet(body: AnyView(body()), actions: nil)
    }
    func present<B: View, A: View>(@ViewBuilder _ body: () -> B, @ViewBuilder actions: () -> A) {
        sheet = Sheet(body: AnyView(body()), actions: AnyView(actions()))
    }
    /// Slide the sheet away, then run `then` once it has gone (0.45 s, like the prototype).
    func closeSheet(then: (() -> Void)? = nil) {
        guard sheet != nil else { then?(); return }
        sheet = nil
        if let then { DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { then() } }
    }

    func showDialog(_ title: String, _ text: String, _ buttons: [DialogButton]) {
        dialog = Dialog(title: title, text: text, buttons: buttons)
    }
    func dismissDialog(running button: DialogButton?) {
        dialog = nil
        if let run = button?.run { DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { run() } }
    }

    func showToast(_ text: String, icon: String = Icon.checkc) {
        let t = Toast(icon: icon, text: text)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in if self?.toast == t { self?.toast = nil } }
    }

    func burst() { burstID = UUID() }
}

/// Hosts the overlays above `content`.
struct OverlayHost<Content: View>: View {
    @EnvironmentObject private var overlay: OverlayCenter
    @ViewBuilder var content: () -> Content
    @State private var drag: CGFloat = 0

    var body: some View {
        let dimmed = overlay.sheet != nil || overlay.dialog != nil
        ZStack {
            content()
                .blur(radius: dimmed ? 3 : 0)
                .animation(.easeOut(duration: 0.25), value: dimmed)

            if dimmed {
                TP.scrim.opacity(0.36).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { if overlay.dialog == nil { overlay.closeSheet() } }
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
            }

            if let sheet = overlay.sheet {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SheetView(sheet: sheet, drag: $drag)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }

            if let dialog = overlay.dialog {
                DialogView(dialog: dialog)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                    .zIndex(3)
            }

            if let toast = overlay.toast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Ico(toast.icon, 22).foregroundStyle(TP.lime)
                        Text(toast.text).font(.lexend(14)).foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 15)
                    .background(TP.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: TP.ink.opacity(0.55), radius: 20, y: 20)
                    .padding(.horizontal, 22).padding(.bottom, 108)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(4)
                .accessibilityAddTraits(.isStaticText)
            }

            if let id = overlay.burstID {
                Burst().id(id).allowsHitTesting(false).zIndex(5)
            }
        }
        .animation(.tpSheet, value: overlay.sheet?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: overlay.dialog?.id)
        .animation(.easeOut(duration: 0.3), value: overlay.toast)
    }
}

private struct SheetView: View {
    let sheet: OverlayCenter.Sheet
    @Binding var drag: CGFloat
    @EnvironmentObject private var overlay: OverlayCenter

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Capsule().fill(TP.hair).frame(width: 40, height: 5).padding(.top, 10)
                        .accessibilityHidden(true)
                    ScrollView(showsIndicators: false) {
                        sheet.body.padding(.horizontal, 22).padding(.vertical, 18)
                            .padding(.bottom, sheet.actions == nil ? geo.safeAreaInsets.bottom + 12 : 0)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    if let actions = sheet.actions {
                        VStack(spacing: 12) { actions }
                            .padding(.horizontal, 22).padding(.top, 14)
                            .padding(.bottom, max(30, geo.safeAreaInsets.bottom + 8))
                            .overlay(alignment: .top) { Rectangle().fill(TP.hair).frame(height: 1) }
                    }
                }
                .frame(maxHeight: geo.size.height * 0.93, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background(TP.white, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
                .offset(y: max(0, drag))
                .gesture(DragGesture().onChanged { drag = $0.translation.height }.onEnded { v in
                    if v.translation.height > 120 || v.predictedEndTranslation.height > 300 { overlay.closeSheet() }
                    withAnimation(.tpSpring) { drag = 0 }
                })
            }
        }
    }
}

private struct DialogView: View {
    let dialog: OverlayCenter.Dialog
    @EnvironmentObject private var overlay: OverlayCenter
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dialog.title).tp(.d3).padding(.bottom, 8)
            Text(dialog.text).tp(.b1).padding(.bottom, 22).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                ForEach(dialog.buttons.indices, id: \.self) { i in
                    let b = dialog.buttons[i]
                    NPButton(b.label, kind: b.kind) { overlay.dismissDialog(running: b) }
                }
            }
        }
        .padding(26)
        .background(TP.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TP.ink.opacity(0.4), radius: 40, y: 40)
        .padding(.horizontal, 24)
    }
}

/// Success colour burst: 30 squares flying out from the mark.
struct Burst: View {
    @State private var go = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let bits: [(Color, CGFloat, CGFloat, Double)] = (0..<30).map { i in
        let a = Double.random(in: 0..<(2 * .pi)), r = Double.random(in: 100...230)
        return ([TP.violet, TP.lime, TP.violetL, TP.good][i % 4], CGFloat(cos(a) * r), CGFloat(sin(a) * r), Double.random(in: 0...0.1))
    }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bits.indices, id: \.self) { i in
                    let b = bits[i]
                    RoundedRectangle(cornerRadius: 2).fill(b.0).frame(width: 9, height: 9)
                        .rotationEffect(.degrees(go ? 300 : 0))
                        .offset(x: go ? b.1 : 0, y: go ? b.2 : 0)
                        .opacity(go ? 0 : 1)
                        .animation(.timingCurve(0.1, 0.7, 0.3, 1, duration: 1.2).delay(b.3), value: go)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.3)
        }
        .ignoresSafeArea()
        .opacity(reduceMotion ? 0 : 1)
        .onAppear { go = true }
    }
}

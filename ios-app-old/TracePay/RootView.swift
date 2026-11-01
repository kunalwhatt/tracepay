import SwiftUI

struct RootView: View {
    @StateObject private var overlay = OverlayCenter()
    @State private var mode = 0
    @State private var text = ""
    @State private var pw = ""
    @State private var tab: MainTab = .home
    var body: some View {
        OverlayHost {
            ZStack(alignment: .bottom) {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { BrandLockup(height: 30); Spacer(); IconButton(icon: Icon.bell, label: "Alerts", dot: true) {} }
                        BrandMark(size: 132).frame(maxWidth: .infinity)
                        Text("Pay anyone.\nKnow them first.").tp(.d1)
                        Text("Body copy in muted Lexend.").tp(.b1)
                        Text("Caption").tp(.cap)
                        SegmentedSwitch(items: [.init(value: 0, title: "Mobile", icon: Icon.mobile), .init(value: 1, title: "Email", icon: Icon.mail)], selection: $mode)
                        TPTextField(prefix: "+91", placeholder: "Mobile number", text: $text, keyboard: .phonePad)
                        TPPasswordField(placeholder: "Password", text: $pw)
                        NPButton("Create account", arrow: true) { overlay.showToast("Pressed") }
                        NPButton("Sign in", kind: .white) { overlay.present { Text("Sheet").tp(.d2) } actions: { NPButton("Close") { overlay.closeSheet() } } }
                        NPButton("Continue", arrow: true) {}.disabled(true)
                        RoundedRectangle(cornerRadius: 36).stroke(.gray).frame(width: 200, height: 200).cornerSquares(TP.lime, size: 16, outset: 7).frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 118)
                }
                FloatingTabBar(tab: $tab) {}.padding(.bottom, 4)
            }
        }
        .environmentObject(overlay)
    }
}

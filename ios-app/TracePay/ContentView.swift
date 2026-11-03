import SwiftUI
import Foundation
import LocalAuthentication
import CoreImage.CIFilterBuiltins
import AVFoundation
import UIKit
import PhotosUI
import Vision

// MARK: - Design system (trace.pay 6, light theme)

enum TP {
    static let ink = Color(hex: 0x120A2B)
    static let ink2 = Color(hex: 0x2B2347)
    static let muted = Color(hex: 0x6B6585)
    static let faint = Color(hex: 0xA39DBB)
    static let hair = Color(hex: 0xECE8F5)
    static let canvas = Color(hex: 0xF7F5FD)
    static let violet = Color(hex: 0x5B2EFF)
    static let violetDark = Color(hex: 0x3A17C9)
    static let violetDeep = Color(hex: 0x24108A)
    static let violetLight = Color(hex: 0x8F6BFF)
    static let violetSoft = Color(hex: 0xF1EDFF)
    static let lime = Color(hex: 0xC6FF3D)
    static let blue = Color(hex: 0x1E7BFF)
    static let mint = Color(hex: 0x0A9D5A)
    static let good = Color(hex: 0x0A9D5A)
    static let goodBg = Color(hex: 0xE6F6EE)
    static let warn = Color(hex: 0xE59A00)
    static let warnBg = Color(hex: 0xFFF4DC)
    static let bad = Color(hex: 0xE03E2D)
    static let badBg = Color(hex: 0xFDEAE7)
}

extension Font {
    static func tp(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

enum Haptic {
    private static var enabled: Bool { UserDefaults.standard.object(forKey: "tp.haptics") as? Bool ?? true }
    static func tap() { if enabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func success() { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func error() { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.error) } }
}

func initials(_ text: String) -> String {
    let parts = text.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).prefix(2)
    let value = parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    return value.isEmpty ? "TP" : value
}

func rupees(_ value: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_IN"); f.maximumFractionDigits = 2
    return "₹" + (f.string(from: NSNumber(value: value)) ?? String(value))
}
func rupees(_ value: String) -> String { rupees(Double(value) ?? 0) }

func parseDate(_ s: String) -> Date {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s) ?? .distantPast
}

/// CRED-style elevated button: a flat face with a darker block behind it that the face presses into.
struct NeoButtonStyle: ButtonStyle {
    enum Kind { case ink, violet, white, danger, lime }
    var kind: Kind = .ink
    private var face: Color { switch kind { case .ink: return TP.ink; case .violet: return TP.violet; case .white: return .white; case .danger: return TP.bad; case .lime: return TP.lime } }
    private var edge: Color { switch kind { case .ink, .violet: return TP.violetDeep; case .white: return Color(hex: 0xD6CFE8); case .danger: return Color(hex: 0x8A1D12); case .lime: return Color(hex: 0x739C10) } }
    private var text: Color { kind == .white || kind == .lime ? TP.ink : .white }
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.tp(16, .semibold))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(face)
            .overlay(Rectangle().stroke(kind == .white ? TP.hair : .clear, lineWidth: 1))
            .offset(x: pressed ? 4 : 0, y: pressed ? 4 : 0)
            .background(edge.offset(x: 4, y: 4))
            .padding(.trailing, 4).padding(.bottom, 4)
            .animation(.easeOut(duration: 0.07), value: pressed)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TPField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var prefix: String? = nil
    @State private var reveal = false
    var body: some View {
        HStack(spacing: 12) {
            if let prefix {
                Text(prefix).font(.tp(16, .medium)).foregroundStyle(TP.muted)
                Rectangle().fill(TP.hair).frame(width: 1, height: 22)
            } else {
                Image(systemName: icon).foregroundStyle(TP.faint).frame(width: 22)
            }
            Group {
                if secure && !reveal { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .font(.tp(16, .medium)).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
            if secure {
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye").foregroundStyle(TP.faint) }
                    .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 18).frame(height: 58)
        .background(TP.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SegmentSwitch: View {
    let options: [(String, String)]   // (icon, label)
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button { withAnimation(.spring(response: 0.3)) { selection = i } } label: {
                    Label(options[i].1, systemImage: options[i].0).font(.tp(14, .medium))
                        .foregroundStyle(selection == i ? TP.ink : TP.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection == i ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .shadow(color: selection == i ? TP.ink.opacity(0.08) : .clear, radius: 6, y: 2)
                }
            }
        }
        .padding(4).background(TP.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 46
    var body: some View {
        Text(initials(name)).font(.tp(size / 2.9, .semibold)).foregroundStyle(TP.violet)
            .frame(width: size, height: size)
            .background(TP.violetSoft, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct CardBox<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.hair, lineWidth: 1))
    }
}

/// The logo's four corner squares, drawn just outside a view.
struct CornerSquares: ViewModifier {
    var color: Color = TP.violetLight
    var size: CGFloat = 10
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { g in
                let s = size, w = g.size.width, h = g.size.height
                ZStack {
                    Rectangle().fill(color).frame(width: s, height: s).position(x: -s / 2 + 3, y: -s / 2 + 3)
                    Rectangle().fill(color).frame(width: s, height: s).position(x: w + s / 2 - 3, y: -s / 2 + 3)
                    Rectangle().fill(color).frame(width: s, height: s).position(x: -s / 2 + 3, y: h + s / 2 - 3)
                    Rectangle().fill(color).frame(width: s, height: s).position(x: w + s / 2 - 3, y: h + s / 2 - 3)
                }
            }.allowsHitTesting(false)
        )
    }
}
extension View { func cornerSquares(_ color: Color = TP.violetLight, size: CGFloat = 10) -> some View { modifier(CornerSquares(color: color, size: size)) } }

struct ScreenBackground: View {
    var body: some View {
        ZStack {
            Color.white
            RadialGradient(colors: [TP.violetLight.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 380)
            RadialGradient(colors: [TP.lime.opacity(0.12), .clear], center: .topLeading, startRadius: 10, endRadius: 260)
        }.ignoresSafeArea()
    }
}

struct Caption: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.tp(11, .medium)).tracking(1.4).foregroundStyle(TP.faint) }
}

// MARK: - Device lock (only the phone's own Face ID / Touch ID / passcode)

enum DeviceLock {
    static var method: (name: String, icon: String) {
        let c = LAContext(); var e: NSError?
        if c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e) {
            switch c.biometryType {
            case .faceID: return ("Face ID", "faceid")
            case .touchID: return ("Touch ID", "touchid")
            case .opticID: return ("Optic ID", "opticid")
            default: break
            }
        }
        return ("Device passcode", "lock.fill")
    }
    static var isAvailable: Bool { var e: NSError?; return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &e) }
    /// Returns true when the person authenticates. If the phone has no lock at all, returns true (nothing to check).
    static func authenticate(_ reason: String) async -> Bool {
        let c = LAContext(); var e: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &e) else { return true }
        do { return try await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) } catch { return false }
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tp.lock") private var lockOn = true
    @State private var locked = false
    @State private var showAuth = false
    @State private var loadError: String?

    var body: some View {
        ZStack {
            if session.token == nil {
                if (CredentialVault.hasCredential || LocalUnlockStore.hasSavedSession) && !showAuth {
                    UnlockScreen(onUseAnother: { session.clearSavedCredentials(); showAuth = true })
                } else {
                    AuthFlow()
                }
            } else if !session.profileLoaded {
                LoadingScreen(error: loadError, retry: { Task { await loadProfile() } }, signOut: { session.clearSavedCredentials() })
                    .task { await loadProfile() }
            } else if session.pilotProfile == nil {
                SetupFlow()
            } else {
                MainTabs()
            }
            if locked && session.token != nil { LockOverlay { locked = false }.transition(.opacity) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && lockOn && session.token != nil && session.pilotProfile != nil { locked = true }
        }
    }

    @MainActor private func loadProfile() async {
        loadError = nil
        do { try await session.refreshPilotProfile() } catch { loadError = error.localizedDescription }
    }
}

struct LoadingScreen: View {
    let error: String?
    let retry: () -> Void
    let signOut: () -> Void
    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 18) {
                Image("TPMark").resizable().scaledToFit().frame(width: 84, height: 84)
                if let error {
                    Text("Couldn't load your account").font(.tp(20, .semibold)).foregroundStyle(TP.ink)
                    Text(error).font(.tp(14)).foregroundStyle(TP.muted).multilineTextAlignment(.center)
                    Button("Try again", action: retry).buttonStyle(NeoButtonStyle())
                    Button("Sign out", action: signOut).font(.tp(15, .medium)).foregroundStyle(TP.violet)
                } else {
                    ProgressView().tint(TP.violet)
                }
            }.padding(28)
        }
    }
}

/// Shown when a saved account exists: unlock with the phone's own lock.
struct UnlockScreen: View {
    @EnvironmentObject private var session: TracePaySession
    let onUseAnother: () -> Void
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                Spacer()
                Image("TPMark").resizable().scaledToFit().frame(width: 112, height: 112)
                    .shadow(color: TP.violet.opacity(0.3), radius: 22, y: 14)
                Text("Welcome back").font(.tp(28, .semibold)).foregroundStyle(TP.ink).padding(.top, 28)
                Text(LocalUnlockStore.savedEmail?.replacingOccurrences(of: "@mobile.tracepay.app", with: "") ?? "").font(.tp(15)).foregroundStyle(TP.muted).padding(.top, 6)
                if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad).multilineTextAlignment(.center).padding(.top, 14) }
                Spacer()
                VStack(spacing: 14) {
                    Button { Task { await unlock() } } label: {
                        if busy { ProgressView().tint(.white) } else { Label("Unlock with \(DeviceLock.method.name)", systemImage: DeviceLock.method.icon) }
                    }.buttonStyle(NeoButtonStyle())
                    Button("Use a different account", action: onUseAnother).font(.tp(15, .medium)).foregroundStyle(TP.violet)
                }
            }.padding(24)
        }
        .task { await unlock() }
    }
    @MainActor private func unlock() async {
        guard !busy else { return }
        busy = true; message = ""; defer { busy = false }
        if CredentialVault.hasCredential {
            guard let cred = await CredentialVault.read(reason: "Unlock trace.pay") else { message = "Not unlocked. Try again."; return }
            do { try await session.signIn(identifier: cred.identifier, password: cred.password); Haptic.success() }
            catch { message = error.localizedDescription }
            return
        }
        guard await DeviceLock.authenticate("Unlock trace.pay") else { message = "Not unlocked. Try again."; return }
        do { try await session.restoreSavedSession() } catch { message = "Your session ended. Sign in again."; LocalUnlockStore.clearToken() }
    }
}

struct LockOverlay: View {
    let onUnlock: () -> Void
    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 18) {
                Image("TPMark").resizable().scaledToFit().frame(width: 96, height: 96)
                Text("trace.pay is locked").font(.tp(22, .semibold)).foregroundStyle(TP.ink)
                Button { Task { await unlock() } } label: { Label("Unlock with \(DeviceLock.method.name)", systemImage: DeviceLock.method.icon) }
                    .buttonStyle(NeoButtonStyle()).padding(.horizontal, 30)
            }
        }
        .task { await unlock() }
    }
    @MainActor private func unlock() async { if await DeviceLock.authenticate("Unlock trace.pay") { onUnlock() } }
}

// MARK: - Sign in / Sign up

struct AuthFlow: View {
    enum Screen { case welcome, signIn, signUp }
    @State private var screen: Screen = .welcome
    var body: some View {
        ZStack {
            switch screen {
            case .welcome: WelcomeScreen(onCreate: { screen = .signUp }, onSignIn: { screen = .signIn })
            case .signIn: SignInScreen(onBack: { screen = .welcome })
            case .signUp: SignUpScreen(onBack: { screen = .welcome })
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
    }
}

struct WelcomeScreen: View {
    let onCreate: () -> Void
    let onSignIn: () -> Void
    @State private var float = false
    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Image("TPMark").resizable().scaledToFit().frame(width: 128, height: 128)
                            .shadow(color: TP.violet.opacity(0.32), radius: 24, y: 16)
                            .offset(y: float ? -6 : 0)
                            .padding(.top, 48)
                        Image("TPLockup").resizable().scaledToFit().frame(height: 34).padding(.top, 26)
                        Text("Pay anyone.\nKnow them first.").font(.tp(32, .semibold)).foregroundStyle(TP.ink)
                            .multilineTextAlignment(.center).padding(.top, 24)
                        Text("Every UPI ID is checked for scams before your money leaves, on any app.")
                            .font(.tp(15)).foregroundStyle(TP.muted).multilineTextAlignment(.center).padding(.top, 10).padding(.horizontal, 10)
                        VStack(spacing: 12) {
                            feature("checkmark.shield", "Risk score in one second", "Before every payment")
                            feature("qrcode.viewfinder", "Works with any UPI QR", "Google Pay, PhonePe, Paytm and more")
                            feature(DeviceLock.method.icon, "Protected by your device lock", "Face ID, fingerprint, PIN or passcode")
                        }.padding(.top, 30)
                    }.padding(.horizontal, 24)
                }
                VStack(spacing: 12) {
                    Button(action: onCreate) { Label("Create account", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle()) }.buttonStyle(NeoButtonStyle())
                    Button("Sign in", action: onSignIn).buttonStyle(NeoButtonStyle(kind: .white))
                }.padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { float = true } }
    }
    private func feature(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(TP.violet)
                .frame(width: 44, height: 44).background(TP.violetSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tp(15, .medium)).foregroundStyle(TP.ink)
                Text(sub).font(.tp(13)).foregroundStyle(TP.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 8) { configuration.title; configuration.icon } }
}

struct BackHeader: View {
    let onBack: () -> Void
    var trailing: String? = nil
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(TP.ink)
                    .frame(width: 44, height: 44).background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TP.hair))
            }.accessibilityLabel("Back")
            Spacer()
            if let trailing { Text(trailing).font(.tp(13)).foregroundStyle(TP.muted) }
        }
    }
}

struct SignInScreen: View {
    @EnvironmentObject private var session: TracePaySession
    let onBack: () -> Void
    @State private var method = 0
    @State private var mobile = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message = ""
    @State private var showForgot = false
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackHeader(onBack: onBack)
                    Image("TPMark").resizable().scaledToFit().frame(width: 52, height: 52).padding(.top, 28)
                    Text("Welcome back").font(.tp(32, .semibold)).foregroundStyle(TP.ink).padding(.top, 20)
                    Text("Sign in with your mobile number or email.").font(.tp(15)).foregroundStyle(TP.muted).padding(.top, 6)
                    SegmentSwitch(options: [("iphone", "Mobile"), ("envelope", "Email")], selection: $method).padding(.top, 24)
                    VStack(spacing: 12) {
                        if method == 0 { TPField(icon: "iphone", placeholder: "10-digit mobile number", text: $mobile, keyboard: .numberPad, prefix: "+91") }
                        else { TPField(icon: "envelope", placeholder: "Email", text: $email, keyboard: .emailAddress) }
                        TPField(icon: "lock", placeholder: "Password", text: $password, secure: true)
                    }.padding(.top, 16)
                    Button("Forgot password?") { showForgot = true }.font(.tp(14.5, .medium)).foregroundStyle(TP.violet)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 12)
                    if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad).padding(.top, 12) }
                }.padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await signIn() } } label: { if busy { ProgressView().tint(.white) } else { Text("Sign in") } }
                    .buttonStyle(NeoButtonStyle()).disabled(busy || password.isEmpty).padding(.horizontal, 24).padding(.vertical, 12).background(.white)
            }
        }
        .sheet(isPresented: $showForgot) { ForgotPasswordSheet() }
    }
    @MainActor private func signIn() async {
        busy = true; message = ""; defer { busy = false }
        let id = method == 0 ? mobile.filter(\.isNumber) : email
        guard !id.isEmpty else { message = method == 0 ? "Enter your mobile number." : "Enter your email."; return }
        do {
            try await session.signIn(identifier: id, password: password)
            Haptic.success()
        } catch { message = error.localizedDescription; Haptic.error() }
    }
}

struct SignUpScreen: View {
    @EnvironmentObject private var session: TracePaySession
    let onBack: () -> Void
    @AppStorage("tp.pendingName") private var pendingName = ""
    @State private var step = 1
    @State private var name = ""
    @State private var mobile = ""
    @State private var email = ""
    @State private var emailCode = ""
    @State private var smsCode = ""
    @State private var emailTicket = ""
    @State private var smsTicket = ""
    @State private var resendIn = 0
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var message = ""
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var rules: [(String, Bool)] {
        [("8+ characters", password.count >= 8), ("Uppercase letter", password.contains(where: \.isUppercase)),
         ("A number", password.contains(where: \.isNumber)), ("A symbol", password.contains(where: { !$0.isLetter && !$0.isNumber }))]
    }
    private var strength: Int { rules.filter { $0.1 }.count }
    private var cleanMobile: String { String(mobile.filter(\.isNumber).suffix(10)) }
    private var detailsOK: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && cleanMobile.count == 10 && email.contains("@") && email.contains(".") }
    private var verified: Bool { !emailTicket.isEmpty && !smsTicket.isEmpty }
    private var passwordOK: Bool { strength == 4 && password == confirm }
    private var titles: [(String, String, String)] { [("Create account", "Let's set you up", "Your name, mobile number and email. We'll verify both."),
        ("Verify", "Enter your OTPs", "We sent a one-time password (OTP) to +91 \(cleanMobile) and another to \(email)."),
        ("Security", "Create a password", "You'll use it to sign in on a new phone.")] }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackHeader(onBack: { if step == 1 { onBack() } else { step -= 1 } }, trailing: "Step \(step) of 3")
                    ProgressBar(step: step, total: 3).padding(.top, 20)
                    Caption(text: titles[step - 1].0).padding(.top, 24)
                    Text(titles[step - 1].1).font(.tp(32, .semibold)).foregroundStyle(TP.ink).padding(.top, 8)
                    Text(titles[step - 1].2).font(.tp(15)).foregroundStyle(TP.muted).padding(.top, 6).padding(.bottom, 22)
                    if step == 1 {
                        VStack(spacing: 12) {
                            TPField(icon: "person", placeholder: "Full name", text: $name)
                            TPField(icon: "iphone", placeholder: "10-digit mobile number", text: $mobile, keyboard: .numberPad, prefix: "+91")
                            TPField(icon: "envelope", placeholder: "Email", text: $email, keyboard: .emailAddress)
                        }
                        Text("By continuing you agree to the Terms and Privacy Policy.").font(.tp(12.5)).foregroundStyle(TP.muted).padding(.top, 14)
                    } else if step == 2 {
                        VStack(alignment: .leading, spacing: 22) {
                            codeBlock(icon: "message.fill", title: "SMS OTP", sub: "+91 \(cleanMobile)", code: $smsCode, done: !smsTicket.isEmpty)
                            codeBlock(icon: "envelope.fill", title: "Email OTP", sub: email, code: $emailCode, done: !emailTicket.isEmpty)
                            Button { Task { await sendCodes() } } label: {
                                Text(resendIn > 0 ? "Resend OTP in \(resendIn)s" : "Resend OTP").font(.tp(14.5, .medium)).foregroundStyle(resendIn > 0 ? TP.faint : TP.violet)
                            }.disabled(resendIn > 0 || busy).frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 12) {
                            TPField(icon: "lock", placeholder: "Password", text: $password, secure: true)
                            HStack(spacing: 6) { ForEach(0..<4, id: \.self) { i in Capsule().fill(i < strength ? [TP.bad, TP.warn, TP.violetLight, TP.good][max(0, strength - 1)] : TP.hair).frame(height: 5) } }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                                ForEach(rules.indices, id: \.self) { i in Label(rules[i].0, systemImage: rules[i].1 ? "checkmark.circle.fill" : "circle").font(.tp(13)).foregroundStyle(rules[i].1 ? TP.good : TP.faint) }
                            }
                            TPField(icon: "lock", placeholder: "Confirm password", text: $confirm, secure: true)
                        }
                    }
                    if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad).padding(.top, 12) }
                }.padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await next() } } label: {
                    if busy { ProgressView().tint(.white) } else { Label(step == 1 ? "Send one-time password (OTP)" : step == 2 ? "Continue" : "Create account", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle()) }
                }
                .buttonStyle(NeoButtonStyle())
                .disabled(busy || !(step == 1 ? detailsOK : step == 2 ? verified : passwordOK))
                .opacity((step == 1 ? detailsOK : step == 2 ? verified : passwordOK) ? 1 : 0.5)
                .padding(.horizontal, 24).padding(.vertical, 12).background(.white)
            }
        }
        .onReceive(tick) { _ in if resendIn > 0 { resendIn -= 1 } }
        .onChange(of: smsCode) { _, v in if v.count == 6 && smsTicket.isEmpty { Task { await check("sms", v) } } }
        .onChange(of: emailCode) { _, v in if v.count == 6 && emailTicket.isEmpty { Task { await check("email", v) } } }
    }

    private func codeBlock(icon: String, title: String, sub: String, code: Binding<String>, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.seal.fill" : icon).font(.system(size: 16)).foregroundStyle(done ? TP.good : TP.violet)
                    .frame(width: 36, height: 36).background(done ? TP.goodBg : TP.violetSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(done ? "\(title) verified" : title).font(.tp(15, .semibold)).foregroundStyle(done ? TP.good : TP.ink)
                    Text(sub).font(.tp(12.5)).foregroundStyle(TP.muted)
                }
            }
            if !done { OTPCodeField(code: code) }
        }
    }

    @MainActor private func sendCodes() async {
        busy = true; message = ""; defer { busy = false }
        do {
            try await session.startVerification(channel: "sms", target: cleanMobile, name: name)
            try await session.startVerification(channel: "email", target: email, name: name)
            resendIn = 30
        } catch { message = error.localizedDescription }
    }
    @MainActor private func check(_ channel: String, _ code: String) async {
        message = ""
        do {
            let t = try await session.checkVerification(channel: channel, target: channel == "sms" ? cleanMobile : email, code: code)
            if channel == "sms" { smsTicket = t } else { emailTicket = t }
            Haptic.success()
        } catch {
            message = error.localizedDescription; Haptic.error()
            if channel == "sms" { smsCode = "" } else { emailCode = "" }
        }
    }
    @MainActor private func next() async {
        message = ""
        if step == 1 { await sendCodes(); if message.isEmpty { withAnimation { step = 2 } }; return }
        if step == 2 { withAnimation { step = 3 }; return }
        busy = true; defer { busy = false }
        do {
            pendingName = name.trimmingCharacters(in: .whitespaces)
            try await session.signUpVerified(email: email, mobile: cleanMobile, password: password, emailTicket: emailTicket, smsTicket: smsTicket)
            Haptic.success()
        } catch { message = error.localizedDescription; Haptic.error() }
    }
}

struct ProgressBar: View {
    let step: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { i in Capsule().fill(i <= step ? TP.violet : TP.hair).frame(height: 4) }
        }.animation(.easeOut, value: step)
    }
}

// MARK: - Profile setup (about you → live selfie → device lock)

struct SetupFlow: View {
    @EnvironmentObject private var session: TracePaySession
    @AppStorage("tp.pendingName") private var pendingName = ""
    @AppStorage("tp.lock") private var lockOn = true
    @State private var step = 1
    @State private var name = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -21, to: Date()) ?? Date()
    @State private var gender = "Prefer not to say"
    @State private var photo: Data?
    @State private var showCamera = false
    @State private var busy = false
    @State private var message = ""
    @State private var code = ""
    @State private var resendIn = 0
    private let genders = ["Male", "Female", "Non-binary", "Prefer not to say"]
    private let resendTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// Email sign-ups finish with a one-time code; mobile sign-ups have no email to verify.
    /// Email and mobile are verified during sign-up now; older unverified accounts verify from the Home banner.
    private var needsEmail: Bool { false }
    private var total: Int { needsEmail ? 4 : 3 }
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Spacer(); Text("Step \(step) of \(total)").font(.tp(13)).foregroundStyle(TP.muted) }.frame(height: 44)
                    ProgressBar(step: step, total: total).padding(.top, 8)
                    Caption(text: ["About you", "Identity", "Device lock", "Verify email"][step - 1]).padding(.top, 24)
                    Text(["Tell us about you", "Take a live selfie", "Lock trace.pay with your phone", "Check your email"][step - 1]).font(.tp(30, .semibold)).foregroundStyle(TP.ink).padding(.top, 8)
                    Text(["Used for your trace.pay profile.", "Encrypted and only checked for one clear face.", "We use the lock you already have. Nothing new to remember.", "We sent a 6-digit code to \(session.email ?? "your email")."][step - 1])
                        .font(.tp(15)).foregroundStyle(TP.muted).padding(.top, 6)
                    Group {
                        if step == 1 { aboutStep } else if step == 2 { selfieStep } else if step == 3 { lockStep } else { emailStep }
                    }.padding(.top, 24)
                    if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad).padding(.top, 12) }
                }.padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await next() } } label: {
                    if busy { ProgressView().tint(.white) } else { Text(step == 3 ? "Turn on \(DeviceLock.method.name)" : step == 4 ? "Verify and finish" : "Continue") }
                }
                .buttonStyle(NeoButtonStyle())
                .disabled(busy || (step == 1 && name.count < 2) || (step == 2 && photo == nil) || (step == 4 && code.count != 6))
                .opacity((step == 1 && name.count < 2) || (step == 2 && photo == nil) || (step == 4 && code.count != 6) ? 0.5 : 1)
                .padding(.horizontal, 24).padding(.vertical, 12).background(.white)
            }
        }
        .onAppear { if name.isEmpty { name = pendingName } }
        .onReceive(resendTick) { _ in if resendIn > 0 { resendIn -= 1 } }
        .fullScreenCover(isPresented: $showCamera) {
            LiveSelfieView(onCaptured: { data in photo = data; showCamera = false; Haptic.success() }, onCancel: { showCamera = false })
        }
    }
    private var aboutStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            TPField(icon: "person", placeholder: "Full name", text: $name)
            HStack {
                Image(systemName: "calendar").foregroundStyle(TP.faint).frame(width: 22)
                Text("Date of birth").font(.tp(16, .medium)).foregroundStyle(TP.muted)
                Spacer()
                DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date).labelsHidden().tint(TP.violet)
            }.padding(.horizontal, 18).frame(height: 58).background(TP.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Caption(text: "Gender").padding(.top, 6)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(genders, id: \.self) { g in
                    Button { gender = g } label: {
                        HStack {
                            Text(g).font(.tp(14.5, .medium))
                            Spacer()
                            Image(systemName: gender == g ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(gender == g ? TP.violet : TP.ink2)
                        .padding(.horizontal, 14).frame(height: 50)
                        .background(gender == g ? TP.violetSoft : TP.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }
    private var selfieStep: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [TP.violetSoft, Color.white], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(TP.hair))
                if let photo, let img = UIImage(data: photo) {
                    VStack(spacing: 12) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 170, height: 214).clipShape(Ellipse())
                            .overlay(Ellipse().stroke(TP.good, lineWidth: 4)).shadow(color: TP.good.opacity(0.25), radius: 16, y: 8)
                        Label("Clear face captured", systemImage: "checkmark.seal.fill").font(.tp(14, .semibold)).foregroundStyle(TP.good)
                            .padding(.horizontal, 12).padding(.vertical, 6).background(TP.goodBg, in: Capsule())
                    }
                } else {
                    VStack(spacing: 14) {
                        ZStack {
                            Ellipse().stroke(TP.violet.opacity(0.35), style: StrokeStyle(lineWidth: 3, dash: [9, 7])).frame(width: 150, height: 190)
                            Image(systemName: "face.smiling").font(.system(size: 64, weight: .light)).foregroundStyle(TP.violet)
                        }
                        Text("Your face goes inside the oval").font(.tp(14, .medium)).foregroundStyle(TP.ink2)
                    }
                }
            }.frame(height: 300)
            VStack(alignment: .leading, spacing: 12) {
                tip("sun.max.fill", "Good light", "Face a window or a lamp; avoid strong light behind you.")
                tip("eyeglasses", "Nothing covering your face", "Take off sunglasses, masks and caps.")
                tip("hand.raised.fill", "Hold still", "The photo is taken automatically when your face is clear.")
                tip("lock.fill", "Private", "Encrypted, and only checked for one clear face.")
            }.padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.hair))
            Button { showCamera = true } label: { Label(photo == nil ? "Open camera" : "Retake selfie", systemImage: "camera.fill") }
                .buttonStyle(NeoButtonStyle(kind: photo == nil ? .violet : .white))
        }
    }
    private func tip(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(TP.violet).frame(width: 32, height: 32).background(TP.violetSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.tp(14, .semibold)).foregroundStyle(TP.ink); Text(text).font(.tp(12.5)).foregroundStyle(TP.muted) }
            Spacer(minLength: 0)
        }
    }
    private var lockStep: some View {
        VStack(spacing: 18) {
            Image(systemName: DeviceLock.method.icon).font(.system(size: 64, weight: .light)).foregroundStyle(.white)
                .frame(width: 140, height: 140)
                .background(LinearGradient(colors: [TP.violet, TP.violetDeep], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
                .shadow(color: TP.violet.opacity(0.45), radius: 24, y: 14)
                .cornerSquares(TP.lime, size: 12)
                .padding(.vertical, 10)
            HStack(spacing: 10) {
                method("faceid", "Face ID", DeviceLock.method.icon == "faceid")
                method("touchid", "Touch ID", DeviceLock.method.icon == "touchid")
                method("lock.fill", "Passcode", DeviceLock.method.icon == "lock.fill")
            }
            Text("This iPhone uses \(DeviceLock.method.name). You'll use it to open trace.pay and confirm payments.")
                .font(.tp(13)).foregroundStyle(TP.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
    private var emailStep: some View {
        VStack(spacing: 18) {
            ZStack {
                TextField("", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .foregroundStyle(.clear).tint(.clear).frame(height: 64)
                    .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        let chars = Array(code)
                        Text(i < chars.count ? String(chars[i]) : "").font(.tp(28, .semibold)).foregroundStyle(TP.ink)
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(TP.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(i == chars.count ? TP.violet : .clear, lineWidth: 1.5))
                    }
                }.allowsHitTesting(false)
            }
            Button { Task { await sendCode() } } label: {
                Text(resendIn > 0 ? "Resend code in \(resendIn)s" : "Resend code").font(.tp(14.5, .medium)).foregroundStyle(resendIn > 0 ? TP.faint : TP.violet)
            }.disabled(resendIn > 0 || busy)
            Label("Didn't get it? Check spam, or wait a minute and resend.", systemImage: "envelope.badge").font(.tp(13)).foregroundStyle(TP.muted)
        }
    }
    @MainActor private func sendCode() async {
        message = ""
        do { try await session.sendEmailCode(name: name); resendIn = 30 } catch { message = error.localizedDescription }
    }
    private func method(_ icon: String, _ label: String, _ on: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(TP.violet)
            Text(label).font(.tp(12.5, .medium)).foregroundStyle(on ? TP.ink : TP.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(on ? TP.violetSoft : TP.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? TP.violet : .clear, lineWidth: 1.5))
    }
    @MainActor private func next() async {
        message = ""
        if step < 3 { withAnimation { step += 1 }; return }
        if step == 3 {
            guard await DeviceLock.authenticate("Turn on device lock for trace.pay") else { message = "Device lock wasn't confirmed. Try again."; return }
            if needsEmail {
                busy = true; await sendCode(); busy = false
                if message.isEmpty { withAnimation { step = 4 } }
                return
            }
        }
        guard let photo else { step = 2; return }
        busy = true; defer { busy = false }
        if step == 4 {
            do { try await session.verifyEmailCode(code) } catch { message = error.localizedDescription; Haptic.error(); return }
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        do {
            try await session.createPilotProfile(fullName: name, dateOfBirth: f.string(from: dob), gender: gender, photoData: photo, consentProfile: true, consentLedger: true)
            lockOn = true; pendingName = ""; Haptic.success()
        } catch { message = error.localizedDescription; Haptic.error() }
    }
}

// MARK: - Main app

enum MainTab: Hashable { case home, activity, scan, check, profile }
struct PayRoute: Identifiable { let id = UUID(); let vpa: String }
struct ExternalRoute: Identifiable { let id = UUID(); let raw: String }
struct TextRoute: Identifiable { let id = UUID(); let value: String }

struct ActivityItem: Identifiable, Hashable {
    let id: String; let title: String; let ref: String; let via: String; let amount: Double; let incoming: Bool
    let status: String; let band: String?; let score: Int?; let date: Date
}

@MainActor final class AppData: ObservableObject {
    @Published var external: [ExternalPaymentItem] = []
    func items(_ session: TracePaySession) -> [ActivityItem] {
        let me = session.pilotProfile?.vpa_id ?? ""
        let local = session.transfers.map { t in
            ActivityItem(id: "tp-\(t.id)", title: t.sender_vpa == me ? t.receiver_vpa : t.sender_vpa, ref: t.transfer_ref, via: "trace.pay",
                         amount: Double(t.amount) ?? 0, incoming: t.receiver_vpa == me, status: t.status, band: nil, score: nil, date: parseDate(t.created_at))
        }
        let ext = external.map { e in
            ActivityItem(id: "ext-\(e.id)", title: e.payee_name ?? e.payee_vpa, ref: e.payee_vpa, via: e.app.capitalized, amount: Double(e.amount) ?? 0,
                         incoming: false, status: e.status, band: e.risk_band, score: e.risk_score, date: parseDate(e.created_at))
        }
        return (local + ext).sorted { $0.date > $1.date }
    }
    func refresh(_ session: TracePaySession) async {
        try? await session.refreshPilotWallet()
        try? await session.refreshPilotTransfers()
        if let ext = try? await session.externalPayments() { external = ext }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var session: TracePaySession
    @StateObject private var data = AppData()
    @State private var tab: MainTab = .home
    @State private var lastTab: MainTab = .home
    @State private var showScanner = false
    @State private var payRoute: PayRoute?
    @State private var externalRoute: ExternalRoute?
    @State private var showHelp = false
    @State private var showQR = false
    @State private var emailStatus: EmailStatus?
    @State private var showVerify = false
    private let ticker = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    /// Email accounts can't pay until the email is verified (the server enforces this too).
    private var mustVerify: Bool { emailStatus.map { $0.required && !$0.verified } ?? false }
    private func pay(_ vpa: String) { if mustVerify { showVerify = true } else { payRoute = PayRoute(vpa: vpa) } }
    private func payExternal(_ raw: String) { if mustVerify { showVerify = true } else { externalRoute = ExternalRoute(raw: raw) } }

    var body: some View {
        TabView(selection: $tab) {
            HomeScreen(data: data, mustVerify: mustVerify, onVerify: { showVerify = true }, onPay: { pay($0) }, onScan: { showScanner = true }, onCheck: { tab = .check },
                       onHelp: { showHelp = true }, onQR: { showQR = true }, onHistory: { tab = .activity })
                .tabItem { Label("Home", systemImage: "house") }.tag(MainTab.home)
            ActivityScreen(data: data).tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }.tag(MainTab.activity)
            Color.white.tabItem { Label("Scan", systemImage: "qrcode.viewfinder") }.tag(MainTab.scan)
            CheckScreen().tabItem { Label("Check", systemImage: "checkmark.shield") }.tag(MainTab.check)
            ProfileScreen(onQR: { showQR = true }, onHelp: { showHelp = true }).tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(MainTab.profile)
        }
        .tint(TP.violet)
        .onChange(of: tab) { old, new in
            if new == .scan { showScanner = true; tab = old } else { lastTab = new }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScanScreen(onTracePay: { id in showScanner = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pay(id) } },
                       onExternal: { raw in showScanner = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { payExternal(raw) } },
                       onClose: { showScanner = false }, onMyQR: { showScanner = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showQR = true } })
        }
        .fullScreenCover(item: $payRoute) { r in PayMemberScreen(prefill: r.vpa) { payRoute = nil; Task { await data.refresh(session) } } }
        .fullScreenCover(item: $externalRoute) { r in ExternalPayScreen(raw: r.raw) { externalRoute = nil; Task { await data.refresh(session) } } }
        .sheet(isPresented: $showHelp) { HelpSheet() }
        .sheet(isPresented: $showQR) { MyQRSheet() }
        .sheet(isPresented: $showVerify) {
            VerifyEmailSheet(email: emailStatus?.email ?? session.email ?? "") { Task { emailStatus = try? await session.emailStatus() } }
        }
        .task { await data.refresh(session); emailStatus = try? await session.emailStatus() }
        .onReceive(ticker) { _ in Task { await data.refresh(session) } }
    }
}

// MARK: Home

struct HomeScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @ObservedObject var data: AppData
    var mustVerify: Bool = false
    var onVerify: () -> Void = {}
    let onPay: (String) -> Void
    let onScan: () -> Void
    let onCheck: () -> Void
    let onHelp: () -> Void
    let onQR: () -> Void
    let onHistory: () -> Void
    @State private var copied = false

    private var items: [ActivityItem] { data.items(session) }
    private var monthItems: [ActivityItem] { items.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) } }
    private var people: [String] {
        let me = session.pilotProfile?.vpa_id ?? ""
        let counts = Dictionary(grouping: session.transfers.filter { $0.sender_vpa == me && $0.status == "SUCCESS" }, by: { $0.receiver_vpa }).mapValues(\.count)
        return Array(counts.sorted { $0.value > $1.value }.map { $0.key }.prefix(4))
    }
    private var firstName: String { session.pilotProfile?.full_name.components(separatedBy: " ").first ?? "there" }
    private var greeting: String { let h = Calendar.current.component(.hour, from: Date()); return h < 12 ? "Good morning," : h < 17 ? "Good afternoon," : "Good evening," }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 10) {
                            Image("TPLockup").resizable().scaledToFit().frame(height: 30)
                            Spacer()
                            Button(action: onHelp) {
                                Image(systemName: "lifepreserver").font(.system(size: 17, weight: .medium)).foregroundStyle(TP.bad)
                                    .frame(width: 44, height: 44).background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TP.hair))
                            }.accessibilityLabel("Get help")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting).font(.tp(15)).foregroundStyle(TP.muted)
                            Text(firstName).font(.tp(32, .semibold)).foregroundStyle(TP.ink)
                        }
                        if mustVerify {
                            Button(action: onVerify) {
                                HStack(spacing: 14) {
                                    Image(systemName: "envelope.badge.fill").font(.system(size: 20)).foregroundStyle(TP.ink)
                                        .frame(width: 44, height: 44).background(TP.lime, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Verify your email to pay").font(.tp(15, .semibold)).foregroundStyle(TP.ink)
                                        Text("Payments unlock after you enter the code we email you.").font(.tp(12.5)).foregroundStyle(TP.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").foregroundStyle(TP.violet)
                                }
                                .padding(14).background(TP.violetSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.violet.opacity(0.35), lineWidth: 1))
                            }.buttonStyle(PressScaleStyle())
                        }
                        balanceCard
                        HStack(spacing: 8) {
                            quick("magnifyingglass", "Check ID", tint: TP.violet, onCheck)
                            quick("qrcode", "My QR", tint: TP.violet, onQR)
                            quick("list.bullet", "History", tint: TP.violet, onHistory)
                            quick("sos", "Get help", tint: TP.bad, onHelp)
                        }
                        safetyCard
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text("Recent").font(.tp(20, .semibold)).foregroundStyle(TP.ink); Spacer()
                                Button("See all", action: onHistory).font(.tp(14, .medium)).foregroundStyle(TP.violet) }
                            if items.isEmpty {
                                Text("No payments yet. Scan any UPI QR to pay safely.").font(.tp(14)).foregroundStyle(TP.muted).padding(.vertical, 12)
                            }
                            ForEach(items.prefix(3)) { item in
                                NavigationLink { PaymentDetailView(item: item) } label: { ActivityRow(item: item) }
                                if item.id != items.prefix(3).last?.id { Divider() }
                            }
                        }
                        if !people.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Pay again").font(.tp(20, .semibold)).foregroundStyle(TP.ink)
                                HStack(spacing: 18) {
                                    ForEach(people, id: \.self) { vpa in
                                        Button { onPay(vpa) } label: {
                                            VStack(spacing: 8) {
                                                Avatar(name: vpa, size: 56)
                                                Text(vpa.components(separatedBy: "@").first ?? vpa).font(.tp(12.5)).foregroundStyle(TP.ink2).lineLimit(1).frame(width: 64)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        scamCards
                    }
                    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("trace.pay balance").font(.tp(13)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Label("Protected", systemImage: "checkmark.shield.fill").font(.tp(12, .medium)).foregroundStyle(TP.lime)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(TP.lime.opacity(0.18), in: Capsule())
            }
            Text(rupees(session.pilotWallet?.balance ?? "0")).font(.tp(40, .semibold)).foregroundStyle(.white).monospacedDigit()
                .contentTransition(.numericText()).padding(.top, 6)
            Button {
                UIPasteboard.general.string = session.pilotProfile?.vpa_id; copied = true; Haptic.tap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Copied" : (session.pilotProfile?.vpa_id ?? ""), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.tp(13)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.padding(.top, 8)
            HStack(spacing: 10) {
                Button(action: onScan) {
                    Label("Scan & pay", systemImage: "qrcode.viewfinder").font(.tp(15, .medium)).foregroundStyle(TP.ink)
                        .frame(maxWidth: .infinity, minHeight: 50).background(TP.lime, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }.buttonStyle(PressScaleStyle())
                Button { onPay("") } label: {
                    Label("Pay", systemImage: "paperplane").font(.tp(15, .medium)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.2)))
                }.buttonStyle(PressScaleStyle())
            }.padding(.top, 20)
        }
        .padding(22)
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [TP.violet, TP.violetDark, TP.violetDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [TP.violetLight.opacity(0.9), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
                Image("TPMark").resizable().scaledToFit().frame(width: 150).opacity(0.10).offset(x: 30, y: -10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TP.violetDark.opacity(0.35), radius: 24, y: 16)
    }

    private func quick(_ icon: String, _ label: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); action() } label: {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(tint)
                    .frame(width: 60, height: 60).background(tint == TP.bad ? TP.badBg : TP.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text(label).font(.tp(12.5, .medium)).foregroundStyle(TP.ink2).lineLimit(1)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(PressScaleStyle())
    }

    private var safetyCard: some View {
        let checked = monthItems.filter { $0.band != nil }.count
        let risky = monthItems.filter { $0.band == "review" || $0.band == "high_review" }.count
        let spent = monthItems.filter { !$0.incoming && $0.status == "SUCCESS" }.reduce(0) { $0 + $1.amount }
        return CardBox(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 26)).foregroundStyle(TP.good)
                        .frame(width: 60, height: 60).background(TP.goodBg, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Caption(text: Date().formatted(.dateTime.month(.wide)) + " safety")
                        Text(risky == 0 ? "You're well protected" : "\(risky) risky payment\(risky == 1 ? "" : "s") flagged").font(.tp(18, .semibold)).foregroundStyle(TP.ink)
                        Text("Payments are checked before they leave").font(.tp(13)).foregroundStyle(TP.muted)
                    }
                }
                Divider()
                HStack {
                    stat("\(checked)", "Checked", TP.ink)
                    stat("\(risky)", "Flagged", risky > 0 ? TP.bad : TP.ink)
                    stat(rupees(spent), "Spent", TP.ink)
                }
            }
        }
    }
    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.tp(18, .semibold)).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.tp(12.5)).foregroundStyle(TP.muted)
        }.frame(maxWidth: .infinity)
    }

    private var scamCards: some View {
        let cards: [(String, String, String, Color, Color)] = [
            ("briefcase.fill", "Task scams", "\"Like videos, earn money\", then pay to unlock earnings. Real jobs never ask you to pay.", TP.badBg, TP.bad),
            ("phone.fill", "Fake KYC calls", "No bank asks for your UPI PIN or OTP on a call or link.", TP.violetSoft, TP.violet),
            ("chart.line.uptrend.xyaxis", "Investment groups", "Guaranteed returns on WhatsApp or Telegram are scams.", TP.warnBg, TP.warn),
        ]
        return VStack(alignment: .leading, spacing: 14) {
            Text("Know the scams").font(.tp(20, .semibold)).foregroundStyle(TP.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cards.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: cards[i].0).font(.system(size: 18)).foregroundStyle(cards[i].4)
                                .frame(width: 46, height: 46).background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Spacer(minLength: 16)
                            Text(cards[i].1).font(.tp(16, .medium)).foregroundStyle(TP.ink)
                            Text(cards[i].2).font(.tp(13)).foregroundStyle(TP.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18).frame(width: 240, height: 200, alignment: .topLeading)
                        .background(cards[i].3, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
            }
        }
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: item.title, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.tp(15, .medium)).foregroundStyle(TP.ink).lineLimit(1)
                Text("\(item.via) · \(item.date.formatted(.relative(presentation: .named)))").font(.tp(12.5)).foregroundStyle(TP.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(item.incoming ? "+" : "−")\(rupees(item.amount))").font(.tp(15, .medium)).monospacedDigit()
                    .foregroundStyle(item.status == "SUCCESS" ? (item.incoming ? TP.good : TP.ink) : TP.faint)
                if item.status != "SUCCESS" { Text(item.status.capitalized).font(.tp(12)).foregroundStyle(TP.faint) }
                else if let band = item.band { Label(Risk.label(band), systemImage: "checkmark.shield").font(.tp(12)).foregroundStyle(Risk.color(band)) }
                else { Text(item.incoming ? "Received" : "Paid").font(.tp(12)).foregroundStyle(TP.muted) }
            }
        }.padding(.vertical, 12).contentShape(Rectangle())
    }
}

// MARK: Activity

struct ActivityScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @ObservedObject var data: AppData
    @State private var filter = 0
    private var all: [ActivityItem] { data.items(session) }
    private var shown: [ActivityItem] {
        switch filter {
        case 1: return all.filter { $0.via == "trace.pay" }
        case 2: return all.filter { $0.via != "trace.pay" }
        case 3: return all.filter { $0.incoming }
        default: return all
        }
    }
    private var week: [(String, Double)] {
        let cal = Calendar.current
        return (0..<7).reversed().map { off in
            let day = cal.date(byAdding: .day, value: -off, to: Date()) ?? Date()
            let total = all.filter { !$0.incoming && $0.status == "SUCCESS" && cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amount }
            return (day.formatted(.dateTime.weekday(.narrow)), total)
        }
    }
    private var monthTotal: Double {
        all.filter { !$0.incoming && $0.status == "SUCCESS" && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { $0 + $1.amount }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Activity").font(.tp(32, .semibold)).foregroundStyle(TP.ink)
                        VStack(alignment: .leading, spacing: 10) {
                            Caption(text: "Spent in " + Date().formatted(.dateTime.month(.wide)))
                            Text(rupees(monthTotal)).font(.tp(32, .semibold)).foregroundStyle(TP.ink).monospacedDigit()
                            let maxV = max(1, week.map { $0.1 }.max() ?? 1)
                            HStack(alignment: .bottom, spacing: 10) {
                                ForEach(week.indices, id: \.self) { i in
                                    VStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(i == 6 ? TP.violet : TP.violetSoft)
                                            .frame(height: max(8, 110 * week[i].1 / maxV))
                                        Text(week[i].0).font(.tp(12)).foregroundStyle(TP.muted)
                                    }.frame(maxWidth: .infinity)
                                }
                            }.frame(height: 136, alignment: .bottom)
                        }
                        .padding(20).background(TP.canvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Picker("Filter", selection: $filter) { Text("All").tag(0); Text("trace.pay").tag(1); Text("Other apps").tag(2); Text("Received").tag(3) }
                            .pickerStyle(.segmented)
                        VStack(spacing: 0) {
                            if shown.isEmpty { Text("Nothing here yet.").font(.tp(14)).foregroundStyle(TP.muted).padding(.vertical, 20) }
                            ForEach(shown) { item in
                                NavigationLink { PaymentDetailView(item: item) } label: { ActivityRow(item: item) }
                                if item.id != shown.last?.id { Divider() }
                            }
                        }
                    }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await data.refresh(session) }
        }
    }
}

struct PaymentDetailView: View {
    let item: ActivityItem
    @State private var report: TextRoute?
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Avatar(name: item.title, size: 64)
                        Text("\(item.incoming ? "Received from" : "Paid to") \(item.title)").font(.tp(15)).foregroundStyle(TP.muted).multilineTextAlignment(.center)
                        Text(rupees(item.amount)).font(.tp(46, .semibold)).foregroundStyle(TP.ink).monospacedDigit()
                        Label(item.status == "SUCCESS" ? "Completed" : item.status.capitalized, systemImage: item.status == "SUCCESS" ? "checkmark.circle.fill" : "clock")
                            .font(.tp(13, .medium)).foregroundStyle(item.status == "SUCCESS" ? TP.good : TP.warn)
                            .padding(.horizontal, 12).padding(.vertical, 6).background(item.status == "SUCCESS" ? TP.goodBg : TP.warnBg, in: Capsule())
                    }.padding(.top, 10)
                    VStack(alignment: .leading, spacing: 16) {
                        if let band = item.band { step("Checked by trace.pay", "Risk \(item.score.map { "\($0)%" } ?? "") · \(Risk.label(band))") }
                        step("\(item.incoming ? "Received" : "Paid") via \(item.via)", item.date.formatted(date: .abbreviated, time: .shortened))
                        step("Saved to your activity", item.date.formatted(date: .abbreviated, time: .shortened))
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(TP.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    CardBox(padding: 0) {
                        VStack(spacing: 0) {
                            row(item.incoming ? "From" : "To", item.ref)
                            Divider().padding(.horizontal, 16)
                            row("App", item.via)
                        }
                    }
                    ShareLink(item: "trace.pay receipt: \(rupees(item.amount)) \(item.incoming ? "from" : "to") \(item.title) (\(item.ref)) on \(item.date.formatted()).") {
                        Label("Share receipt", systemImage: "square.and.arrow.up")
                    }.buttonStyle(NeoButtonStyle(kind: .white))
                    if !item.incoming {
                        Button { report = TextRoute(value: item.ref) } label: { Label("Report a problem", systemImage: "flag") }.buttonStyle(NeoButtonStyle(kind: .white))
                    }
                }.padding(.horizontal, 22).padding(.bottom, 24)
            }
        }
        .navigationTitle("Payment details").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $report) { r in ReportSheet(ref: r.value) }
    }
    private func step(_ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(TP.good).frame(width: 12, height: 12).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.tp(14.5, .medium)).foregroundStyle(TP.ink); Text(sub).font(.tp(12.5)).foregroundStyle(TP.muted) }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.tp(14)).foregroundStyle(TP.muted); Spacer(); Text(v).font(.tp(14)).foregroundStyle(TP.ink).lineLimit(1).truncationMode(.middle) }.padding(16)
    }
}

// MARK: - Risk (ScoreMeter + report)

enum Risk {
    static func band(_ score: Int) -> String { score >= 75 ? "high_review" : score >= 50 ? "review" : score >= 25 ? "watch" : "low" }
    static func color(_ band: String) -> Color {
        switch band { case "high_review", "review": return TP.bad; case "watch": return TP.warn; case "low": return TP.good; default: return TP.faint }
    }
    static func bg(_ band: String) -> Color {
        switch band { case "high_review", "review": return TP.badBg; case "watch": return TP.warnBg; case "low": return TP.goodBg; default: return TP.canvas }
    }
    static func label(_ band: String) -> String {
        switch band { case "high_review", "review": return "Poor"; case "watch": return "Average"; case "low": return "Excellent"; default: return "New" }
    }
    static func icon(_ code: String) -> String {
        switch code {
        case "INBOUND_BREADTH": return "person.3.fill"
        case "OUTBOUND_BREADTH": return "arrow.up.right.circle.fill"
        case "RAPID_ONWARD", "LARGE_RELAY": return "bolt.fill"
        case "PASS_THROUGH", "HIGH_FORWARDING": return "arrow.left.arrow.right"
        case "SHORT_DWELL": return "timer"
        case "FAN_IN_OUT": return "arrow.triangle.merge"
        case "STRUCTURING": return "square.grid.2x2.fill"
        case "ROUND_TRIP": return "arrow.triangle.2.circlepath"
        case "VICTIM_CONVERGENCE": return "person.crop.circle.badge.questionmark"
        case "ESCALATION": return "chart.line.uptrend.xyaxis"
        case "SCAM_AMOUNTS": return "indianrupeesign.circle.fill"
        case "MULE_LIFECYCLE": return "clock.arrow.circlepath"
        case "COORDINATED": return "link"
        case "DENSE_CORE", "RING": return "circle.hexagongrid.fill"
        case "BRIDGE": return "point.3.connected.trianglepath.dotted"
        case "ANOMALY": return "waveform.path.ecg"
        case "VERIFIED_REPORTS", "COMMUNITY_REPORTS": return "flag.fill"
        case "COMPLAINTS": return "exclamationmark.bubble.fill"
        case "INVESTIGATOR_FLAG": return "shield.slash.fill"
        case "INVESTIGATOR_CLEARED": return "checkmark.shield.fill"
        case "VERIFIED_MERCHANT": return "checkmark.seal.fill"
        case "REGULAR_CUSTOMERS": return "storefront.fill"
        case "NEW_ACCOUNT": return "clock.fill"
        default: return "exclamationmark.circle.fill"
        }
    }
}

struct RiskModel: Identifiable {
    let id = UUID()
    let name: String; let ref: String; let verified: Bool; let member: Bool
    let score: Int?; let band: String; let title: String; let advice: String
    let factors: [SafetyFactor]; let counterfactuals: [String]
    let reports: Int; let records: Int; let confidence: Double; let shield: [String]
    init(_ l: SafetyLookup) {
        name = l.display_name ?? l.ref; ref = l.ref; verified = l.merchant?.verified == true; member = l.member
        score = l.score; band = l.band; title = l.verdict.title; advice = l.verdict.advice
        factors = l.factors; counterfactuals = l.counterfactuals
        reports = l.reports; records = l.records; confidence = l.confidence; shield = l.shield?.reasons.map(\.text) ?? []
    }
    init(fallback r: RiskResponse, name: String) {
        self.name = name; ref = r.recipient_ref; verified = false; member = true
        score = ["review": 70, "caution": 40, "no_known_warning": 8][r.level] ?? 20
        band = ["review": "review", "caution": "watch", "no_known_warning": "low"][r.level] ?? "insufficient_information"
        title = ["review": "Risky", "caution": "Be careful", "no_known_warning": "No warning signs"][r.level] ?? "Not enough history"
        advice = r.disclaimer
        factors = r.reasons.enumerated().map { SafetyFactor(code: "R\($0.offset)", label: $0.element, family: "core", points: 0, detail: "") }
        counterfactuals = []; reports = 0; records = r.observed_transaction_count; confidence = 0; shield = r.shield?.reasons.map(\.text) ?? []
    }
}

struct ScoreMeterView: View {
    let score: Int?
    let band: String
    @State private var progress: Double = 0
    private let radius: CGFloat = 96
    var body: some View {
        ZStack {
            ForEach(0..<31, id: \.self) { i in
                Capsule().fill(TP.faint.opacity(i % 5 == 0 ? 0.9 : 0.45))
                    .frame(width: i % 5 == 0 ? 1.6 : 1, height: i % 5 == 0 ? 8 : 4)
                    .offset(y: -(radius + 14))
                    .rotationEffect(.degrees(-135 + Double(i) * 9))
            }
            Circle().trim(from: 0, to: 0.75).stroke(TP.canvas, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2).rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * progress).stroke(Risk.color(band), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2).rotationEffect(.degrees(135))
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white).frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 2).fill(Risk.color(band)).frame(width: 10, height: 10))
                .shadow(color: TP.ink.opacity(0.25), radius: 4, y: 2)
                .offset(y: -radius).rotationEffect(.degrees(-135 + 270 * progress))
                .opacity(score == nil ? 0 : 1)
            VStack(spacing: 4) {
                Caption(text: "Risk score")
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(score == nil ? "—" : "\(Int((progress * 100).rounded()))")
                        .font(.tp(52, .semibold)).foregroundStyle(TP.ink).monospacedDigit().contentTransition(.numericText())
                    if score != nil { Text("%").font(.tp(20, .medium)).foregroundStyle(TP.ink) }
                }
                Text(Risk.label(band)).font(.tp(12, .medium)).foregroundStyle(Risk.color(band))
                    .padding(.horizontal, 11).padding(.vertical, 4).background(Risk.bg(band), in: Capsule())
            }
            .frame(width: 148, height: 148)
            .background(Circle().fill(.white).shadow(color: TP.ink.opacity(0.12), radius: 16, y: 10))
            .overlay(Circle().stroke(TP.canvas, lineWidth: 8).padding(-8))
        }
        .frame(width: 250, height: 250)
        .onAppear { withAnimation(.easeOut(duration: 1.3)) { progress = Double(score ?? 0) / 100 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Risk score \(score.map { "\($0) percent" } ?? "not available"), \(Risk.label(band))")
    }
}

struct RiskReportView: View {
    let model: RiskModel
    @AppStorage("tp.voice") private var voice = false
    @State private var synth = AVSpeechSynthesizer()
    @State private var shown = 0
    @State private var showRules = false
    private var raises: [SafetyFactor] { model.factors.filter { $0.points >= 0 } }
    private var lowers: [SafetyFactor] { model.factors.filter { $0.points < 0 } }
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Avatar(name: model.name, size: 54)
                HStack(spacing: 6) {
                    Text(model.name).font(.tp(20, .semibold)).foregroundStyle(TP.ink).lineLimit(1).minimumScaleFactor(0.7)
                    if model.verified { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(hex: 0x1D9BF0)) }
                }
                Text(model.ref).font(.tp(13)).foregroundStyle(TP.muted)
            }
            TraceScoreBadge()
            ZStack(alignment: .topTrailing) {
                PixelField(tint: Risk.color(model.band)).frame(height: 290).frame(maxWidth: .infinity)
                    .mask(RadialGradient(colors: [.black, .black.opacity(0.6), .clear], center: .center, startRadius: 40, endRadius: 190))
                    .allowsHitTesting(false)
                ScoreMeterView(score: model.score, band: model.band).frame(maxWidth: .infinity).padding(.top, 20)
                Button { showRules = true } label: {
                    Image(systemName: "info.circle.fill").font(.system(size: 22)).foregroundStyle(TP.violet)
                        .frame(width: 44, height: 44).background(Color.white, in: Circle()).shadow(color: TP.ink.opacity(0.08), radius: 6, y: 2)
                }.accessibilityLabel("How the score works")
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.band == "low" ? "checkmark.shield.fill" : "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(Risk.color(model.band))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title).font(.tp(16, .semibold)).foregroundStyle(Risk.color(model.band))
                    Text(model.advice).font(.tp(14)).foregroundStyle(TP.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { speak() } label: { Image(systemName: "speaker.wave.2.fill").font(.system(size: 14)).foregroundStyle(TP.violet).frame(width: 36, height: 36).background(Color.white, in: Circle()) }
                    .accessibilityLabel("Read aloud")
            }
            .padding(16).background(Risk.bg(model.band), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                fact("flag.fill", "\(model.reports)", "Reports")
                fact("doc.text.fill", "\(model.records)", "Payments seen")
                fact(model.member ? "person.fill" : "globe", model.member ? "Member" : "External", "Account")
                fact("gauge.with.dots.needle.50percent", "\(Int(model.confidence * 100))%", "Confidence")
            }
            if !model.shield.isEmpty {
                section("For this payment") {
                    ForEach(model.shield.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TP.warn).frame(width: 22)
                            Text(model.shield[i]).font(.tp(14)).foregroundStyle(TP.ink2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 10)
                        if i < model.shield.count - 1 { Divider() }
                    }
                }
            }
            HStack {
                Text("Why this score").font(.tp(18, .semibold)).foregroundStyle(TP.ink)
                Spacer()
                Button { showRules = true } label: { Label("How it's scored", systemImage: "info.circle").font(.tp(13, .medium)).foregroundStyle(TP.violet) }
            }
            if !raises.isEmpty { section("What raises the risk") { factorList(raises, offset: 0) } }
            if !lowers.isEmpty { section("What lowers the risk") { factorList(lowers, offset: raises.count) } }
            if model.factors.isEmpty { section("Why") { Text("No warning or trust signals were found for this account.").font(.tp(14)).foregroundStyle(TP.muted).padding(.vertical, 10) } }
            if !model.counterfactuals.isEmpty {
                section("How the score changes") {
                    ForEach(model.counterfactuals.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(TP.violet).frame(width: 22)
                            Text(model.counterfactuals[i]).font(.tp(14)).foregroundStyle(TP.ink2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 10)
                    }
                }
            }
            Label("Advisory only. You decide whether to pay.", systemImage: "lock").font(.tp(12.5)).foregroundStyle(TP.muted)
        }
        .task {
            if voice { speak() }
            try? await Task.sleep(nanoseconds: 600_000_000)
            for i in model.factors.indices { try? await Task.sleep(nanoseconds: 100_000_000); withAnimation(.easeOut(duration: 0.3)) { shown = i + 1 } }
        }
        .onDisappear { synth.stopSpeaking(at: .immediate) }
        .sheet(isPresented: $showRules) { ScoringInfoSheet() }
    }
    private func factorList(_ list: [SafetyFactor], offset: Int) -> some View {
        ForEach(list.indices, id: \.self) { i in
            FactorRow(factor: list[i]).opacity(offset + i < shown ? 1 : 0).offset(y: offset + i < shown ? 0 : 8)
            if i < list.count - 1 { Divider() }
        }
    }
    private func fact(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(TP.violet).frame(width: 34, height: 34).background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.tp(16, .semibold)).foregroundStyle(TP.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.tp(12)).foregroundStyle(TP.muted)
            }
            Spacer(minLength: 0)
        }.padding(12).background(TP.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Caption(text: title)
            VStack(alignment: .leading, spacing: 0) { content() }.padding(.horizontal, 16).padding(.vertical, 4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.hair))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func speak() {
        synth.stopSpeaking(at: .immediate)
        let pct = model.score.map { "Risk \($0) percent." } ?? ""
        let u = AVSpeechUtterance(string: "\(model.title). \(pct) \(model.factors.prefix(3).map(\.label).joined(separator: ". "))")
        u.voice = AVSpeechSynthesisVoice(language: "en-IN"); u.rate = 0.5
        synth.speak(u)
    }
}

struct FactorRow: View {
    let factor: SafetyFactor
    private var lowers: Bool { factor.points < 0 }
    private var level: Int { abs(factor.points) >= 15 ? 3 : abs(factor.points) >= 8 ? 2 : 1 }
    var body: some View {
        let tint = lowers ? TP.good : TP.bad
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: Risk.icon(factor.code)).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(factor.label).font(.tp(15, .semibold)).foregroundStyle(TP.ink).fixedSize(horizontal: false, vertical: true)
                    if factor.points != 0 {
                        Text("\(["", "Low", "Medium", "High"][level]) impact · \(lowers ? "lowers" : "raises") risk").font(.tp(12)).foregroundStyle(tint)
                    }
                }
                Spacer(minLength: 6)
                if factor.points != 0 {
                    Text("\(factor.points > 0 ? "+" : "−")\(abs(factor.points))").font(.tp(16, .bold)).foregroundStyle(tint).monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 5).background(tint.opacity(0.1), in: Capsule())
                }
            }
            if !factor.detail.isEmpty {
                Text(factor.detail).font(.tp(13)).foregroundStyle(TP.ink2).fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(TP.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if factor.points != 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TP.hair)
                        Capsule().fill(tint).frame(width: g.size.width * min(1, CGFloat(abs(factor.points)) / 25))
                    }
                }.frame(height: 5)
            }
        }.padding(.vertical, 12)
    }
}

/// Native sheet with the report and pinned actions. The chosen action runs after the sheet closes (see onDismiss callers).
enum RiskAction { case pay, report }
struct RiskSheet: View {
    let model: RiskModel
    let payLabel: String
    let choose: (RiskAction?) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView(showsIndicators: false) {
            RiskReportView(model: model).padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { choose(.pay); dismiss() } label: { Label(payLabel, systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle()) }
                    .buttonStyle(NeoButtonStyle(kind: model.band == "review" || model.band == "high_review" ? .danger : .ink))
                HStack(spacing: 10) {
                    Button("Cancel") { choose(nil); dismiss() }.buttonStyle(NeoButtonStyle(kind: .white))
                    Button { choose(.report); dismiss() } label: { Label("Report", systemImage: "flag") }.buttonStyle(NeoButtonStyle(kind: .white))
                }
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8).background(.white)
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

// MARK: Scan

struct ScanScreen: View {
    let onTracePay: (String) -> Void
    let onExternal: (String) -> Void
    let onClose: () -> Void
    let onMyQR: () -> Void
    @State private var key = 0
    @State private var message = ""
    var body: some View {
        ZStack(alignment: .top) {
            QRScannerSheet(onScan: { raw in
                if let id = TracePayID.normalize(raw) { Haptic.success(); onTracePay(id) }
                else if UPIQR.parse(raw) != nil { Haptic.success(); onExternal(raw) }
                else {
                    Haptic.error(); message = "That QR has no UPI ID."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { message = ""; key += 1 }
                }
            }, onClose: onClose, onMyQR: onMyQR)
            .id(key).ignoresSafeArea()
            if !message.isEmpty {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.tp(14, .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10).background(TP.bad, in: Capsule()).padding(.top, 70)
            }
        }
    }
}

// MARK: Check

struct CheckScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @AppStorage("tp.recentChecks") private var recentRaw = ""
    @State private var query = ""
    @State private var result: RiskModel?
    @State private var busy = false
    @State private var message = ""
    @State private var report: TextRoute?
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }
    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Check any UPI ID").font(.tp(32, .semibold)).foregroundStyle(TP.ink)
                        Text("trace.pay, Google Pay, PhonePe, Paytm or a bank.").font(.tp(15)).foregroundStyle(TP.muted)
                        HStack(spacing: 10) {
                            TPField(icon: "magnifyingglass", placeholder: "name@okaxis", text: $query, keyboard: .emailAddress)
                            Button { if let s = UIPasteboard.general.string { query = s } } label: {
                                Image(systemName: "doc.on.clipboard").foregroundStyle(TP.violet).frame(width: 58, height: 58).background(TP.violetSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }.accessibilityLabel("Paste")
                        }
                        Button { Task { await check() } } label: { if busy { ProgressView().tint(.white) } else { Label("Check UPI ID", systemImage: "checkmark.shield") } }
                            .buttonStyle(NeoButtonStyle()).disabled(busy || query.trimmingCharacters(in: .whitespaces).isEmpty)
                        if !message.isEmpty { Label(message, systemImage: "exclamationmark.circle.fill").font(.tp(14)).foregroundStyle(TP.bad) }
                        if let result {
                            RiskReportView(model: result).id(result.id).padding(.top, 8)
                            Button { report = TextRoute(value: result.ref) } label: { Label("Report this account", systemImage: "flag") }.buttonStyle(NeoButtonStyle(kind: .white))
                        } else if !recent.isEmpty {
                            Caption(text: "Recent checks").padding(.top, 10)
                            VStack(spacing: 0) {
                                ForEach(recent, id: \.self) { r in
                                    Button { query = r; Task { await check() } } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock").foregroundStyle(TP.faint)
                                            Text(r).font(.tp(15)).foregroundStyle(TP.ink)
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundStyle(TP.faint)
                                        }.padding(.vertical, 14)
                                    }
                                    if r != recent.last { Divider() }
                                }
                            }
                        }
                    }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $report) { r in ReportSheet(ref: r.value) }
    }
    @MainActor private func check() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !q.isEmpty else { return }
        busy = true; message = ""; result = nil; defer { busy = false }
        do {
            let l = try await session.lookup(ref: q)
            result = RiskModel(l)
            recentRaw = ([l.ref] + recent.filter { $0 != l.ref }).prefix(6).joined(separator: "\n")
        } catch { message = error.localizedDescription }
    }
}

// MARK: Profile

struct ProfileScreen: View {
    @EnvironmentObject private var session: TracePaySession
    let onQR: () -> Void
    let onHelp: () -> Void
    @AppStorage("tp.lock") private var lockOn = true
    @AppStorage("tp.cooling") private var coolingOn = true
    @AppStorage("tp.coolingMinutes") private var coolingMinutes = 1
    @AppStorage("tp.dailyLimit") private var dailyLimit = 50000.0
    @AppStorage("tp.voice") private var voice = false
    @AppStorage("tp.haptics") private var haptics = true
    @State private var confirmSignOut = false
    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Profile").font(.tp(32, .semibold)).foregroundStyle(TP.ink)
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 14) {
                                Text(initials(session.pilotProfile?.full_name ?? "TP")).font(.tp(20, .semibold)).foregroundStyle(.white)
                                    .frame(width: 58, height: 58).background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.pilotProfile?.full_name ?? "").font(.tp(17, .semibold)).foregroundStyle(.white)
                                    Text(session.pilotProfile?.vpa_id ?? "").font(.tp(13)).foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer(minLength: 0)
                            }
                            Button(action: onQR) {
                                Label("My QR", systemImage: "qrcode").font(.tp(15, .medium)).foregroundStyle(TP.ink)
                                    .frame(maxWidth: .infinity, minHeight: 48).background(TP.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }.buttonStyle(PressScaleStyle())
                        }
                        .padding(20)
                        .background(LinearGradient(colors: [TP.violet, TP.violetDeep], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        group("Security") {
                            Toggle(isOn: Binding(get: { lockOn }, set: { new in Task { if await DeviceLock.authenticate(new ? "Turn on device lock" : "Turn off device lock") { lockOn = new } } })) {
                                row(DeviceLock.method.icon, "Device lock", "\(DeviceLock.method.name), as set on your phone")
                            }
                        }
                        group("Payment safety") {
                            Toggle(isOn: $coolingOn) { row("hourglass", "Cooling-off for new payees", "Pause before a first payment of ₹5,000+") }
                            if coolingOn {
                                Picker("Wait", selection: $coolingMinutes) { Text("1 min").tag(1); Text("5 min").tag(5); Text("10 min").tag(10) }.pickerStyle(.segmented)
                            }
                            Divider()
                            Stepper(value: $dailyLimit, in: 1000...100000, step: 5000) { row("gauge.with.needle", "Daily limit", rupees(dailyLimit)) }
                            Divider()
                            Toggle(isOn: $voice) { row("speaker.wave.2", "Read the risk aloud", "Speaks every risk verdict") }
                        }
                        group("App") {
                            Toggle(isOn: $haptics) { row("hand.tap", "Haptics", "Vibration feedback") }
                            Divider()
                            Button(action: onHelp) { HStack { row("lifepreserver", "Help & emergency", "If you've been scammed"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(TP.faint) } }
                        }
                        Button { confirmSignOut = true } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }.buttonStyle(NeoButtonStyle(kind: .white))
                        Text("trace.pay · version 6.0").font(.tp(12.5)).foregroundStyle(TP.muted).frame(maxWidth: .infinity)
                    }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(TP.violet)
        .confirmationDialog("Sign out of trace.pay?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { session.clearSavedCredentials() }
        }
    }
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption(text: title)
            VStack(spacing: 12) { content() }.padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.hair))
        }
    }
    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(TP.violet)
                .frame(width: 38, height: 38).background(TP.violetSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tp(15, .medium)).foregroundStyle(TP.ink)
                Text(sub).font(.tp(12.5)).foregroundStyle(TP.muted)
            }
        }
    }
}

func makeQR(_ text: String) -> UIImage? {
    let f = CIFilter.qrCodeGenerator(); f.message = Data(text.utf8); f.correctionLevel = "H"
    guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
    return UIImage(cgImage: cg)
}

struct MyQRSheet: View {
    @EnvironmentObject private var session: TracePaySession
    var body: some View {
        let vpa = session.pilotProfile?.vpa_id ?? ""
        let name = session.pilotProfile?.full_name ?? ""
        let payload = "upi://pay?pa=\(vpa)&pn=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)&cu=INR"
        let image = makeQR(payload)
        VStack(spacing: 16) {
            Caption(text: "My QR").padding(.top, 30)
            Text("Scan to pay me").font(.tp(24, .semibold)).foregroundStyle(TP.ink)
            if let image {
                ZStack {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    Image("TPMark").resizable().scaledToFit().frame(width: 46, height: 46).padding(3).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(width: 220, height: 220).padding(18)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: TP.ink.opacity(0.12), radius: 18, y: 10)
                .cornerSquares()
                .padding(.vertical, 8)
            }
            Text(name).font(.tp(17, .semibold)).foregroundStyle(TP.ink)
            Text(vpa).font(.tp(14)).foregroundStyle(TP.muted)
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("My trace.pay QR", image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }.buttonStyle(NeoButtonStyle()).padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity).background(ScreenBackground())
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

// MARK: - Pay a trace.pay member

struct PayMemberScreen: View {
    @EnvironmentObject private var session: TracePaySession
    let prefill: String
    let onDone: () -> Void
    enum Step { case recipient, amount, cooling, done }
    @AppStorage("tp.cooling") private var coolingOn = true
    @AppStorage("tp.coolingMinutes") private var coolingMinutes = 1
    @AppStorage("tp.dailyLimit") private var dailyLimit = 50000.0
    @State private var step: Step = .recipient
    @State private var input = ""
    @State private var recipient: PilotRecipient?
    @State private var amount = ""
    @State private var risk: RiskModel?
    @State private var pending: RiskAction?
    @State private var report: TextRoute?
    @State private var busy = false
    @State private var message = ""
    @State private var result: PilotTransferResponse?
    @State private var remaining = 0
    @State private var key = UUID().uuidString
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var value: Decimal { Decimal(string: amount) ?? 0 }
    private var isNewPayee: Bool { !session.transfers.contains { $0.receiver_vpa == recipient?.vpa_id && $0.status == "SUCCESS" } }
    private var spentToday: Double {
        let me = session.pilotProfile?.vpa_id
        return session.transfers.filter { $0.sender_vpa == me && $0.status == "SUCCESS" && Calendar.current.isDateInToday(parseDate($0.created_at)) }
            .reduce(0) { $0 + (Double($1.amount) ?? 0) }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            switch step {
            case .recipient: recipientStep
            case .amount: amountStep
            case .cooling: coolingStep
            case .done: SuccessView(ok: result?.status == "SUCCESS", amount: Double(result?.amount ?? amount) ?? 0,
                                    to: recipient?.display_name ?? recipient?.vpa_id ?? "", via: "trace.pay",
                                    reference: result?.transfer_ref, failure: result?.failure_reason, onDone: onDone)
            }
        }
        .sheet(item: $risk, onDismiss: runPending) { m in RiskSheet(model: m, payLabel: "Pay \(rupees(amount))") { pending = $0 } }
        .sheet(item: $report) { r in ReportSheet(ref: r.value) }
        .onReceive(tick) { _ in
            guard step == .cooling, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { Task { await confirmAndSend() } }
        }
        .task { if !prefill.isEmpty { input = prefill; await findRecipient() } }
    }

    private var header: some View {
        HStack {
            Button(action: onDone) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(TP.ink)
                    .frame(width: 44, height: 44).background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TP.hair))
            }.accessibilityLabel("Close")
            Spacer()
            Text("Pay").font(.tp(16, .medium)).foregroundStyle(TP.ink)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var recipientStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                Text("Who are you paying?").font(.tp(30, .semibold)).foregroundStyle(TP.ink).padding(.top, 14)
                TPField(icon: "at", placeholder: "name@tracepay", text: $input, keyboard: .emailAddress)
                if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad) }
                Text("Paying a Google Pay, PhonePe or Paytm QR? Use Scan.").font(.tp(13)).foregroundStyle(TP.muted)
            }.padding(22)
        }
        .safeAreaInset(edge: .bottom) {
            Button { Task { await findRecipient() } } label: { if busy { ProgressView().tint(.white) } else { Text("Continue") } }
                .buttonStyle(NeoButtonStyle()).disabled(busy || input.isEmpty).padding(.horizontal, 22).padding(.vertical, 12)
        }
    }

    private var amountStep: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 8)
            VStack(spacing: 6) {
                Avatar(name: recipient?.display_name ?? "TP", size: 58)
                Text(recipient?.display_name ?? "").font(.tp(17, .semibold)).foregroundStyle(TP.ink)
                Text(recipient?.vpa_id ?? "").font(.tp(13)).foregroundStyle(TP.muted)
                if isNewPayee {
                    Label("First payment to this person", systemImage: "exclamationmark.triangle.fill").font(.tp(12, .medium)).foregroundStyle(Color(hex: 0x9A6200))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(TP.warnBg, in: Capsule()).padding(.top, 4)
                }
            }.padding(.top, 12)
            Text(amount.isEmpty ? "₹0" : "₹\(amount)").font(.tp(58, .semibold)).foregroundStyle(TP.ink).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 22).padding(.top, 18)
            Text("Balance \(rupees(session.pilotWallet?.balance ?? "0"))").font(.tp(13)).foregroundStyle(TP.muted)
            if !message.isEmpty { Text(message).font(.tp(13.5)).foregroundStyle(TP.bad).multilineTextAlignment(.center).padding(.horizontal, 22).padding(.top, 8) }
            Spacer(minLength: 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { k in
                    Button { press(k) } label: {
                        Group { if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) } }
                            .font(.tp(26)).foregroundStyle(TP.ink).frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(Rectangle())
                    }.buttonStyle(PressScaleStyle())
                }
            }.padding(.horizontal, 22)
            Button { Task { await assess() } } label: { if busy { ProgressView().tint(.white) } else { Label("Check & continue", systemImage: "checkmark.shield") } }
                .buttonStyle(NeoButtonStyle()).disabled(busy || value <= 0).opacity(value > 0 ? 1 : 0.5)
                .padding(.horizontal, 22).padding(.vertical, 12)
        }
    }

    private var coolingStep: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(TP.canvas, lineWidth: 10)
                Circle().trim(from: 0, to: CGFloat(remaining) / CGFloat(max(1, coolingMinutes * 60)))
                    .stroke(TP.violet, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60)).font(.tp(44, .semibold)).foregroundStyle(TP.ink).monospacedDigit()
            }.frame(width: 190, height: 190)
            Text("Take a moment").font(.tp(26, .semibold)).foregroundStyle(TP.ink)
            Text("This is your first payment of \(rupees(amount)) to \(recipient?.display_name ?? "this person"). Scammers rush you. Do you know them?")
                .font(.tp(15)).foregroundStyle(TP.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            Button("Cancel payment") { step = .amount }.buttonStyle(NeoButtonStyle(kind: .white)).padding(.horizontal, 22).padding(.bottom, 12)
        }
    }

    private func press(_ k: String) {
        Haptic.tap(); message = ""
        if k == "⌫" { if !amount.isEmpty { amount.removeLast() }; return }
        if k == "." && amount.contains(".") { return }
        if let dot = amount.firstIndex(of: "."), amount.distance(from: dot, to: amount.endIndex) > 2 { return }
        if amount.count < 8 { amount += k }
    }

    @MainActor private func findRecipient() async {
        guard let id = TracePayID.normalize(input) else { message = TracePayID.invalidMessage; return }
        busy = true; message = ""; defer { busy = false }
        do { recipient = try await session.lookupPilotRecipient(vpa: id); step = .amount } catch { message = error.localizedDescription }
    }

    @MainActor private func assess() async {
        guard let r = recipient else { return }
        let v = Double(amount) ?? 0
        if v > 100000 { message = "Each payment is limited to ₹1,00,000."; return }
        if let bal = Double(session.pilotWallet?.balance ?? ""), v > bal { message = "That's more than your balance."; return }
        if spentToday + v > dailyLimit { message = "This passes your daily limit of \(rupees(dailyLimit)). You can change it in Profile."; return }
        busy = true; message = ""; defer { busy = false }
        do {
            let rr = try await session.assess(recipientRef: r.vpa_id, amount: value)
            if let look = try? await session.lookup(ref: r.vpa_id, amount: value) { risk = RiskModel(look) } else { risk = RiskModel(fallback: rr, name: r.display_name) }
            key = UUID().uuidString
        } catch { message = error.localizedDescription }
    }

    private func runPending() {
        let action = pending; pending = nil
        switch action {
        case .pay:
            if coolingOn && isNewPayee && (Double(amount) ?? 0) >= 5000 { remaining = coolingMinutes * 60; step = .cooling }
            else { Task { await confirmAndSend() } }
        case .report: report = TextRoute(value: recipient?.vpa_id ?? input)
        case .none: break
        }
    }

    @MainActor private func confirmAndSend() async {
        guard let r = recipient else { return }
        guard await DeviceLock.authenticate("Pay \(rupees(amount)) to \(r.display_name)") else { step = .amount; message = "Payment not confirmed."; return }
        busy = true; defer { busy = false }
        do {
            result = try await session.makePilotTransfer(receiverVPA: r.vpa_id, amount: value, note: "", idempotencyKey: key)
            if result?.status == "SUCCESS" { Haptic.success() } else { Haptic.error() }
            step = .done
            try? await session.refreshPilotWallet(); try? await session.refreshPilotTransfers()
        } catch { message = "\(error.localizedDescription) Trying again is safe."; step = .amount }
    }
}

struct SuccessView: View {
    let ok: Bool
    let amount: Double
    let to: String
    let via: String
    let reference: String?
    let failure: String?
    var details: [(String, String)] = []
    let onDone: () -> Void
    @State private var pop = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 52, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 116, height: 116)
                    .background(LinearGradient(colors: ok ? [Color(hex: 0x14B86C), TP.good] : [TP.bad, Color(hex: 0xB42A1B)], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .shadow(color: (ok ? TP.good : TP.bad).opacity(0.45), radius: 24, y: 14)
                    .cornerSquares(ok ? TP.lime : TP.badBg, size: 12)
                    .scaleEffect(pop ? 1 : 0.4).opacity(pop ? 1 : 0).padding(.top, 40)
                Text(ok ? "Paid to \(to)" : "Payment not completed").font(.tp(15)).foregroundStyle(TP.muted).padding(.top, 20).multilineTextAlignment(.center)
                if ok { Text(rupees(amount)).font(.tp(52, .semibold)).foregroundStyle(TP.ink).monospacedDigit() }
                Text(ok ? "via \(via) · checked by trace.pay" : (failure ?? "No money moved. You can try again safely."))
                    .font(.tp(13)).foregroundStyle(TP.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
                let rows = details + (reference.map { [("Reference", $0)] } ?? [])
                if ok && !rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { i in
                            HStack(alignment: .top) {
                                Text(rows[i].0).font(.tp(13.5)).foregroundStyle(TP.muted)
                                Spacer(minLength: 12)
                                Text(rows[i].1).font(.tp(13.5, .medium)).foregroundStyle(TP.ink).multilineTextAlignment(.trailing).textSelection(.enabled)
                            }.padding(.vertical, 11)
                            if i < rows.count - 1 { Divider() }
                        }
                    }.padding(.horizontal, 16).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.hair)).padding(.top, 8)
                }
            }.padding(.horizontal, 22)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if ok {
                    ShareLink(item: (["trace.pay receipt", "\(rupees(amount)) to \(to) via \(via)"] + details.map { "\($0.0): \($0.1)" } + [reference.map { "Reference: \($0)" } ?? ""]).joined(separator: "\n")) {
                        Label("Share receipt", systemImage: "square.and.arrow.up")
                    }.buttonStyle(NeoButtonStyle(kind: .white))
                }
                Button("Done", action: onDone).buttonStyle(NeoButtonStyle())
            }.padding(.horizontal, 22).padding(.vertical, 10)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = true }; if ok { Haptic.success() } }
    }
}

// MARK: - Pay any UPI QR (Google Pay, PhonePe, Paytm, BHIM)

struct UPIApp: Identifiable { let id: String; let name: String; let schemes: [String]; let store: String; let color: Color }

/// The payee's mobile number when the UPI ID starts with one (e.g. 8142180305@superyes).
func mobileFromUPI(_ vpa: String) -> String? {
    let head = vpa.components(separatedBy: "@").first ?? ""
    let digits = head.filter(\.isNumber)
    guard head.count == digits.count, digits.count >= 10 else { return nil }
    let last10 = String(digits.suffix(10))
    return "6789".contains(last10.first ?? "0") ? last10 : nil
}

struct ExternalPayScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.scenePhase) private var scenePhase
    let raw: String
    let onDone: () -> Void
    enum Prompt: Identifiable { case notInstalled; var id: Int { 1 } }
    private let apps: [UPIApp] = [
        UPIApp(id: "gpay", name: "Google Pay", schemes: ["gpay://upi/pay", "tez://upi/pay"], store: "https://apps.apple.com/in/app/google-pay/id1193357041", color: Color(hex: 0x1A73E8)),
        UPIApp(id: "phonepe", name: "PhonePe", schemes: ["phonepe://pay", "phonepe://upi/pay"], store: "https://apps.apple.com/in/app/phonepe/id1170055821", color: Color(hex: 0x5F259F)),
        UPIApp(id: "paytm", name: "Paytm", schemes: ["paytmmp://pay", "paytm://upi/pay"], store: "https://apps.apple.com/in/app/paytm/id473941634", color: Color(hex: 0x00B9F1)),
        UPIApp(id: "bhim", name: "BHIM", schemes: ["bhim://upi/pay", "upi://pay"], store: "https://apps.apple.com/in/app/bhim/id1200315258", color: Color(hex: 0x0B6E4F)),
    ]
    @State private var amount = ""
    @State private var payeeMobile = ""
    @State private var chosen: UPIApp?
    @State private var look: SafetyLookup?
    @State private var risk: RiskModel?
    @State private var pending: RiskAction?
    @State private var report: TextRoute?
    @State private var prompt: Prompt?
    @State private var showGuide = false
    @State private var showReceipt = false
    @State private var awaiting = false
    @State private var busy = false
    @State private var message = ""
    @State private var saved: ReceiptBody?
    @State private var copied = ""
    private var qr: [String: String]? { UPIQR.parse(raw) }
    private var payeeName: String { look?.display_name ?? qr?["pn"] ?? qr?["pa"] ?? "" }
    private func installed(_ app: UPIApp) -> Bool { app.schemes.contains { s in URL(string: s).map { UIApplication.shared.canOpenURL($0) } ?? false } }

    var body: some View {
        ZStack {
            ScreenBackground()
            if let saved {
                SuccessView(ok: saved.status == "SUCCESS", amount: Double(saved.amount) ?? 0, to: payeeName, via: chosen?.name ?? "UPI",
                            reference: saved.upi_txn_id, failure: "Not paid. Nothing was recorded as a payment.",
                            details: receiptRows(saved), onDone: onDone)
            } else { form }
        }
        .onAppear {
            if amount.isEmpty { amount = qr?["am"] ?? "" }
            if payeeMobile.isEmpty, let pa = qr?["pa"], let m = mobileFromUPI(pa) { payeeMobile = m }
        }
        .sheet(item: $risk, onDismiss: runPending) { m in RiskSheet(model: m, payLabel: "Pay \(rupees(amount)) with \(chosen?.name ?? "UPI")") { pending = $0 } }
        .sheet(item: $report) { r in ReportSheet(ref: r.value) }
        .sheet(isPresented: $showGuide) { guide }
        .sheet(isPresented: $showReceipt) {
            ReceiptSheet(amount: amount, payee: qr?["pa"] ?? raw, payeeName: payeeName, app: chosen?.name ?? "UPI") { body in
                Task { await save(body) }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active && awaiting { awaiting = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showReceipt = true } } }
        .alert(item: $prompt) { _ in
            Alert(title: Text("Couldn't open \(chosen?.name ?? "the app")"), message: Text("The number is copied. Open any UPI app and paste it, or install this one."),
                  primaryButton: .default(Text("Get \(chosen?.name ?? "app")")) { if let s = chosen?.store, let u = URL(string: s) { UIApplication.shared.open(u) } },
                  secondaryButton: .cancel(Text("OK")))
        }
    }

    private var form: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button(action: onDone) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(TP.ink)
                            .frame(width: 44, height: 44).background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TP.hair))
                    }.accessibilityLabel("Close")
                    Spacer()
                    Text("Pay any UPI QR").font(.tp(16, .medium)).foregroundStyle(TP.ink)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                if let qr {
                    VStack(spacing: 10) {
                        Avatar(name: payeeName, size: 70)
                        Text(payeeName).font(.tp(24, .semibold)).foregroundStyle(TP.ink).multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            Label(qr["pa"] ?? "", systemImage: "at").font(.tp(12.5)).foregroundStyle(TP.ink2)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(TP.canvas, in: Capsule())
                            if !payeeMobile.isEmpty {
                                Label("+91 \(payeeMobile)", systemImage: "phone.fill").font(.tp(12.5)).foregroundStyle(TP.ink2)
                                    .padding(.horizontal, 10).padding(.vertical, 6).background(TP.canvas, in: Capsule())
                            }
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 8) {
                        Caption(text: "Amount")
                        HStack(spacing: 4) {
                            Text("₹").font(.tp(32, .medium)).foregroundStyle(TP.faint)
                            TextField("0", text: $amount).keyboardType(.decimalPad).font(.tp(42, .semibold)).foregroundStyle(TP.ink).monospacedDigit()
                        }.padding(.horizontal, 20).frame(height: 82).background(TP.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Caption(text: "Payee's mobile number")
                        TPField(icon: "phone", placeholder: "10-digit mobile (to pay by phone number)", text: $payeeMobile, keyboard: .numberPad, prefix: "+91")
                        Text(mobileFromUPI(qr["pa"] ?? "") != nil ? "Read from the UPI ID." : "Optional. With it, you can use \"Pay phone number\" in your UPI app.")
                            .font(.tp(12)).foregroundStyle(TP.muted)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Caption(text: "Pay with")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            ForEach(apps) { app in
                                Button { chosen = app; Task { await check() } } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text(String(app.name.prefix(1))).font(.tp(20, .bold)).foregroundStyle(.white)
                                                .frame(width: 46, height: 46).background(app.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            Spacer()
                                            if busy && chosen?.id == app.id { ProgressView() } else { Image(systemName: "arrow.up.right").foregroundStyle(TP.faint) }
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name).font(.tp(16, .semibold)).foregroundStyle(TP.ink)
                                            Text(installed(app) ? "Installed" : "Tap to open").font(.tp(12)).foregroundStyle(installed(app) ? TP.good : TP.muted)
                                        }
                                    }
                                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(chosen?.id == app.id ? app.color : TP.hair, lineWidth: chosen?.id == app.id ? 2 : 1))
                                }.buttonStyle(PressScaleStyle()).disabled(busy)
                            }
                        }
                    }
                    if !message.isEmpty { Label(message, systemImage: "exclamationmark.circle.fill").font(.tp(14)).foregroundStyle(TP.bad) }
                    Label("trace.pay checks the account first. Your UPI PIN is only entered in your UPI app.", systemImage: "lock.shield").font(.tp(12.5)).foregroundStyle(TP.muted)
                } else {
                    Text("This QR has no valid UPI ID.").font(.tp(15)).foregroundStyle(TP.bad)
                }
            }.padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Step-by-step: copy the phone number (or UPI ID), open the app, pay there, come back.
    private var guide: some View {
        let mobile = payeeMobile.filter(\.isNumber)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Caption(text: "Pay in \(chosen?.name ?? "your UPI app")").padding(.top, 28)
                Text("Three quick steps").font(.tp(26, .semibold)).foregroundStyle(TP.ink)
                guideStep(1, mobile.count == 10 ? "Copy the phone number" : "Copy the UPI ID",
                          mobile.count == 10 ? "+91 \(mobile)" : (qr?["pa"] ?? ""), copyValue: mobile.count == 10 ? mobile : (qr?["pa"] ?? ""))
                if mobile.count == 10 { guideStep(nil, "Or copy the UPI ID", qr?["pa"] ?? "", copyValue: qr?["pa"] ?? "") }
                guideStep(2, "Open \(chosen?.name ?? "the app") and choose \(mobile.count == 10 ? "\"Pay phone number\"" : "\"Pay UPI ID\"")", "Paste, then pay \(rupees(amount)) with your PIN.", copyValue: nil)
                guideStep(3, "Come back to trace.pay", "Add the payment screenshot and we'll save every detail.", copyValue: nil)
                if !copied.isEmpty { Label("Copied \(copied)", systemImage: "checkmark.circle.fill").font(.tp(13, .medium)).foregroundStyle(TP.good) }
                Button { showGuide = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openApp(copy: mobile.count == 10 ? mobile : (qr?["pa"] ?? "")) } } label: {
                    Label("Open \(chosen?.name ?? "app")", systemImage: "arrow.up.right")
                }.buttonStyle(NeoButtonStyle())
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func guideStep(_ n: Int?, _ title: String, _ sub: String, copyValue: String?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(n.map(String.init) ?? "·").font(.tp(15, .bold)).foregroundStyle(n == nil ? TP.muted : .white)
                .frame(width: 32, height: 32).background(n == nil ? TP.canvas : TP.ink, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tp(15, .semibold)).foregroundStyle(TP.ink)
                Text(sub).font(.tp(13)).foregroundStyle(TP.muted).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if let copyValue, !copyValue.isEmpty {
                Button { UIPasteboard.general.string = copyValue; copied = copyValue; Haptic.tap() } label: {
                    Label("Copy", systemImage: "doc.on.doc").font(.tp(13, .semibold)).foregroundStyle(TP.violet)
                        .padding(.horizontal, 12).padding(.vertical, 8).background(TP.violetSoft, in: Capsule())
                }
            }
        }.padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.hair))
    }

    @MainActor private func check() async {
        guard let v = Decimal(string: amount), v > 0 else { message = "Enter the amount first."; return }
        busy = true; message = ""; defer { busy = false }
        do { let l = try await session.lookup(ref: raw, amount: v); look = l; risk = RiskModel(l) } catch { message = error.localizedDescription }
    }

    private func runPending() {
        let action = pending; pending = nil
        switch action {
        case .pay: DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGuide = true }
        case .report: report = TextRoute(value: qr?["pa"] ?? raw)
        case .none: break
        }
    }

    private func openApp(copy value: String) {
        guard let app = chosen else { return }
        UIPasteboard.general.string = value
        let roots: [URL] = app.schemes.compactMap { s in s.components(separatedBy: "://").first.flatMap { URL(string: $0 + "://") } }
        tryOpen(roots, index: 0)
    }

    private func tryOpen(_ urls: [URL], index: Int) {
        guard index < urls.count else { prompt = .notInstalled; return }
        UIApplication.shared.open(urls[index], options: [:]) { ok in
            DispatchQueue.main.async { if ok { awaiting = true } else { tryOpen(urls, index: index + 1) } }
        }
    }

    private func receiptRows(_ r: ReceiptBody) -> [(String, String)] {
        var rows: [(String, String)] = [("Amount", rupees(r.amount)), ("Paid to", payeeName), ("UPI ID", r.payee)]
        if let m = r.payee_mobile, !m.isEmpty { rows.append(("Mobile", "+91 \(m)")) }
        if let p = r.paid_at { rows.append(("Date & time", parseDate(p).formatted(date: .abbreviated, time: .shortened))) }
        rows.append(("App", chosen?.name ?? "UPI"))
        if let s = look?.score { rows.append(("Risk at payment", "\(s)% · \(Risk.label(look?.band ?? ""))")) }
        return rows
    }

    @MainActor private func save(_ body: ReceiptBody) async {
        let full = ReceiptBody(payee: body.payee, payee_name: payeeName, amount: body.amount, app: chosen?.id ?? "upi", status: body.status, source: body.source,
                               upi_txn_id: body.upi_txn_id, risk_score: look?.score, risk_band: look?.band, paid_at: body.paid_at,
                               payee_mobile: payeeMobile.filter(\.isNumber).isEmpty ? nil : payeeMobile.filter(\.isNumber))
        do { try await session.recordReceipt(full); saved = full; showReceipt = false } catch { message = error.localizedDescription; showReceipt = false }
    }
}

// MARK: - Payment receipt: read the payment screenshot (on-device text recognition) and save every detail

struct ReceiptSheet: View {
    let amount: String
    let payee: String
    let payeeName: String
    let app: String
    let onSave: (ReceiptBody) -> Void
    @State private var picked: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var reading = false
    @State private var amt = ""
    @State private var utr = ""
    @State private var paidAt = Date()
    @State private var success = true
    @State private var note = ""
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Caption(text: "Payment receipt").padding(.top, 28)
                Text("Did the payment go through?").font(.tp(26, .semibold)).foregroundStyle(TP.ink)
                Text("Add the payment screenshot from \(app). We'll read the amount, reference and time from it.").font(.tp(14.5)).foregroundStyle(TP.muted)
                PhotosPicker(selection: $picked, matching: .screenshots) {
                    HStack(spacing: 14) {
                        if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 90).clipShape(RoundedRectangle(cornerRadius: 10)) }
                        else { Image(systemName: "photo.badge.plus").font(.system(size: 22)).foregroundStyle(TP.violet).frame(width: 54, height: 54).background(TP.violetSoft, in: RoundedRectangle(cornerRadius: 14)) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(image == nil ? "Choose the screenshot" : "Screenshot added").font(.tp(15, .semibold)).foregroundStyle(TP.ink)
                            Text(reading ? "Reading the details…" : image == nil ? "From your Photos" : note).font(.tp(12.5)).foregroundStyle(TP.muted)
                        }
                        Spacer(minLength: 0)
                        if reading { ProgressView() }
                    }.padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.hair))
                }
                VStack(spacing: 12) {
                    TPField(icon: "indianrupeesign", placeholder: "Amount", text: $amt, keyboard: .decimalPad)
                    TPField(icon: "number", placeholder: "UPI reference / UTR (12 digits)", text: $utr, keyboard: .numberPad)
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(TP.faint).frame(width: 22)
                        Text("Paid at").font(.tp(16, .medium)).foregroundStyle(TP.muted)
                        Spacer()
                        DatePicker("", selection: $paidAt).labelsHidden().tint(TP.violet)
                    }.padding(.horizontal, 18).frame(height: 58).background(TP.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    SegmentSwitch(options: [("checkmark.circle", "Successful"), ("xmark.circle", "Failed")], selection: Binding(get: { success ? 0 : 1 }, set: { success = $0 == 0 }))
                }
                Button { onSave(body(status: success ? "SUCCESS" : "FAILURE", source: image == nil ? "manual" : "receipt")) } label: { Label("Save payment", systemImage: "checkmark") }
                    .buttonStyle(NeoButtonStyle()).disabled(Decimal(string: amt) == nil)
                Button { onSave(body(status: "CANCELLED", source: "manual")) } label: { Text("I didn't pay") }.buttonStyle(NeoButtonStyle(kind: .white))
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible).interactiveDismissDisabled()
        .onAppear { if amt.isEmpty { amt = amount } }
        .onChange(of: picked) { _, item in Task { await load(item) } }
    }
    private func body(status: String, source: String) -> ReceiptBody {
        let iso = ISO8601DateFormatter()
        return ReceiptBody(payee: payee, payee_name: payeeName, amount: amt, app: app, status: status, source: source == "receipt" ? "manual" : source,
                           upi_txn_id: utr.isEmpty ? nil : utr, risk_score: nil, risk_band: nil, paid_at: iso.string(from: paidAt), payee_mobile: nil)
    }
    @MainActor private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        image = img; reading = true; defer { reading = false }
        let text = await ReceiptReader.text(in: img)
        let found = ReceiptReader.parse(text)
        if let a = found.amount { amt = a }
        if let u = found.utr { utr = u }
        if let d = found.date { paidAt = d }
        if let s = found.success { success = s }
        note = [found.amount.map { "₹\($0)" }, found.utr.map { "Ref \($0)" }, found.date.map { $0.formatted(date: .abbreviated, time: .shortened) }].compactMap { $0 }.joined(separator: " · ")
        if note.isEmpty { note = "Couldn't read details. Fill them in below." }
    }
}

enum ReceiptReader {
    static func text(in image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request]) } catch { cont.resume(returning: "") }
            }
        }
    }
    static func parse(_ text: String) -> (amount: String?, utr: String?, date: Date?, success: Bool?) {
        func first(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
        let amount = first(#"(?:₹|rs\.?|inr)\s?([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#)?.replacingOccurrences(of: ",", with: "")
        let utr = first(#"(?:utr|upi\s*(?:transaction\s*)?(?:id|ref(?:erence)?(?:\s*no\.?)?)|transaction\s*id|ref(?:erence)?\s*(?:no|number)?)[^0-9]{0,24}([0-9]{12})"#) ?? first(#"\b([0-9]{12})\b"#)
        var date: Date?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            date = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date
        }
        let lower = text.lowercased()
        let success: Bool? = lower.contains("failed") || lower.contains("declined") ? false : (lower.contains("success") || lower.contains("paid") || lower.contains("completed") ? true : nil)
        return (amount, utr, date, success)
    }
}

// MARK: - Help and report

struct HelpSheet: View {
    @State private var scammer = ""
    @State private var report: TextRoute?
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "sos").font(.system(size: 26, weight: .semibold)).foregroundStyle(TP.bad)
                    .frame(width: 58, height: 58).background(TP.badBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.top, 28)
                Text("Act within the first hour").font(.tp(28, .semibold)).foregroundStyle(TP.ink)
                Text("Money reported quickly is the easiest to freeze.").font(.tp(15)).foregroundStyle(TP.muted)
                VStack(spacing: 0) {
                    step("phone.fill", "Call 1930", "National cyber-crime helpline. Share the amount, time and UPI ID.", "tel://1930")
                    Divider().padding(.leading, 70)
                    step("doc.text.fill", "File a complaint", "At cybercrime.gov.in. Keep screenshots of the chat and payment.", "https://cybercrime.gov.in")
                    Divider().padding(.leading, 70)
                    step("building.columns.fill", "Call your bank", "Ask them to block the transaction and raise a dispute.", nil)
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.hair))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Warn others").font(.tp(16, .semibold)).foregroundStyle(TP.ink)
                    Text("Report the account so everyone who tries to pay it gets a warning.").font(.tp(13)).foregroundStyle(TP.muted)
                    TPField(icon: "link", placeholder: "Scammer's UPI ID", text: $scammer, keyboard: .emailAddress)
                    Button { report = TextRoute(value: scammer) } label: { Label("Report on trace.pay", systemImage: "flag.fill") }
                        .buttonStyle(NeoButtonStyle(kind: .danger)).disabled(UPIQR.parse(scammer) == nil).opacity(UPIQR.parse(scammer) == nil ? 0.5 : 1)
                }.padding(18).background(TP.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("Never share your UPI PIN or OTP, and never install screen-sharing apps when a caller asks.").font(.tp(12.5)).foregroundStyle(TP.muted)
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }
        .background(ScreenBackground())
        .presentationDragIndicator(.visible)
        .sheet(item: $report) { r in ReportSheet(ref: r.value) }
    }
    private func step(_ icon: String, _ title: String, _ text: String, _ link: String?) -> some View {
        Button { if let link, let url = URL(string: link) { UIApplication.shared.open(url) } } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(TP.bad)
                    .frame(width: 40, height: 40).background(TP.badBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.tp(16, .semibold)).foregroundStyle(TP.ink)
                    Text(text).font(.tp(13)).foregroundStyle(TP.muted).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if link != nil { Image(systemName: "arrow.up.right").foregroundStyle(TP.faint) }
            }.padding(16).contentShape(Rectangle())
        }.disabled(link == nil)
    }
}

struct ReportSheet: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.dismiss) private var dismiss
    let ref: String
    @State private var category = "task_scam"
    @State private var details = ""
    @State private var lost = ""
    @State private var busy = false
    @State private var message = ""
    @State private var sent = false
    private let categories: [(String, String, String)] = [
        ("scam_payment", "Scam payment", "indianrupeesign.circle"), ("task_scam", "Task scam", "briefcase"), ("investment_scam", "Investment scam", "chart.line.uptrend.xyaxis"),
        ("fake_merchant", "Fake shop", "storefront"), ("loan_app", "Loan app", "iphone"), ("impersonation", "Impersonation", "person.crop.circle.badge.exclamationmark"),
    ]
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Caption(text: "Report an account").padding(.top, 28)
                Text(sent ? "Thanks. We'll review it." : "What happened?").font(.tp(26, .semibold)).foregroundStyle(TP.ink)
                Text(ref).font(.tp(13.5)).foregroundStyle(TP.muted)
                if sent {
                    Text("Investigators review every report. If it's confirmed, everyone who tries to pay this account will be warned.").font(.tp(15)).foregroundStyle(TP.muted)
                    Button("Done") { dismiss() }.buttonStyle(NeoButtonStyle()).padding(.top, 10)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(categories.indices, id: \.self) { i in
                            let c = categories[i]
                            Button { category = c.0 } label: {
                                Label(c.1, systemImage: c.2).font(.tp(13.5, .medium)).foregroundStyle(category == c.0 ? .white : TP.ink2)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 12)
                                    .background(category == c.0 ? TP.ink : TP.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    TPField(icon: "text.alignleft", placeholder: "Add details (optional)", text: $details)
                    TPField(icon: "indianrupeesign", placeholder: "Amount lost (optional)", text: $lost, keyboard: .decimalPad)
                    if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad) }
                    Button { Task { await send() } } label: { if busy { ProgressView().tint(.white) } else { Label("Send report", systemImage: "flag.fill") } }
                        .buttonStyle(NeoButtonStyle(kind: .danger)).disabled(busy)
                }
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    @MainActor private func send() async {
        busy = true; message = ""; defer { busy = false }
        do { try await session.reportScam(ref: ref, category: category, description: details, amount: lost); sent = true; Haptic.success() }
        catch { message = error.localizedDescription }
    }
}


// MARK: - Verify email (for accounts that haven't yet)

struct VerifyEmailSheet: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.dismiss) private var dismiss
    let email: String
    let onVerified: () -> Void
    @State private var code = ""
    @State private var resendIn = 0
    @State private var busy = false
    @State private var message = ""
    @State private var done = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: done ? "checkmark.seal.fill" : "envelope.open.fill").font(.system(size: 26)).foregroundStyle(done ? TP.good : TP.ink)
                    .frame(width: 60, height: 60).background(done ? TP.goodBg : TP.lime, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.top, 28)
                Text(done ? "Email verified" : "Check your email").font(.tp(28, .semibold)).foregroundStyle(TP.ink)
                Text(done ? "Payments are unlocked. You're all set." : "We sent a 6-digit code to \(email). Enter it to unlock payments.").font(.tp(15)).foregroundStyle(TP.muted)
                if done {
                    Button("Done") { dismiss() }.buttonStyle(NeoButtonStyle())
                } else {
                    OTPCodeField(code: $code)
                    if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad) }
                    Button { Task { await verify() } } label: { if busy { ProgressView().tint(.white) } else { Text("Verify email") } }
                        .buttonStyle(NeoButtonStyle()).disabled(busy || code.count != 6).opacity(code.count == 6 ? 1 : 0.5)
                    Button { Task { await sendCode() } } label: {
                        Text(resendIn > 0 ? "Resend code in \(resendIn)s" : "Resend code").font(.tp(14.5, .medium)).foregroundStyle(resendIn > 0 ? TP.faint : TP.violet)
                    }.disabled(resendIn > 0 || busy).frame(maxWidth: .infinity)
                    Label("Didn't get it? Check spam, or wait a minute and resend.", systemImage: "info.circle").font(.tp(13)).foregroundStyle(TP.muted)
                }
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .onReceive(tick) { _ in if resendIn > 0 { resendIn -= 1 } }
        .task { await sendCode() }
    }
    @MainActor private func sendCode() async {
        message = ""
        do { try await session.sendEmailCode(name: session.pilotProfile?.full_name ?? ""); resendIn = 30 } catch { message = error.localizedDescription }
    }
    @MainActor private func verify() async {
        busy = true; message = ""; defer { busy = false }
        do { try await session.verifyEmailCode(code); Haptic.success(); withAnimation { done = true }; onVerified() }
        catch { message = error.localizedDescription; Haptic.error() }
    }
}

// MARK: - 6.1 components

/// Six polished code boxes over one hidden field: auto-fills from SMS/Mail, supports paste, animates as digits arrive.
struct OTPCodeField: View {
    @Binding var code: String
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            TextField("", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).focused($focused)
                .foregroundStyle(.clear).tint(.clear).frame(height: 66)
                .onChange(of: code) { _, v in let c = String(v.filter(\.isNumber).prefix(6)); if c != v { code = c } }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let chars = Array(code)
                    let filled = i < chars.count
                    let active = focused && i == chars.count
                    Text(filled ? String(chars[i]) : "").font(.tp(28, .semibold)).foregroundStyle(TP.ink)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(filled ? Color.white : TP.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? TP.violet : (filled ? TP.hair : .clear), lineWidth: active ? 2 : 1))
                        .shadow(color: filled ? TP.ink.opacity(0.06) : .clear, radius: 6, y: 3)
                        .scaleEffect(filled ? 1 : 0.97)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: code)
                }
            }.allowsHitTesting(false)
        }
        .contentShape(Rectangle()).onTapGesture { focused = true }
        .onAppear { focused = true }
    }
}

struct ForgotPasswordSheet: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.dismiss) private var dismiss
    @State private var method = 0
    @State private var mobile = ""
    @State private var email = ""
    @State private var sent = false
    @State private var code = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var message = ""
    @State private var done = false
    private var identifier: String { method == 0 ? String(mobile.filter(\.isNumber).suffix(10)) : email.trimmingCharacters(in: .whitespaces).lowercased() }
    private var strong: Bool { password.count >= 8 && password.contains(where: \.isUppercase) && password.contains(where: \.isNumber) && password.contains(where: { !$0.isLetter && !$0.isNumber }) }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: done ? "checkmark.seal.fill" : "key.fill").font(.system(size: 24)).foregroundStyle(done ? TP.good : TP.violet)
                    .frame(width: 58, height: 58).background(done ? TP.goodBg : TP.violetSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.top, 28)
                Text(done ? "Password updated" : sent ? "Reset your password" : "Forgot password?").font(.tp(28, .semibold)).foregroundStyle(TP.ink)
                Text(done ? "Sign in with your new password." : sent ? "Enter the OTP we sent to \(method == 0 ? "+91 \(identifier)" : identifier), then choose a new password." : "We'll send a code to your mobile number or email.")
                    .font(.tp(15)).foregroundStyle(TP.muted)
                if done {
                    Button("Back to sign in") { dismiss() }.buttonStyle(NeoButtonStyle())
                } else if !sent {
                    SegmentSwitch(options: [("iphone", "Mobile"), ("envelope", "Email")], selection: $method)
                    if method == 0 { TPField(icon: "iphone", placeholder: "10-digit mobile number", text: $mobile, keyboard: .numberPad, prefix: "+91") }
                    else { TPField(icon: "envelope", placeholder: "Email", text: $email, keyboard: .emailAddress) }
                    if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad) }
                    Button { Task { await send() } } label: { if busy { ProgressView().tint(.white) } else { Text("Send one-time password (OTP)") } }
                        .buttonStyle(NeoButtonStyle()).disabled(busy || identifier.count < 5)
                } else {
                    OTPCodeField(code: $code)
                    TPField(icon: "lock", placeholder: "New password (8+ characters)", text: $password, secure: true)
                    TPField(icon: "lock", placeholder: "Confirm new password", text: $confirm, secure: true)
                    Text("Use 8+ characters with an uppercase letter, a number and a symbol.").font(.tp(12.5)).foregroundStyle(strong ? TP.good : TP.muted)
                    if !message.isEmpty { Text(message).font(.tp(14)).foregroundStyle(TP.bad) }
                    Button { Task { await reset() } } label: { if busy { ProgressView().tint(.white) } else { Text("Update password") } }
                        .buttonStyle(NeoButtonStyle()).disabled(busy || code.count != 6 || !strong || password != confirm)
                    Button("Resend OTP") { Task { await send() } }.font(.tp(14.5, .medium)).foregroundStyle(TP.violet).frame(maxWidth: .infinity)
                }
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    @MainActor private func send() async {
        busy = true; message = ""; defer { busy = false }
        do { try await session.forgotPassword(identifier: identifier); sent = true } catch { message = error.localizedDescription }
    }
    @MainActor private func reset() async {
        busy = true; message = ""; defer { busy = false }
        do { try await session.resetPassword(identifier: identifier, code: code, newPassword: password); done = true; Haptic.success() }
        catch { message = error.localizedDescription; Haptic.error() }
    }
}

/// "How the score works": every rule, its points and the bands (from the server, so it always matches the real model).
struct ScoringInfoSheet: View {
    @EnvironmentObject private var session: TracePaySession
    @State private var model: ScoringModel?
    @State private var message = ""
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                TraceScoreBadge().padding(.top, 28)
                Text("How TraceScore works").font(.tp(28, .semibold)).foregroundStyle(TP.ink)
                if let model {
                    Text(model.summary).font(.tp(15)).foregroundStyle(TP.ink2)
                    VStack(spacing: 0) {
                        ForEach(model.bands) { b in
                            HStack(spacing: 12) {
                                Text(b.range).font(.tp(14, .bold)).foregroundStyle(Risk.color(b.band)).frame(width: 64, alignment: .leading).monospacedDigit()
                                VStack(alignment: .leading, spacing: 1) { Text(b.label).font(.tp(14.5, .semibold)).foregroundStyle(TP.ink); Text(b.meaning).font(.tp(12.5)).foregroundStyle(TP.muted) }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 10)
                            if b.id != model.bands.last?.id { Divider() }
                        }
                    }.padding(.horizontal, 14).background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.hair))
                    ruleList("Payment behaviour", model.signals)
                    ruleList("Reports and trust", model.community)
                    Label(model.window, systemImage: "clock").font(.tp(12.5)).foregroundStyle(TP.muted)
                } else if !message.isEmpty {
                    Text(message).font(.tp(14)).foregroundStyle(TP.bad)
                } else { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .task { do { model = try await session.scoringModel() } catch { message = error.localizedDescription } }
    }
    private func ruleList(_ title: String, _ rules: [ScoringRule]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Caption(text: title)
            VStack(spacing: 0) {
                ForEach(rules) { r in
                    let lowers = r.pointsText.hasPrefix("-")
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: Risk.icon(r.code)).font(.system(size: 14, weight: .semibold)).foregroundStyle(lowers ? TP.good : TP.violet)
                            .frame(width: 34, height: 34).background(lowers ? TP.goodBg : TP.violetSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) { Text(r.label).font(.tp(14.5, .semibold)).foregroundStyle(TP.ink); Text(r.rule).font(.tp(12.5)).foregroundStyle(TP.muted).fixedSize(horizontal: false, vertical: true) }
                        Spacer(minLength: 6)
                        Text(r.pointsText).font(.tp(13, .bold)).foregroundStyle(lowers ? TP.good : TP.bad).multilineTextAlignment(.trailing)
                    }.padding(.vertical, 10)
                    if r.id != rules.last?.id { Divider() }
                }
            }.padding(.horizontal, 14).background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.hair))
        }
    }
}


// MARK: - TraceScore brand

/// "TraceScore by trace.pay" lockup shown on every risk report.
struct TraceScoreBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("TPMark").resizable().scaledToFit().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("Trace").font(.tp(15, .bold)).foregroundStyle(TP.ink) + Text("Score").font(.tp(15, .bold)).foregroundStyle(TP.violet)
            Text("by trace.pay").font(.tp(11.5, .medium)).foregroundStyle(TP.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(TP.hair))
        .shadow(color: TP.violet.opacity(0.12), radius: 10, y: 4)
    }
}

/// Floating pixel squares (the logo's corner squares) drifting in 3D behind the score meter.
struct PixelField: View {
    var tint: Color = TP.violet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Pixel { let x, y, size, speed, phase, depth: Double; let lime: Bool }
    @State private var pixels: [Pixel] = (0..<34).map { i in
        let r = { (a: Double, b: Double) -> Double in Double.random(in: a...b) }
        return Pixel(x: r(0, 1), y: r(0, 1), size: r(5, 15), speed: r(0.25, 0.8), phase: r(0, .pi * 2), depth: r(0.3, 1), lime: i % 5 == 0)
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for p in pixels {
                    let dx = sin(t * p.speed + p.phase) * 14 * p.depth
                    let dy = cos(t * p.speed * 0.8 + p.phase) * 18 * p.depth
                    let s = p.size * (0.6 + 0.4 * p.depth)
                    let rect = CGRect(x: p.x * size.width + dx - s / 2, y: p.y * size.height + dy - s / 2, width: s, height: s)
                    let color: Color = p.lime ? TP.lime : (Int(p.phase * 10) % 3 == 0 ? tint : TP.violetLight)
                    ctx.opacity = 0.18 + 0.5 * p.depth
                    ctx.fill(Path(roundedRect: rect, cornerRadius: s * 0.22), with: .color(color))
                }
            }
            .rotation3DEffect(.degrees(sin(t * 0.35) * 9), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(cos(t * 0.28) * 11), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        }
    }
}

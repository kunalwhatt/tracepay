import SwiftUI
import Foundation
import CoreImage.CIFilterBuiltins
import LocalAuthentication
import PhotosUI
import UIKit
import Charts
import AVFoundation

// MARK: - Trace.Pay brand system

enum TP {
    // 4.3 pixel-t identity. Token names are kept so every screen picks up the new palette:
    // "coral" is now the primary violet, "mint"/"green" are the lime success pair.
    static let ivory = Color(hex: 0xF3EEFF)       // lavender page background
    static let paper = Color(hex: 0xFFFFFF)       // cards
    static let ink = Color(hex: 0x14092E)
    static let charcoal = Color(hex: 0x2A1A5E)
    static let coral = Color(hex: 0x5B2EFF)       // primary violet
    static let coralSoft = Color(hex: 0xE4DCFF)   // soft lavender
    static let lime = Color(hex: 0xC6FF3D)
    static let mint = Color(hex: 0xECFFC2)        // success background
    static let green = Color(hex: 0x3D5600)       // success text on lime
    static let muted = Color(hex: 0x5E5480)
    static let line = Color(hex: 0xDDD3FF)
    static let blue = Color(hex: 0x8F6BFF)
    static let amber = Color(hex: 0x8A5A00)
    static let red = Color(hex: 0xB3261E)
    static let coralGradient = LinearGradient(colors: [coral, Color(hex: 0x7B57FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let darkGradient = LinearGradient(colors: [ink, charcoal], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct RootView: View {
    @EnvironmentObject private var session: TracePaySession
    @State private var unlocked = false
    @State private var profileError: String?

    var body: some View {
        ZStack {
            TP.ivory.ignoresSafeArea()
            if session.token == nil {
                if LocalUnlockStore.hasSavedSession && !unlocked {
                    DeviceUnlockScreen(unlocked: $unlocked)
                } else {
                    AccountAccessScreen()
                }
            } else if !session.profileLoaded {
                ProgressScreen()
            } else if session.pilotProfile == nil {
                ProfileSetupScreen()
            } else {
                AppShell()
            }
            if session.sessionExpired && session.token == nil {
                VStack { SessionExpiredBanner().padding(.horizontal, 16).padding(.top, 8); Spacer() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.sessionExpired)
        .task(id: session.token) {
            guard session.token != nil else { return }
            do { try await session.refreshPilotProfile() }
            catch { profileError = error.localizedDescription }
        }
    }
}

// MARK: - Authentication

struct AccountAccessScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @State private var register = false
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var errorMessage = ""
    @State private var appear = false

    @State private var confirm = ""
    @Namespace private var segment
    private let checks: [(String, String)] = [("12+ characters", ".{12,}"), ("Uppercase letter", "[A-Z]"), ("Number", "[0-9]"), ("Symbol", "[^A-Za-z0-9]")]
    private var strength: Int { checks.filter { password.range(of: $0.1, options: .regularExpression) != nil }.count }
    private var emailOK: Bool { email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil }
    private var canSubmit: Bool { !busy && emailOK && (register ? strength == 4 && confirm == password : !password.isEmpty) }
    private var strengthColor: Color { [TP.red, TP.amber, Color(hex: 0x8FD14F), TP.green][max(0, strength - 1)] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                form.offset(y: -36).padding(.horizontal, 18)
            }
        }
        .background(TP.ivory)
        .ignoresSafeArea(edges: .top)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appear = true } }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [TP.coral, Color(hex: 0x7B57FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(TP.lime).frame(width: 170, height: 170).offset(x: appear ? 250 : 215, y: appear ? -36 : -64)
            Circle().fill(Color.white.opacity(0.13)).frame(width: 120, height: 120).offset(x: appear ? -16 : -52, y: appear ? 190 : 225)
            Circle().fill(Color(hex: 0x8F6BFF)).frame(width: 56, height: 56).offset(x: appear ? 168 : 205, y: appear ? 172 : 148)
            VStack(alignment: .leading, spacing: 10) {
                BrandLockup(inverted: true)
                Spacer().frame(height: 28)
                Text(register ? "Create your\naccount." : "Welcome\nback.")
                    .font(.system(size: 42, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .id(register).transition(.opacity.combined(with: .move(edge: .bottom)))
                Text(register ? "Your Trace.Pay ID is ready in a minute." : "Pay safely. See the trail behind every payment.")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.white.opacity(0.88))
            }
            .padding(.horizontal, 24).padding(.top, 72)
        }
        .frame(height: 320)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 38, bottomTrailingRadius: 38, style: .continuous))
        .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: appear)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ForEach([false, true], id: \.self) { value in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { register = value; errorMessage = ""; confirm = "" }
                    } label: {
                        Text(value ? "Create account" : "Sign in")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(register == value ? Color.white : TP.muted)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background {
                                if register == value {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TP.coral).matchedGeometryEffect(id: "seg", in: segment)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(TP.ivory, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            AuthInput(icon: "envelope.fill", placeholder: "Email", text: $email, secure: false, visible: .constant(true), keyboard: .emailAddress, valid: email.isEmpty || emailOK)
            AuthInput(icon: "lock.fill", placeholder: "Password", text: $password, secure: true, visible: $showPassword, keyboard: .default, valid: true)
            if register {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { i in Capsule().fill(i < strength ? strengthColor : TP.line).frame(height: 6) }
                    }
                    .animation(.easeOut(duration: 0.2), value: strength)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(checks.indices, id: \.self) { i in
                            let ok = password.range(of: checks[i].1, options: .regularExpression) != nil
                            Label(checks[i].0, systemImage: ok ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ok ? TP.green : TP.muted)
                        }
                    }
                    AuthInput(icon: "lock.rotation", placeholder: "Confirm password", text: $confirm, secure: true, visible: $showPassword, keyboard: .default, valid: confirm.isEmpty || confirm == password)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ErrorText(errorMessage)
            TPPrimaryButton(title: busy ? (register ? "Creating account…" : "Signing in…") : (register ? "Create account" : "Sign in"), busy: busy) {
                Task { await submit() }
            }
            .disabled(!canSubmit)
            .opacity(canSubmit || busy ? 1 : 0.55)
            Label("We never ask for your UPI PIN, OTP or bank password.", systemImage: "lock.shield.fill")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(TP.muted).frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(TP.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TP.coral.opacity(0.18), radius: 24, y: 12)
        .opacity(appear ? 1 : 0)
    }

    private var passwordStrength: Bool {
        password.count >= 12 && password.range(of: "[A-Z]", options: .regularExpression) != nil && password.range(of: "[0-9]", options: .regularExpression) != nil && password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
    }

    @MainActor private func submit() async {
        busy = true; errorMessage = ""
        defer { busy = false }
        do {
            if register {
                try await session.register(email: email, password: password)
            } else {
                try await session.login(email: email, password: password)
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

struct DeviceUnlockScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @Binding var unlocked: Bool
    @State private var message = ""
    @State private var pulse = false

    var body: some View {
        ZStack {
            TP.darkGradient.ignoresSafeArea()
            Circle().stroke(TP.coral.opacity(0.35), lineWidth: 1).frame(width: 220, height: 220).scaleEffect(pulse ? 1.16 : 0.86).opacity(pulse ? 0.15 : 0.7)
            VStack(spacing: 18) {
                BrandLockup(inverted: true)
                Spacer().frame(height: 45)
                ZStack {
                    Circle().fill(TP.coral.opacity(0.13)).frame(width: 110, height: 110)
                    Image(systemName: "faceid").font(.system(size: 48, weight: .medium)).foregroundStyle(.white)
                }
                Text("Welcome back")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Unlock your saved Trace.Pay session")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                Button {
                    authenticate()
                } label: {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TP.ink)
                        .frame(maxWidth: .infinity).frame(height: 55)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
                .padding(.horizontal, 35)
                if !message.isEmpty { Text(message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center) }
                Button("Use another account") { session.clearSavedCredentials() }
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(25)
        }
        .onAppear { withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { pulse = true }; authenticate() }
    }

    private func authenticate() {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { message = error?.localizedDescription ?? "Device authentication is unavailable."; return }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your Trace.Pay account") { ok, authError in
            Task { @MainActor in
                if ok { do { try await session.restoreSavedSession(); unlocked = true } catch { message = error.localizedDescription } }
                else { message = authError?.localizedDescription ?? "Authentication was not completed." }
            }
        }
    }
}

// MARK: - Profile onboarding

struct ProfileSetupScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @State private var fullName = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var gender = "Prefer not to say"
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var consentProfile = false
    @State private var consentLedger = false
    @State private var busy = false
    @State private var errorMessage = ""
    @State private var photoLoading = false
    @State private var showCamera = false

    private let genders = ["Female", "Male", "Non-binary", "Prefer not to say", "Other"]
    private var adult: Bool { Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0 >= 18 }
    private var validName: Bool { fullName.range(of: #"^[\p{L}][\p{L} .’'\-]{1,158}$"#, options: .regularExpression) != nil }
    private var dobString: String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: dob) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    BrandLockup()
                    Text("Complete your profile")
                        .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1.5).padding(.top, 28)
                    Text("Your Trace.Pay ID and wallet are created after this step. Your selfie is encrypted and only checked for one clear face.")
                        .font(.system(size: 11)).foregroundStyle(TP.muted).lineSpacing(3)
                    Button { showCamera = true } label: {
                        VStack(spacing: 10) {
                            if let photoData, let image = UIImage(data: photoData) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 104, height: 104).clipShape(Circle()).overlay(Circle().stroke(TP.lime, lineWidth: 4))
                            } else {
                                Image(systemName: "faceid").font(.system(size: 34)).foregroundStyle(TP.coral).frame(width: 96, height: 96).background(TP.coralSoft, in: Circle())
                            }
                            Text(photoData == nil ? "Take a live selfie" : "Face captured · tap to retake").font(.system(size: 14, weight: .bold)).foregroundStyle(photoData == nil ? TP.ink : TP.coral)
                            Text("Camera only · face detection guides you").font(.system(size: 11)).foregroundStyle(TP.muted)
                        }
                        .frame(maxWidth: .infinity).padding(20)
                        .background(TP.paper, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(photoData == nil ? TP.line : TP.lime, lineWidth: photoData == nil ? 1 : 2))
                    }
                    .buttonStyle(PressScaleStyle())
                    .fullScreenCover(isPresented: $showCamera) {
                        LiveSelfieView(onCaptured: { data in photoData = data; showCamera = false; errorMessage = "" }, onCancel: { showCamera = false })
                    }
                    Field(title: "FULL NAME", text: $fullName, placeholder: "Your legal name", keyboard: .default, contentType: .name)
                    DatePicker("Date of birth · 18+", selection: $dob, in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!, displayedComponents: .date)
                        .font(.system(size: 12, weight: .semibold)).padding(15).background(TP.paper, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("GENDER").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(TP.muted)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { ForEach(genders, id: \.self) { value in Button { gender = value } label: { HStack { Image(systemName: gender == value ? "checkmark.circle.fill" : "circle"); Text(value).lineLimit(1); Spacer() }.font(.system(size: 10, weight: .semibold)).foregroundStyle(gender == value ? TP.coral : TP.ink).padding(12).background(gender == value ? TP.coralSoft : TP.paper, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(gender == value ? TP.coral.opacity(0.3) : TP.line)) }.buttonStyle(.plain) } }
                    }
                    ConsentToggle(isOn: $consentProfile, title: "I consent to storing this profile.", detail: "Required to create your Trace.Pay profile.")
                    ConsentToggle(isOn: $consentLedger, title: "I agree to the Trace.Pay wallet terms.", detail: "Your balance is held in the Trace.Pay wallet ledger.")
                    if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 10, weight: .semibold)).foregroundStyle(TP.red).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(TP.coralSoft, in: RoundedRectangle(cornerRadius: 13)) }
                    Button { Task { await create() } } label: { HStack { if busy { ProgressView().tint(.white) }; Text(busy ? "Creating profile…" : "Create Trace.Pay profile"); Spacer(); Image(systemName: "arrow.right") }.font(.system(size: 13, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 18).frame(height: 56).background(TP.coralGradient, in: RoundedRectangle(cornerRadius: 17)).shadow(color: TP.coral.opacity(0.2), radius: 16, y: 8) }.buttonStyle(PressScaleStyle()).disabled(busy || !validName || !adult || photoData == nil || !consentProfile || !consentLedger)
                }
                .padding(20)
            }
            .background(TP.ivory)
        }
    }

    private func loadPhoto() async { guard let selectedPhoto else { return }; photoLoading = true; defer { photoLoading = false }; do { photoData = try await selectedPhoto.loadTransferable(type: Data.self) } catch { errorMessage = "Could not read the selected photo." } }
    @MainActor private func create() async { busy = true; errorMessage = ""; defer { busy = false }; do { try await session.createPilotProfile(fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines), dateOfBirth: dobString, gender: gender, photoData: photoData!, consentProfile: consentProfile, consentLedger: consentLedger) } catch { errorMessage = error.localizedDescription } }
}

struct ConsentToggle: View { @Binding var isOn: Bool; let title: String; let detail: String; var body: some View { Toggle(isOn: $isOn) { VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 11, weight: .bold)); Text(detail).font(.system(size: 9)).foregroundStyle(TP.muted).lineSpacing(2) } }.tint(TP.coral).padding(14).background(TP.paper, in: RoundedRectangle(cornerRadius: 15)) } }

// MARK: - Main application

// MARK: - Main app (4.3 redesign: home, pay flow, scan / my QR, activity, profile)

enum MainTab: Int, Hashable { case home, pay, qr, activity, profile }

enum Haptic {
    private static var enabled: Bool { UserDefaults.standard.object(forKey: "tp.haptics") as? Bool ?? true }
    static func tap() { if enabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func success() { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func error() { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.error) } }
}

func initials(_ vpa: String) -> String {
    let name = vpa.split(separator: "@").first.map(String.init) ?? vpa
    let parts = name.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
    let letters = parts.prefix(2).compactMap { $0.first }
    return letters.isEmpty ? "TP" : String(letters).uppercased()
}

struct MainAppScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @State private var tab: MainTab = .home
    @State private var qrMode = 0
    @State private var payPrefill = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            TP.ivory.ignoresSafeArea()
            Group {
                switch tab {
                case .home: HomeScreen(tab: $tab, qrMode: $qrMode, payPrefill: $payPrefill)
                case .pay: PayFlowScreen(tab: $tab, qrMode: $qrMode, prefill: $payPrefill)
                case .qr: ScanQRScreen(tab: $tab, mode: $qrMode, payPrefill: $payPrefill)
                case .activity: ActivityTab()
                case .profile: ProfileTab(tab: $tab, qrMode: $qrMode)
                }
            }
            .transition(.opacity)
            // The pay flow is full-screen, as in the design; every other tab shows the floating bar.
            if tab != .pay && !(tab == .qr && qrMode == 0) { TPTabBar(tab: $tab) }
        }
        .animation(.easeInOut(duration: 0.18), value: tab)
        .task {
            try? await session.refreshPilotWallet()
            try? await session.refreshPilotTransfers()
            await session.refreshSessionIfNeeded()
        }
    }
}

// MARK: Shared building blocks

struct TPCard<Content: View>: View {
    var fill: Color = TP.paper
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(fill == TP.paper ? TP.line : Color.clear))
    }
}

struct TPChip: View {
    let text: String
    var fill: Color = TP.lime
    var body: some View {
        Text(text).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
            .padding(.horizontal, 12).padding(.vertical, 7).background(fill, in: Capsule())
    }
}

struct BackHeader: View {
    let action: () -> Void
    var chip: String? = nil
    var chipFill: Color = TP.lime
    var body: some View {
        HStack {
            Button(action: action) { Text("‹ Back").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink) }
                .buttonStyle(PressScaleStyle())
            Spacer()
            if let chip { TPChip(text: chip, fill: chipFill) }
        }
    }
}

struct TPPrimaryButton: View {
    let title: String
    var busy = false
    var fill: Color = TP.coral
    var textColor: Color = .white
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(textColor) }
                Text(title)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(textColor)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: fill == TP.coral ? TP.coral.opacity(0.28) : Color.clear, radius: 14, y: 8)
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct TPSecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(TP.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.line))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct ErrorText: View {
    let message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        if !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(TP.red)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xFFE2DD), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11)).foregroundStyle(TP.muted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(TP.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.line))
    }
}

struct TransferRow: View {
    let transfer: PilotTransferResponse
    let myVPA: String?
    private var incoming: Bool { transfer.receiver_vpa == myVPA && transfer.sender_vpa != myVPA }
    private var ok: Bool { transfer.status == "SUCCESS" }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(TP.coral)
                .frame(width: 44, height: 44).background(TP.coralSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(incoming ? transfer.sender_vpa : transfer.receiver_vpa).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(TP.ink).lineLimit(1)
                Text("\(transfer.transfer_ref) · \(incoming ? "Received" : "Sent")").font(.system(size: 11)).foregroundStyle(TP.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(incoming ? "+" : "")₹\(transfer.amount)").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                Text(transfer.status).font(.system(size: 9, weight: .heavy)).foregroundStyle(ok ? TP.green : TP.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(ok ? TP.lime : TP.coralSoft, in: Capsule())
            }
        }
        .padding(12)
        .background(TP.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.line))
        .accessibilityElement(children: .combine)
    }
}

struct SessionChip: View {
    @EnvironmentObject private var session: TracePaySession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int((session.tokenExpiry ?? context.date).timeIntervalSince(context.date)))
            Text(String(format: "Session %02d:%02d", remaining / 60, remaining % 60))
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(remaining < 120 ? TP.red : TP.ink)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(TP.coralSoft, in: Capsule())
                .onChange(of: remaining / 30) { _, _ in
                    if remaining < 300 { Task { await session.refreshSessionIfNeeded() } }
                }
                .accessibilityLabel("Session time remaining \(remaining / 60) minutes")
        }
    }
}

struct SessionExpiredBanner: View {
    @EnvironmentObject private var session: TracePaySession
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(TP.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your session ended").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                Text("For your security, sign in again to continue.").font(.system(size: 12)).foregroundStyle(TP.muted)
            }
            Spacer()
            Button { session.sessionExpired = false } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(TP.muted) }
                .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(TP.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.line))
        .shadow(color: TP.coral.opacity(0.15), radius: 16, y: 8)
    }
}

// MARK: Home

struct HomeTile: View {
    let icon: String
    let title: String
    let fill: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(TP.ink)
                    .frame(width: 60, height: 60)
                    .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(fill == TP.paper ? TP.line : Color.clear))
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(TP.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct BalanceCard: View {
    let balance: String?
    @Binding var hidden: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(TP.coralGradient)
            Circle().fill(TP.blue.opacity(0.55)).frame(width: 190, height: 190).offset(x: 170, y: -40)
            Circle().fill(TP.lime).frame(width: 110, height: 110).offset(x: 280, y: 80)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TRACE.PAY BALANCE").font(.system(size: 11, weight: .heavy)).tracking(1.1).foregroundStyle(Color.white.opacity(0.9))
                    Spacer()
                    Button { hidden.toggle() } label: {
                        Text(hidden ? "SHOW" : "HIDE").font(.system(size: 10, weight: .heavy)).foregroundStyle(TP.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Color.white.opacity(0.9), in: Capsule())
                    }
                }
                Text(hidden ? "₹ •••••" : "₹\(balance ?? "—")").font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("Available in your Trace.Pay wallet").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(20)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @Binding var tab: MainTab
    @Binding var qrMode: Int
    @Binding var payPrefill: String
    @State private var hideBalance = false
    @State private var copied = false

    private var displayName: String { session.pilotProfile?.full_name ?? "there" }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
    }
    private var recentPayees: [String] {
        var seen = Set<String>(); var out: [String] = []
        let me = session.pilotProfile?.vpa_id
        for t in session.transfers where t.sender_vpa == me && t.status == "SUCCESS" {
            if seen.insert(t.receiver_vpa).inserted { out.append(t.receiver_vpa) }
            if out.count == 6 { break }
        }
        return out
    }
    private let steps: [(String, String)] = [("person", "Recipient"), ("exclamationmark.triangle", "Risk review"), ("faceid", "Face ID"), ("checkmark.shield", "Ledger")]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                BalanceCard(balance: session.pilotWallet?.balance, hidden: $hideBalance)
                HStack(spacing: 10) {
                    HomeTile(icon: "arrow.right", title: "Pay", fill: TP.paper) { payPrefill = ""; tab = .pay }
                    HomeTile(icon: "qrcode.viewfinder", title: "Scan", fill: TP.lime) { qrMode = 0; tab = .qr }
                    HomeTile(icon: "qrcode", title: "My QR", fill: TP.coralSoft) { qrMode = 1; tab = .qr }
                    HomeTile(icon: "waveform.path.ecg", title: "Activity", fill: TP.paper) { tab = .activity }
                }
                idCard
                riskCard
                howItWorks
                if !recentPayees.isEmpty { payAgain }
                recent
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .refreshable {
            try? await session.refreshPilotWallet()
            try? await session.refreshPilotTransfers()
            await session.refreshSessionIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("TracePayMark").resizable().scaledToFit().frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting).font(.system(size: 12, weight: .medium)).foregroundStyle(TP.muted)
                Text(displayName).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            SessionChip()
        }
    }

    private var idCard: some View {
        TPCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR TRACE.PAY ID").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(TP.muted)
                    Text(session.pilotProfile?.vpa_id ?? "—").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = session.pilotProfile?.vpa_id
                    copied = true; Haptic.tap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                } label: { TPChip(text: copied ? "Copied" : "Copy ID") }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    private var riskCard: some View {
        TPCard {
            HStack(spacing: 12) {
                ZStack { Circle().fill(TP.lime); Image(systemName: "checkmark.shield").font(.system(size: 18, weight: .bold)).foregroundStyle(TP.ink) }
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Risk check before every payment").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                    Text("rules-v1 · an advisory from the records Trace.Pay can see, not proof of fraud").font(.system(size: 11)).foregroundStyle(TP.muted)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(TP.coral).frame(width: 5, height: CGFloat(8 + i * 5)) }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private var howItWorks: some View {
        TPCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("How a payment works").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                HStack {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        VStack(spacing: 6) {
                            ZStack { Circle().fill(TP.coralSoft); Image(systemName: step.0).font(.system(size: 15, weight: .semibold)).foregroundStyle(TP.coral) }
                                .frame(width: 42, height: 42)
                            Text(step.1).font(.system(size: 10, weight: .bold)).foregroundStyle(TP.ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Only completed payments move money. Failed attempts never do.").font(.system(size: 11)).foregroundStyle(TP.muted)
            }
        }
    }

    private var payAgain: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pay again").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                Spacer()
                Text("Tap to pay").font(.system(size: 11)).foregroundStyle(TP.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(recentPayees.enumerated()), id: \.element) { idx, vpa in
                        Button { payPrefill = vpa; tab = .pay } label: {
                            VStack(spacing: 6) {
                                Text(initials(vpa)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                                    .frame(width: 54, height: 54).background(idx % 2 == 1 ? TP.lime : TP.coralSoft, in: Circle())
                                Text(vpa.split(separator: "@").first.map(String.init) ?? vpa).font(.system(size: 10, weight: .semibold)).foregroundStyle(TP.ink)
                                    .lineLimit(1).frame(width: 64)
                            }
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Pay \(vpa) again")
                    }
                }
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                Spacer()
                Button("See all") { tab = .activity }.font(.system(size: 12, weight: .bold)).foregroundStyle(TP.coral)
            }
            if session.transfers.isEmpty {
                EmptyMobile(icon: "waveform.path.ecg", title: "No transfers yet", text: "Your Trace.Pay payments will appear here.")
            } else {
                ForEach(session.transfers.prefix(3), id: \.transfer_ref) { TransferRow(transfer: $0, myVPA: session.pilotProfile?.vpa_id) }
            }
        }
    }
}

// MARK: Pay flow: recipient → amount → risk review → Face ID → result

enum PayStage: Equatable { case recipient, amount, review, authorising, result }

struct RiskStyle {
    let label: String; let headline: String; let icon: String; let tint: Color; let fill: Color
    init(level: String) {
        switch level.lowercased() {
        case "review":
            label = "REVIEW"; headline = "Two or more pattern reasons showed up."; icon = "exclamationmark.octagon"; tint = TP.red; fill = Color(hex: 0xFFE2DD)
        case "caution":
            label = "CAUTION"; headline = "One pattern reason showed up."; icon = "exclamationmark.triangle"; tint = TP.amber; fill = TP.coralSoft
        case "no_known_warning":
            label = "NO KNOWN WARNING"; headline = "No configured pattern showed up."; icon = "checkmark.shield"; tint = TP.green; fill = TP.mint
        default:
            label = "NOT ENOUGH RECORDS"; headline = "Trace.Pay has too few records to assess this recipient."; icon = "questionmark.circle"; tint = TP.muted; fill = TP.coralSoft
        }
    }
}

struct Keypad: View {
    @Binding var value: String
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(keys, id: \.self) { key in
                Button { press(key) } label: {
                    Group {
                        if key == "⌫" { Image(systemName: "delete.left").font(.system(size: 20, weight: .semibold)) }
                        else { Text(key).font(.system(size: 24, weight: .bold, design: .rounded)) }
                    }
                    .foregroundStyle(TP.ink).frame(maxWidth: .infinity).frame(height: 56)
                    .background(TP.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.line))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(key == "⌫" ? "Delete" : key)
            }
        }
    }
    private func press(_ key: String) {
        Haptic.tap()
        if key == "⌫" { if !value.isEmpty { value.removeLast() }; return }
        if key == "." {
            if value.contains(".") { return }
            value = value.isEmpty ? "0." : value + "."
            return
        }
        if let dot = value.firstIndex(of: "."), value.distance(from: dot, to: value.endIndex) > 2 { return } // two decimals max
        if !value.contains(".") && value.count >= 6 { return }
        value = (value == "0") ? key : value + key
    }
}

struct PayFlowScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @Binding var tab: MainTab
    @Binding var qrMode: Int
    @Binding var prefill: String
    @State private var stage: PayStage = .recipient
    @State private var recipientInput = ""
    @State private var recipient: PilotRecipient?
    @State private var amount = ""
    @State private var risk: RiskResponse?
    @State private var look: SafetyLookup?
    @State private var showRisk = false
    @State private var showReport = false
    @State private var result: PilotTransferResponse?
    @State private var message = ""
    @State private var busy = false
    @State private var spin = false
    @State private var pop = false
    // One key per payment attempt; reused on retry so a dropped connection can never pay twice.
    @State private var idempotencyKey = UUID().uuidString

    private var amountValue: Decimal { Decimal(string: amount) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch stage {
            case .recipient: recipientStep
            case .amount: amountStep
            case .review: reviewStep
            case .authorising: authorisingStep
            case .result: resultStep
            }
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: stage)
        .onAppear {
            if !prefill.isEmpty {
                recipientInput = prefill
                prefill = ""
                Task { await findRecipient() }
            }
        }
    }

    private var recipientStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackHeader(action: { reset(goHome: true) }, chip: "SECURE")
            Text("Who are you paying?").font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
            Text("Enter their Trace.Pay ID. Every Trace.Pay ID ends in @tracepay.").font(.system(size: 13)).foregroundStyle(TP.muted)
            HStack(spacing: 0) {
                TextField("name", text: $recipientInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    .font(.system(size: 17, weight: .semibold, design: .rounded)).submitLabel(.next)
                    .onSubmit { Task { await findRecipient() } }
                if !recipientInput.contains("@") { Text("@tracepay").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(TP.muted) }
            }
            .padding(.horizontal, 16).frame(height: 58)
            .background(TP.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.line))
            Button { qrMode = 0; tab = .qr } label: {
                Label("Scan a Trace.Pay QR instead", systemImage: "qrcode.viewfinder").font(.system(size: 14, weight: .bold)).foregroundStyle(TP.coral)
            }
            ErrorText(message)
            Spacer()
            TPPrimaryButton(title: "Find recipient", busy: busy) { Task { await findRecipient() } }
                .disabled(busy || recipientInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var amountStep: some View {
        VStack(spacing: 14) {
            BackHeader(action: { message = ""; stage = .recipient }, chip: "SECURE")
            Text("To: \(recipient?.display_name ?? "") · \(recipient?.vpa_id ?? "")")
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading).frame(height: 50)
                .background(TP.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.line))
            Text("HOW MUCH?").font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(TP.muted).padding(.top, 6)
            Text("₹\(amount.isEmpty ? "0" : amount)").font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(TP.coral)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text("Balance ₹\(session.pilotWallet?.balance ?? "—") · limit ₹1,00,000").font(.system(size: 12)).foregroundStyle(TP.muted)
            Keypad(value: $amount)
            ErrorText(message)
            Spacer(minLength: 0)
            TPPrimaryButton(title: "Check recipient", busy: busy) { Task { await checkRisk() } }
                .disabled(busy || amountValue <= 0)
        }
    }

    private var reviewStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                BackHeader(action: { message = ""; stage = .amount }, chip: "RISK REVIEW", chipFill: TP.coralSoft)
                if let risk {
                    let style = RiskStyle(level: risk.level)
                    if let shield = risk.shield, !shield.reasons.isEmpty { ShieldCardView(shield: shield) }
                    if let look {
                        Button { showRisk = true } label: {
                            Label("See why: TraceScore \(look.score.map(String.init) ?? "–")/100 · \(look.verdict.title)", systemImage: "gauge.with.dots.needle.67percent")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(TP.coral).padding(.horizontal, 14).padding(.vertical, 10).background(TP.coralSoft, in: Capsule())
                        }
                        .sheet(isPresented: $showRisk) {
                            RiskSheetView(look: look, payLabel: "Continue to pay ₹\(amount)", onPay: { showRisk = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { authenticate() } },
                                          onCancel: { showRisk = false }, onReport: { showRisk = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showReport = true } })
                            .presentationDetents([.large])
                        }
                        .sheet(isPresented: $showReport) { ReportSheetView(ref: look.ref) { sent in showReport = false; if sent { message = "Thanks. Your report was sent for review." } } }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(style.label, systemImage: style.icon).font(.system(size: 13, weight: .heavy)).foregroundStyle(style.tint)
                        Text(style.headline).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(style.fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    TPCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why this category").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                            ForEach(risk.reasons, id: \.self) { reason in
                                Text(reason).font(.system(size: 13)).foregroundStyle(TP.ink).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        StatTile(value: "\(risk.observed_transaction_count)", label: "Records")
                        StatTile(value: risk.rule_version, label: "Rule")
                        StatTile(value: risk.data_as_of.formatted(date: .omitted, time: .shortened), label: "As of")
                    }
                    Text(risk.disclaimer).font(.system(size: 11)).foregroundStyle(TP.muted)
                    TPCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paying").font(.system(size: 11)).foregroundStyle(TP.muted)
                                Text(recipient?.display_name ?? "").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                                Text(recipient?.vpa_id ?? "").font(.system(size: 11)).foregroundStyle(TP.muted)
                            }
                            Spacer()
                            Text("₹\(amount)").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(TP.coral)
                        }
                    }
                }
                ErrorText(message)
                TPSecondaryButton(title: "Cancel") { reset(goHome: true) }
                TPPrimaryButton(title: "Continue with Face ID") { authenticate() }
            }
            .padding(.bottom, 20)
        }
    }

    private var authorisingStep: some View {
        VStack(spacing: 18) {
            HStack { TPChip(text: "CONFIRM"); Spacer() }
            Spacer()
            ZStack {
                Circle().fill(TP.paper).frame(width: 190, height: 190).shadow(color: TP.coral.opacity(0.15), radius: 30, y: 12)
                Circle().trim(from: 0, to: 0.22).stroke(TP.coral, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 190, height: 190).rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                Image(systemName: "faceid").font(.system(size: 60, weight: .regular)).foregroundStyle(TP.ink)
            }
            .onAppear { spin = true }
            Text(busy ? "Confirming with Trace.Pay…" : "Look at your phone").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
            Text("Face ID confirms ₹\(amount) to \(recipient?.display_name ?? "the recipient")").font(.system(size: 13)).foregroundStyle(TP.muted).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultStep: some View {
        let ok = result?.status == "SUCCESS"
        return VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(ok ? TP.lime : TP.coralSoft).frame(width: 150, height: 150)
                Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 54, weight: .heavy)).foregroundStyle(TP.ink)
            }
            .scaleEffect(pop ? 1 : 0.6).opacity(pop ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { pop = true } }
            Text(ok ? "Sent ₹\(result?.amount ?? amount)" : "Payment not completed").font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink).multilineTextAlignment(.center)
            Text(ok ? "to \(recipient?.display_name ?? "") · \(result?.receiver_vpa ?? "")" : (result?.failure_reason ?? "The transfer failed."))
                .font(.system(size: 14)).foregroundStyle(TP.muted).multilineTextAlignment(.center)
            Text(result?.transfer_ref ?? "").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(TP.ink)
                .padding(.horizontal, 14).padding(.vertical, 8).background(TP.paper, in: Capsule()).overlay(Capsule().stroke(TP.line))
            Text(ok ? "Payment complete. Both sides of the Trace.Pay ledger were updated." : "No ledger value was moved.")
                .font(.system(size: 12)).foregroundStyle(TP.muted).multilineTextAlignment(.center).padding(.horizontal, 20)
            Spacer()
            if ok {
                TPPrimaryButton(title: "Back home") { reset(goHome: true) }
                TPSecondaryButton(title: "View activity") { reset(goHome: false); tab = .activity }
            } else {
                TPPrimaryButton(title: "Try again") { pop = false; message = ""; result = nil; stage = .amount }
                TPSecondaryButton(title: "Back home") { reset(goHome: true) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor private func findRecipient() async {
        guard let id = TracePayID.normalize(recipientInput) else { message = TracePayID.invalidMessage; return }
        if id == session.pilotProfile?.vpa_id { message = "That's your own Trace.Pay ID. Choose someone else."; return }
        busy = true; message = ""
        defer { busy = false }
        do {
            recipient = try await session.lookupPilotRecipient(vpa: id)
            recipientInput = id
            amount = ""
            stage = .amount
        } catch let failure {
            message = failure.localizedDescription
        }
    }

    @MainActor private func checkRisk() async {
        guard let recipient else { stage = .recipient; return }
        if amountValue > 100000 { message = "Each payment is limited to ₹1,00,000."; return }
        if let balance = Decimal(string: session.pilotWallet?.balance ?? ""), amountValue > balance {
            message = "That's more than your Trace.Pay balance of ₹\(session.pilotWallet?.balance ?? "0")."
            return
        }
        busy = true; message = ""
        defer { busy = false }
        do {
            risk = try await session.assess(recipientRef: recipient.vpa_id, amount: amountValue)
            look = try? await session.lookup(ref: recipient.vpa_id, amount: amountValue)
            idempotencyKey = UUID().uuidString   // a new attempt starts here
            stage = .review
            showRisk = look != nil
        } catch let failure {
            message = failure.localizedDescription
        }
    }

    private func authenticate() {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            message = authError?.localizedDescription ?? "Face ID or the device passcode is unavailable."
            return
        }
        message = ""
        stage = .authorising
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Confirm ₹\(amount) to \(recipient?.vpa_id ?? "this recipient")") { ok, failure in
            Task { @MainActor in
                guard ok else {
                    message = failure?.localizedDescription ?? "Authentication cancelled."
                    stage = .review
                    return
                }
                await submit()
            }
        }
    }

    @MainActor private func submit() async {
        guard let recipient else { return }
        busy = true
        defer { busy = false }
        do {
            let transfer = try await session.makePilotTransfer(receiverVPA: recipient.vpa_id, amount: amountValue, note: "", idempotencyKey: idempotencyKey)
            idempotencyKey = UUID().uuidString   // the server answered definitively
            result = transfer
            if transfer.status == "SUCCESS" { Haptic.success() } else { Haptic.error() }
            stage = .result
        } catch let failure {
            // Same key kept on purpose: retrying this attempt can never move value twice.
            message = "\(failure.localizedDescription) The payment was not confirmed; retrying is safe."
            Haptic.error()
            stage = .review
        }
    }

    private func reset(goHome: Bool) {
        stage = .recipient; recipient = nil; recipientInput = ""; amount = ""; risk = nil; result = nil
        message = ""; pop = false; idempotencyKey = UUID().uuidString
        if goHome { tab = .home }
    }
}

// MARK: Scan and My QR

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct ViewfinderCorners: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let l: CGFloat = 36
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

struct ScanQRScreen: View {
    @EnvironmentObject private var session: TracePaySession
    @Binding var tab: MainTab
    @Binding var mode: Int
    @Binding var payPrefill: String
    @State private var showScanner = false
    @State private var message = ""
    @State private var copied = false
    @State private var line = false
    @State private var scanKey = 0
    @State private var externalQR: ExternalQR?

    private var qrPayload: String {
        let vpa = session.pilotProfile?.vpa_id ?? ""
        let name = (session.pilotProfile?.full_name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "tracepay://pay?pa=\(vpa)&pn=\(name)"
    }

    var body: some View {
        Group { if mode == 0 { cameraView } else { qrBody } }
            .fullScreenCover(item: $externalQR) { item in ExternalPayView(raw: item.raw) { externalQR = nil; scanKey += 1 } }
    }

    /// Tapping Scan opens the camera straight away; the animated frame and "Import from photos" live inside it.
    private var cameraView: some View {
        ZStack(alignment: .top) {
            QRScannerSheet(onScan: { raw in
                if let id = TracePayID.normalize(raw) {
                    message = ""; payPrefill = id; tab = .pay
                } else if UPIQR.parse(raw) != nil {
                    externalQR = ExternalQR(raw: raw)
                } else {
                    message = "That QR is not a Trace.Pay ID. Trace.Pay only pays name@tracepay accounts."
                    Haptic.error()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { message = ""; scanKey += 1 }
                }
            }, onClose: { tab = .home }, onMyQR: { mode = 1 })
            .id(scanKey)
            .ignoresSafeArea()
            if !message.isEmpty {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(12).background(TP.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20).padding(.top, 80)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: message)
    }

    private var qrBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                BackHeader(action: { tab = .home }, chip: "TRACE.PAY QR")
                HStack(spacing: 0) { segment("Scan", 0); segment("My QR", 1) }
                    .padding(4)
                    .background(TP.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TP.line))
                if mode == 0 { scanPanel } else { myQR }
                ErrorText(message)
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { raw in
                showScanner = false
                if let id = TracePayID.normalize(raw) {
                    message = ""; payPrefill = id; tab = .pay
                } else if UPIQR.parse(raw) != nil {
                    externalQR = ExternalQR(raw: raw)
                } else {
                    message = "That QR is not a Trace.Pay ID. Trace.Pay only pays name@tracepay accounts."
                    Haptic.error()
                }
            }
            .presentationCornerRadius(30)
        }
    }

    private func segment(_ title: String, _ value: Int) -> some View {
        Button { mode = value; message = "" } label: {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(mode == value ? Color.white : TP.ink)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(mode == value ? TP.coral : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }

    private var scanPanel: some View {
        VStack(spacing: 12) {
            Button { showScanner = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(TP.coral)
                    ViewfinderCorners().stroke(TP.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)).padding(28)
                    Rectangle().fill(TP.lime).frame(height: 3).padding(.horizontal, 44)
                        .offset(y: line ? 100 : -100)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: line)
                    VStack {
                        Spacer()
                        Text("Tap to open the camera").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).padding(.bottom, 40)
                    }
                }
                .frame(height: 300)
            }
            .buttonStyle(PressScaleStyle())
            .onAppear { line = true }
            .accessibilityLabel("Open the camera to scan a Trace.Pay QR")
            HStack(spacing: 10) {
                TPSecondaryButton(title: "Import from photos") { showScanner = true }
                TPPrimaryButton(title: "Enter ID", fill: TP.lime, textColor: TP.ink) { payPrefill = ""; tab = .pay }
            }
        }
    }

    private var myQR: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                if let image = QRCode.image(for: qrPayload) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 210, height: 210)
                        .padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TP.lime, lineWidth: 4))
                        .accessibilityLabel("QR code for \(session.pilotProfile?.vpa_id ?? "your Trace.Pay ID")")
                }
                Text(session.pilotProfile?.full_name ?? "").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                Text(session.pilotProfile?.vpa_id ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(TP.muted)
                Button {
                    UIPasteboard.general.string = session.pilotProfile?.vpa_id
                    copied = true; Haptic.tap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                } label: { TPChip(text: copied ? "Copied" : "Copy ID", fill: TP.coralSoft) }
                .buttonStyle(PressScaleStyle())
            }
            .padding(20).frame(maxWidth: .infinity)
            .background(TP.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(TP.line))
            if let image = QRCode.image(for: qrPayload) {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("My Trace.Pay QR", image: Image(uiImage: image))) {
                    Label("Share QR", systemImage: "square.and.arrow.up").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(TP.lime, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            Text("Share this code to receive payments to your Trace.Pay ID.").font(.system(size: 12)).foregroundStyle(TP.muted).multilineTextAlignment(.center)
        }
    }
}

// MARK: Activity

struct ActivityTab: View {
    @EnvironmentObject private var session: TracePaySession
    @State private var filter = 0
    private let filters = ["All", "Sent", "Received", "Failed"]
    private var me: String? { session.pilotProfile?.vpa_id }
    private var items: [PilotTransferResponse] {
        switch filter {
        case 1: return session.transfers.filter { $0.sender_vpa == me && $0.status == "SUCCESS" }
        case 2: return session.transfers.filter { $0.receiver_vpa == me && $0.sender_vpa != me }
        case 3: return session.transfers.filter { $0.status != "SUCCESS" }
        default: return session.transfers
        }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Activity").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                    Spacer()
                    Image(systemName: "waveform.path.ecg").font(.system(size: 17, weight: .semibold)).foregroundStyle(TP.ink)
                        .frame(width: 44, height: 44)
                        .background(TP.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TP.line))
                        .accessibilityHidden(true)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters.indices, id: \.self) { i in
                            Button { filter = i } label: {
                                Text(filters[i]).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(filter == i ? TP.lime : TP.paper, in: Capsule())
                                    .overlay(Capsule().stroke(filter == i ? Color.clear : TP.line))
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityAddTraits(filter == i ? .isSelected : [])
                        }
                    }
                }
                if items.isEmpty {
                    EmptyMobile(icon: "clock.arrow.circlepath", title: filter == 0 ? "Nothing here yet" : "No \(filters[filter].lowercased()) transfers", text: "Payments you send or receive appear here.")
                } else {
                    ForEach(items, id: \.transfer_ref) { TransferRow(transfer: $0, myVPA: me) }
                }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .refreshable { try? await session.refreshPilotTransfers() }
    }
}

// MARK: Profile

struct ProfileRowButton: View {
    let icon: String; let title: String; let detail: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(TP.ink)
                    .frame(width: 36, height: 36).background(TP.coralSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                Spacer()
                Text(detail).font(.system(size: 12)).foregroundStyle(TP.muted)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(TP.muted)
            }
            .padding(14)
            .background(TP.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.line))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct SettingToggle: View {
    let title: String; let detail: String; @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(TP.muted)
            }
        }
        .tint(TP.coral)
        .padding(14)
        .background(TP.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.line))
    }
}

struct LockedSetting: View {
    let title: String; let detail: String
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(TP.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(TP.muted)
            }
            Spacer()
            Label("Always on", systemImage: "lock.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(TP.green)
                .padding(.horizontal, 10).padding(.vertical, 6).background(TP.mint, in: Capsule())
        }
        .padding(14)
        .background(TP.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.line))
        .accessibilityElement(children: .combine)
    }
}

struct ProfileTab: View {
    @EnvironmentObject private var session: TracePaySession
    @Binding var tab: MainTab
    @Binding var qrMode: Int
    @AppStorage("tp.haptics") private var haptics = true
    @State private var confirmLogout = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Profile").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                HStack(spacing: 14) {
                    Image("TracePayMark").resizable().scaledToFit().frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.35)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.pilotProfile?.full_name ?? "Trace.Pay member").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        Text(session.pilotProfile?.vpa_id ?? "—").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
                    }
                    Spacer()
                }
                .padding(18)
                .background(TP.coralGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                ProfileRowButton(icon: "qrcode", title: "My QR code", detail: "Receive") { qrMode = 1; tab = .qr }
                LockedSetting(title: "Face ID for payments", detail: "Required for every Trace.Pay payment")
                LockedSetting(title: "Risk review before paying", detail: "Shown before every payment")
                SettingToggle(title: "Haptics", detail: "Taps, success and error", isOn: $haptics)
                TPCard {
                    VStack(spacing: 0) {
                        ProfileLine(title: "Gender", value: session.pilotProfile?.gender ?? "—")
                        Divider()
                        ProfileLine(title: "Face check", value: (session.pilotProfile?.selfie_status ?? "—").replacingOccurrences(of: "_", with: " "))
                        Divider()
                        ProfileLine(title: "Account", value: session.email ?? LocalUnlockStore.savedEmail ?? "—")
                        Divider()
                        ProfileLine(title: "Wallet", value: "Trace.Pay wallet")
                    }
                }
                InfoBanner(icon: "lock.shield.fill", title: "We never ask for your UPI PIN", text: "Trace.Pay never collects a UPI PIN, OTP or bank password. Face ID stays on your phone.")
                Button { confirmLogout = true } label: {
                    Text("Log out").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(TP.red)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(TP.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TP.line))
                }
                .buttonStyle(PressScaleStyle())
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .confirmationDialog("Log out of Trace.Pay on this phone?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { session.clearSavedCredentials() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: Floating tab bar

struct TPTabSpec: Identifiable { let id: MainTab; let icon: String; let title: String }

struct TPTabBar: View {
    @Binding var tab: MainTab
    private let items = [
        TPTabSpec(id: .home, icon: "house", title: "Home"),
        TPTabSpec(id: .pay, icon: "arrow.right", title: "Pay"),
        TPTabSpec(id: .qr, icon: "qrcode.viewfinder", title: "Scan QR"),
        TPTabSpec(id: .activity, icon: "waveform.path.ecg", title: "Activity"),
        TPTabSpec(id: .profile, icon: "person", title: "Profile"),
    ]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button { Haptic.tap(); tab = item.id } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 17, weight: .semibold))
                        Text(item.title).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(TP.ink)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background {
                        if tab == item.id { Circle().fill(TP.lime).frame(width: 58, height: 58) }
                    }
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityAddTraits(tab == item.id ? .isSelected : [])
            }
        }
        .padding(6)
        .background(TP.paper, in: Capsule())
        .overlay(Capsule().stroke(TP.line))
        .shadow(color: TP.coral.opacity(0.14), radius: 18, y: 8)
        .padding(.horizontal, 14).padding(.bottom, 6)
    }
}


// MARK: - Components

struct BrandLockup: View { var inverted = false; var body: some View { if inverted { HStack(spacing: 9) { Image("TracePayMark").resizable().scaledToFit().frame(width: 34, height: 34); Text("trace").foregroundStyle(.white) + Text(".").foregroundStyle(TP.lime) + Text("pay").foregroundStyle(.white) }.font(.system(size: 21, weight: .bold, design: .rounded)).tracking(-1) } else { HStack(spacing: 9) { Image("TracePayMark").resizable().scaledToFit().frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 9)); Text("trace").foregroundStyle(TP.ink) + Text(".").foregroundStyle(TP.coral) + Text("pay").foregroundStyle(TP.ink) }.font(.system(size: 21, weight: .bold, design: .rounded)).tracking(-0.8).accessibilityElement(children: .ignore).accessibilityLabel("trace.pay") } } }
struct AuthAmbientBackground: View { @State private var move = false; var body: some View { ZStack { Circle().fill(TP.coral.opacity(0.11)).frame(width: 360).blur(radius: 25).offset(x: move ? 170 : 40, y: -260); Circle().fill(TP.mint.opacity(0.75)).frame(width: 280).blur(radius: 20).offset(x: move ? -170 : -30, y: 310) }.onAppear { withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { move = true } } } }
struct AnimatedSignalCard: View { @State private var phase = false; var body: some View { HStack(spacing: 13) { ZStack { Circle().stroke(TP.coral.opacity(0.18), lineWidth: 8).frame(width: 45, height: 45); Circle().fill(TP.coral).frame(width: 8, height: 8).scaleEffect(phase ? 1.5 : 0.8) }.animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: phase); VStack(alignment: .leading, spacing: 4) { Text("LIVE INTELLIGENCE").font(.system(size: 8, weight: .heavy)).tracking(1.2).foregroundStyle(TP.muted); Text("Ledger · Graph · Evidence · Risk").font(.system(size: 11, weight: .bold)) }; Spacer(); Image(systemName: "waveform.path.ecg").foregroundStyle(TP.coral) }.padding(15).background(TP.paper, in: RoundedRectangle(cornerRadius: 19)).overlay(RoundedRectangle(cornerRadius: 19).stroke(TP.line)).onAppear { phase = true } } }
struct Field: View { let title: String; @Binding var text: String; let placeholder: String; let keyboard: UIKeyboardType; let contentType: UITextContentType?; var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.25).foregroundStyle(TP.muted); TextField(placeholder, text: $text).keyboardType(keyboard).textContentType(contentType).textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(size: 13, weight: .medium)).padding(.horizontal, 15).frame(height: 54).background(TP.paper, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(TP.line)) } } }
struct PasswordField: View { @Binding var password: String; @Binding var visible: Bool; var body: some View { VStack(alignment: .leading, spacing: 7) { Text("PASSWORD").font(.system(size: 9, weight: .heavy)).tracking(1.25).foregroundStyle(TP.muted); HStack { Group { if visible { TextField("Enter password", text: $password) } else { SecureField("Enter password", text: $password) } }.textContentType(.password); Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(TP.muted) } }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 15).frame(height: 54).background(TP.paper, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(TP.line)) } } }
struct SectionHeading: View { let kicker: String; let title: String; var body: some View { VStack(alignment: .leading, spacing: 4) { Text(kicker).font(.system(size: 9, weight: .heavy)).tracking(1.6).foregroundStyle(TP.muted); Text(title).font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-1.2) } } }
struct ProfileCircle: View { var body: some View { ZStack { Circle().fill(TP.coralSoft); Image(systemName: "person.fill").foregroundStyle(TP.coral) }.frame(width: 43, height: 43) } }
struct RecipientCard: View { let info: PilotRecipient; var body: some View { HStack(spacing: 12) { ZStack { Circle().fill(TP.mint); Image(systemName: info.recipient_type == "merchant" ? "storefront.fill" : "person.fill").foregroundStyle(TP.green) }.frame(width: 44, height: 44); VStack(alignment: .leading, spacing: 3) { Text(info.display_name).font(.system(size: 13, weight: .bold)); Text(info.vpa_id).font(.system(size: 9, design: .monospaced)).foregroundStyle(TP.muted); Label("Registered Trace.Pay \(info.recipient_type)", systemImage: "checkmark.seal.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(TP.green) }; Spacer() }.padding(14).background(TP.paper, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(TP.line)) } }
struct MobileTransferRow: View { let transfer: PilotTransferResponse; var body: some View { HStack(spacing: 11) { ZStack { Circle().fill(transfer.status == "SUCCESS" ? TP.mint : TP.coralSoft); Image(systemName: transfer.status == "SUCCESS" ? "arrow.up.right" : "xmark").foregroundStyle(transfer.status == "SUCCESS" ? TP.green : TP.coral) }.frame(width: 42, height: 42); VStack(alignment: .leading, spacing: 3) { Text(transfer.receiver_vpa).font(.system(size: 10, weight: .bold)); Text(transfer.transfer_ref).font(.system(size: 8, design: .monospaced)).foregroundStyle(TP.muted) }; Spacer(); VStack(alignment: .trailing, spacing: 3) { Text("₹\(transfer.amount)").font(.system(size: 12, weight: .bold)); Text(transfer.status).font(.system(size: 8, weight: .heavy)).foregroundStyle(transfer.status == "SUCCESS" ? TP.green : TP.coral) } }.padding(13).background(TP.paper, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(TP.line)) } }
struct InfoBanner: View { let icon: String; let title: String; let text: String; var body: some View { HStack(alignment: .top, spacing: 10) { Image(systemName: icon).foregroundStyle(TP.coral); VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 10, weight: .bold)); Text(text).font(.system(size: 9)).foregroundStyle(TP.muted).lineSpacing(2) } }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TP.coralSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 16)) } }
struct ProfileLine: View { let title: String; let value: String; var body: some View { HStack { Text(title).font(.system(size: 9)).foregroundStyle(TP.muted); Spacer(); Text(value).font(.system(size: 10, weight: .semibold)) }.padding(.vertical, 8) } }
struct EmptyMobile: View { let icon: String; let title: String; let text: String; var body: some View { VStack(spacing: 9) { Image(systemName: icon).font(.system(size: 28)).foregroundStyle(TP.coral.opacity(0.65)); Text(title).font(.system(size: 13, weight: .bold)); Text(text).font(.system(size: 9)).foregroundStyle(TP.muted).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(35).background(TP.paper, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(TP.line)) } }
struct RiskBadge: View { let level: String; var body: some View { let l=level.lowercased(); let c=l.contains("critical") || l.contains("high") ? TP.red : l.contains("medium") || l.contains("review") ? TP.amber : TP.green; return HStack(spacing: 6) { Circle().fill(c).frame(width: 6, height: 6); Text(level.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7) }.foregroundStyle(c).padding(.horizontal, 9).padding(.vertical, 6).background(c.opacity(0.10), in: Capsule()) } }
struct PressScaleStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).opacity(configuration.isPressed ? 0.9 : 1).animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed) } }
struct ProgressScreen: View { @State private var spin = false; var body: some View { ZStack { TP.ivory.ignoresSafeArea(); VStack(spacing: 14) { ZStack { Circle().stroke(TP.coralSoft, lineWidth: 10).frame(width: 65, height: 65); Circle().trim(from: 0, to: 0.3).stroke(TP.coral, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 65, height: 65).rotationEffect(.degrees(spin ? 360 : 0)).animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin) }; Text("Getting things ready…").font(.system(size: 11, weight: .semibold)).foregroundStyle(TP.muted) }.onAppear { spin = true } } } }


struct AuthInput: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let secure: Bool
    @Binding var visible: Bool
    let keyboard: UIKeyboardType
    let valid: Bool
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(TP.coral).frame(width: 20)
            Group {
                if secure && !visible { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
            .font(.system(size: 15, weight: .medium)).focused($focused)
            if secure {
                Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(TP.muted) }
                    .accessibilityLabel(visible ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 16).frame(height: 56)
        .background(TP.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(!valid ? TP.red : (focused ? TP.coral : TP.line), lineWidth: focused || !valid ? 2 : 1))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct ShieldCardView: View {
    let shield: ShieldInfo
    private var tint: Color { shield.level == "stop" ? TP.red : (shield.level == "caution" ? TP.amber : TP.coral) }
    private var fill: Color { shield.level == "stop" ? Color(hex: 0xFFE2DD) : (shield.level == "caution" ? Color(hex: 0xFFF1D2) : TP.coralSoft) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(shield.level == "stop" ? "TraceShield · think twice before paying" : "TraceShield", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(tint)
            ForEach(shield.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                    Text(reason.text).font(.system(size: 13)).foregroundStyle(TP.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("You decide. Trace.Pay never blocks a payment on its own.").font(.system(size: 11)).foregroundStyle(TP.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Safety layer views

func bandColor(_ band: String) -> Color {
    switch band { case "high_review": return Color(hex: 0xB3261E); case "review": return Color(hex: 0xE5482F)
    case "watch": return Color(hex: 0xE3A127); case "low": return Color(hex: 0x3D9A00); default: return Color(hex: 0x8A82A8) }
}

/// Semicircle gauge that sweeps to the score while the number counts up.
struct RiskGaugeView: View {
    let score: Int?; let band: String
    @State private var progress: Double = 0
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().trim(from: 0, to: 0.5).stroke(TP.coralSoft, style: StrokeStyle(lineWidth: 16, lineCap: .round)).rotationEffect(.degrees(180))
            Circle().trim(from: 0, to: 0.5 * progress).stroke(bandColor(band), style: StrokeStyle(lineWidth: 16, lineCap: .round)).rotationEffect(.degrees(180))
            VStack(spacing: 0) {
                Text(score == nil ? "–" : "\(Int((progress * 100).rounded()))").font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(bandColor(band)).contentTransition(.numericText())
                Text("TraceScore / 100").font(.system(size: 11)).foregroundStyle(TP.muted)
            }.offset(y: 4)
        }
        .frame(width: 190, height: 190).frame(height: 112, alignment: .top).clipped()
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { progress = Double(score ?? 0) / 100 } }
    }
}

/// The pop-up shown before every payment: score, verdict, every factor (animated in one by one), what would change it.
struct RiskSheetView: View {
    let look: SafetyLookup; let payLabel: String
    let onPay: () -> Void; let onCancel: () -> Void; let onReport: () -> Void
    @State private var shown = 0
    private var maxPoints: Int { max(1, look.factors.map { abs($0.points) }.max() ?? 1) }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Capsule().fill(TP.line).frame(width: 40, height: 5).padding(.top, 10)
                HStack(spacing: 6) {
                    Text(look.display_name ?? look.ref).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(TP.ink)
                    if look.merchant?.verified == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(hex: 0x1D9BF0)) }
                }
                Text(look.ref).font(.system(size: 12)).foregroundStyle(TP.muted)
                RiskGaugeView(score: look.score, band: look.band)
                Text(look.verdict.title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(bandColor(look.band))
                Text(look.verdict.advice).font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(TP.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([look.member ? "Trace.Pay member" : "External UPI ID", "\(look.community.reports) report(s)",
                                 "\(look.history.records) record(s)", "Confidence \(Int(look.confidence * 100))%"], id: \.self) { chip in
                            Text(chip).font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 6).background(TP.coralSoft, in: Capsule())
                        }
                    }
                }
                if let shield = look.shield, !shield.reasons.isEmpty { ShieldCardView(shield: shield) }
                Text("Why this score").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                if look.factors.isEmpty { Text("No warning or trust signals found.").font(.system(size: 13)).foregroundStyle(TP.muted).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(Array(look.factors.enumerated()), id: \.element.code) { index, factor in
                    if index < shown { FactorRowView(factor: factor, maxPoints: maxPoints).transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                if !look.counterfactuals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("What would change it", systemImage: "lightbulb.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(TP.coral)
                        ForEach(look.counterfactuals, id: \.self) { Text($0).font(.system(size: 12.5)).foregroundStyle(TP.ink) }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TP.coralSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                }
                Button(action: onPay) {
                    Text(payLabel).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(["high_review", "review"].contains(look.band) ? bandColor(look.band) : TP.coral, in: RoundedRectangle(cornerRadius: 18))
                }
                HStack(spacing: 10) {
                    Button(action: onCancel) { Text("Cancel").font(.system(size: 15, weight: .bold)).foregroundStyle(TP.ink).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TP.line)) }
                    Button(action: onReport) { Label("Report", systemImage: "flag.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(TP.red).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color(hex: 0xFFE2DD), in: RoundedRectangle(cornerRadius: 16)) }
                }
                Text("Advisory only. You decide whether to pay.").font(.system(size: 11)).foregroundStyle(TP.muted).padding(.bottom, 16)
            }.padding(.horizontal, 20)
        }
        .background(TP.paper)
        .task {
            shown = 0
            try? await Task.sleep(nanoseconds: 450_000_000)
            for i in look.factors.indices { try? await Task.sleep(nanoseconds: 120_000_000); withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { shown = i + 1 } }
        }
    }
}

struct FactorRowView: View {
    let factor: SafetyFactor; let maxPoints: Int
    @State private var grow: CGFloat = 0
    private var tint: Color { factor.points < 0 ? TP.green : Color(hex: 0xE5482F) }
    private var family: String { ["core": "Core", "community": "Community", "trust": "Trust"][factor.family] ?? "Behaviour" }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(family).font(.system(size: 10, weight: .bold)).foregroundStyle(TP.coral).padding(.horizontal, 6).padding(.vertical, 2).background(TP.coralSoft, in: RoundedRectangle(cornerRadius: 6))
                Text(factor.label).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(TP.ink)
                Spacer()
                Text("\(factor.points > 0 ? "+" : "")\(factor.points)").font(.system(size: 14, weight: .heavy)).foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TP.coralSoft)
                    Capsule().fill(tint).frame(width: geo.size.width * grow)
                }
            }.frame(height: 7)
            if !factor.detail.isEmpty { Text(factor.detail).font(.system(size: 11.5)).foregroundStyle(TP.muted) }
        }
        .padding(12).background(Color(hex: 0xFAF8FF), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { grow = CGFloat(abs(factor.points)) / CGFloat(maxPoints) } }
    }
}

struct ReportSheetView: View {
    @EnvironmentObject private var session: TracePaySession
    let ref: String; let onDone: (Bool) -> Void
    @State private var category = "scam_payment"
    @State private var details = ""
    @State private var amount = ""
    @State private var busy = false
    @State private var error = ""
    private let categories = [("scam_payment", "Scam payment"), ("task_scam", "Task scam"), ("investment_scam", "Investment scam"), ("fake_merchant", "Fake shop"),
                              ("loan_app", "Loan app"), ("impersonation", "Impersonation"), ("lottery_prize", "Prize scam"), ("other", "Other")]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report this account").font(.system(size: 21, weight: .heavy, design: .rounded))
            Text(ref).font(.system(size: 12)).foregroundStyle(TP.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(categories, id: \.0) { item in
                    Button { category = item.0 } label: { Text(item.1).font(.system(size: 13, weight: .bold)).foregroundStyle(TP.ink).padding(.horizontal, 14).padding(.vertical, 9)
                        .background(category == item.0 ? TP.lime : TP.coralSoft, in: Capsule()) }
                } }
            }
            TextField("What happened? (optional)", text: $details, axis: .vertical).lineLimit(3...5).padding(12).background(TP.ivory, in: RoundedRectangle(cornerRadius: 14))
            TextField("Amount lost, ₹ (optional)", text: $amount).keyboardType(.decimalPad).padding(12).background(TP.ivory, in: RoundedRectangle(cornerRadius: 14))
            if !error.isEmpty { Text(error).font(.system(size: 13)).foregroundStyle(TP.red) }
            Button {
                busy = true
                Task { do { try await session.reportScam(ref: ref, category: category, description: details, amount: amount); onDone(true) } catch { self.error = error.localizedDescription; busy = false } }
            } label: { Text(busy ? "Sending…" : "Send report").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(TP.red, in: RoundedRectangle(cornerRadius: 18)) }
                .disabled(busy)
            Text("Investigators review every report. Confirmed reports warn everyone who tries to pay this account.").font(.system(size: 11)).foregroundStyle(TP.muted)
            Spacer()
        }.padding(20).presentationDetents([.medium, .large])
    }
}

struct ExternalQR: Identifiable { let id = UUID(); let raw: String }

/// Pay any UPI QR (GPay, PhonePe, Paytm…): check → risk pop-up → hand off to the UPI app → confirm on return → record.
struct ExternalPayView: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.scenePhase) private var scenePhase
    let raw: String; let onDone: () -> Void
    @State private var amount = ""
    @State private var look: SafetyLookup?
    @State private var showRisk = false
    @State private var showReport = false
    @State private var awaitingReturn = false
    @State private var askConfirm = false
    @State private var app = "upi"
    @State private var busy = false
    @State private var message = ""
    @State private var recorded: String?
    private var qr: [String: String]? { UPIQR.parse(raw) }
    private let apps: [(String, String)] = [("Google Pay", "tez://upi/pay"), ("PhonePe", "phonepe://pay"), ("Paytm", "paytmmp://pay"), ("Any UPI app", "upi://pay")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button(action: onDone) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(TP.ink).frame(width: 42, height: 42).background(TP.paper, in: Circle()) }
                    Text("Pay any UPI QR").font(.system(size: 21, weight: .heavy, design: .rounded))
                }
                if let qr {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PAYING").font(.system(size: 11, weight: .bold)).foregroundStyle(TP.muted)
                        Text(qr["pn"] ?? qr["pa"] ?? "").font(.system(size: 23, weight: .heavy, design: .rounded))
                        Text(qr["pa"] ?? "").font(.system(size: 13)).foregroundStyle(TP.muted)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(TP.paper, in: RoundedRectangle(cornerRadius: 24))
                    TextField("Amount (₹)", text: $amount).keyboardType(.decimalPad).font(.system(size: 22, weight: .bold)).padding(16).background(TP.paper, in: RoundedRectangle(cornerRadius: 18))
                    if !message.isEmpty { Text(message).font(.system(size: 13)).foregroundStyle(TP.red) }
                    if let recorded { Label(recorded == "SUCCESS" ? "Payment recorded in your activity." : "Recorded as \(recorded.lowercased()).", systemImage: "checkmark.circle.fill").foregroundStyle(TP.green).font(.system(size: 14, weight: .bold)) }
                    Text("Choose the app to pay with").font(.system(size: 14, weight: .bold))
                    ForEach(apps, id: \.0) { item in
                        Button { app = item.0; Task { await check() } } label: {
                            HStack { Text(item.0).font(.system(size: 15, weight: .bold)); Spacer(); Image(systemName: "arrow.up.right") }
                                .foregroundStyle(TP.ink).padding(16).background(TP.paper, in: RoundedRectangle(cornerRadius: 16))
                        }.disabled(busy)
                    }
                    Text("Trace.Pay checks the account first and shows the risk. Your UPI PIN is only entered in your UPI app. If an app declines a payment started from another app, open it and scan the same QR there.")
                        .font(.system(size: 12)).foregroundStyle(TP.muted)
                } else { Text("This QR has no valid UPI ID.").foregroundStyle(TP.red) }
            }.padding(20)
        }
        .background(TP.ivory.ignoresSafeArea())
        .onAppear { amount = qr?["am"] ?? "" }
        .sheet(isPresented: $showRisk) {
            if let look { RiskSheetView(look: look, payLabel: "Pay ₹\(amount) with \(app)", onPay: { showRisk = false; openApp() },
                                        onCancel: { showRisk = false }, onReport: { showRisk = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showReport = true } })
                .presentationDetents([.large]) }
        }
        .sheet(isPresented: $showReport) { ReportSheetView(ref: qr?["pa"] ?? raw) { sent in showReport = false; if sent { message = "Thanks. Your report was sent for review." } } }
        .onChange(of: scenePhase) { _, phase in if phase == .active && awaitingReturn { awaitingReturn = false; askConfirm = true } }
        .alert("Did the payment go through?", isPresented: $askConfirm) {
            Button("Yes, I paid") { record("SUCCESS") }
            Button("No", role: .cancel) { record("CANCELLED") }
        } message: { Text("UPI apps on iPhone don't report back, so confirm to record it.") }
    }

    @MainActor private func check() async {
        guard let value = Decimal(string: amount), value > 0 else { message = "Enter the amount first."; return }
        busy = true; message = ""; defer { busy = false }
        do { look = try await session.lookup(ref: raw, amount: value); showRisk = true } catch { message = error.localizedDescription }
    }

    private func openApp() {
        guard let qr, let base = apps.first(where: { $0.0 == app })?.1, var components = URLComponents(string: base) else { return }
        components.queryItems = [URLQueryItem(name: "pa", value: qr["pa"]), URLQueryItem(name: "pn", value: look?.display_name ?? qr["pn"] ?? qr["pa"]),
                                 URLQueryItem(name: "am", value: amount), URLQueryItem(name: "cu", value: "INR"), URLQueryItem(name: "tn", value: qr["tn"] ?? "Checked with Trace.Pay")]
        guard let url = components.url else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UIApplication.shared.open(url) { ok in
                if ok { awaitingReturn = true } else { message = "\(app) is not installed. Choose another app." }
            }
        }
    }

    private func record(_ status: String) {
        guard let qr else { return }
        Task {
            do {
                try await session.recordExternalPayment(ExternalPaymentBody(payee: qr["pa"] ?? raw, payee_name: look?.display_name ?? qr["pn"], amount: amount,
                                                                            app: app.lowercased(), status: status, source: "manual", upi_txn_id: nil,
                                                                            risk_score: look?.score, risk_band: look?.band))
                recorded = status
            } catch { message = error.localizedDescription }
        }
    }
}

// =====================================================================================
// MARK: - Trace.Pay 7 · design system
// =====================================================================================

enum DS {
    static let bg = Color(hex: 0xF6F5FB)
    static let card = Color.white
    static let ink = Color(hex: 0x0F0B1E)
    static let sub = Color(hex: 0x6B6880)
    static let hair = Color(hex: 0xE9E6F2)
    static let accent = Color(hex: 0x5B2EFF)
    static let accentSoft = Color(hex: 0xEEE9FF)
    static let lime = Color(hex: 0xC6FF3D)
    static let safe = Color(hex: 0x16A34A)
    static let watch = Color(hex: 0xF59E0B)
    static let review = Color(hex: 0xF97316)
    static let high = Color(hex: 0xDC2626)

    static func risk(_ band: String) -> Color {
        switch band { case "high_review": return high; case "review": return review; case "watch": return watch; case "low": return safe; default: return sub }
    }
    static func riskLabel(_ band: String) -> String {
        switch band { case "high_review": return "High risk"; case "review": return "Risky"; case "watch": return "Be careful"; case "low": return "Safe"; default: return "New account" }
    }
    // Typography: serif display for headings, rounded for numbers, default for text.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

enum Lang: String, CaseIterable { case en, te, hi
    var label: String { switch self { case .en: return "English"; case .te: return "తెలుగు"; case .hi: return "हिन्दी" } }
}
func L(_ key: String) -> String {
    let lang = Lang(rawValue: UserDefaults.standard.string(forKey: "tp.lang") ?? "en") ?? .en
    let table: [String: [Lang: String]] = [
        "home": [.en: "Home", .te: "హోమ్", .hi: "होम"], "activity": [.en: "Activity", .te: "లావాదేవీలు", .hi: "गतिविधि"],
        "scan": [.en: "Scan", .te: "స్కాన్", .hi: "स्कैन"], "check": [.en: "Check", .te: "తనిఖీ", .hi: "जाँच"],
        "profile": [.en: "Profile", .te: "ప్రొఫైల్", .hi: "प्रोफ़ाइल"], "pay": [.en: "Pay", .te: "చెల్లించు", .hi: "भुगतान"],
        "check_id": [.en: "Check UPI ID", .te: "UPI ID తనిఖీ", .hi: "UPI ID जाँचें"], "scammed": [.en: "Get help", .te: "సహాయం", .hi: "मदद"],
        "recent": [.en: "Recent activity", .te: "ఇటీవలి లావాదేవీలు", .hi: "हाल की गतिविधि"], "see_all": [.en: "See all", .te: "అన్నీ", .hi: "सभी"],
        "trusted": [.en: "People you pay", .te: "మీరు చెల్లించే వారు", .hi: "जिन्हें आप भुगतान करते हैं"],
        "stay_safe": [.en: "Know the scams", .te: "మోసాలను తెలుసుకోండి", .hi: "धोखाधड़ी पहचानें"],
        "continue": [.en: "Continue", .te: "కొనసాగించు", .hi: "जारी रखें"], "cancel": [.en: "Cancel", .te: "రద్దు", .hi: "रद्द करें"],
        "report": [.en: "Report", .te: "ఫిర్యాదు", .hi: "रिपोर्ट"], "settings": [.en: "Settings", .te: "సెట్టింగ్‌లు", .hi: "सेटिंग्स"],
        "risk_report": [.en: "Risk report", .te: "రిస్క్ నివేదిక", .hi: "जोखिम रिपोर्ट"],
    ]
    return table[key]?[lang] ?? table[key]?[.en] ?? key
}

func parseDate(_ s: String) -> Date {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]; return f.date(from: s) ?? Date.distantPast
}
func rupees(_ value: String) -> String {
    guard let d = Double(value) else { return "₹" + value }
    let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_IN"); f.maximumFractionDigits = 2
    return "₹" + (f.string(from: NSNumber(value: d)) ?? value)
}
func rupees(_ value: Double) -> String { rupees(String(value)) }

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DS.hair, lineWidth: 1))
    }
}

struct PrimaryButton: View {
    let title: String; var icon: String? = nil; var tint: Color = DS.accent; var busy = false; let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) } else if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(DS.text(16, .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(PressScaleStyle()).disabled(busy)
    }
}

struct SecondaryButton: View {
    let title: String; var icon: String? = nil; var tint: Color = DS.ink; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { if let icon { Image(systemName: icon) }; Text(title) }
                .font(DS.text(15, .semibold)).foregroundStyle(tint).frame(maxWidth: .infinity).frame(height: 50)
                .background(DS.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.hair))
        }.buttonStyle(PressScaleStyle())
    }
}

struct ScreenHeader: View {
    let title: String; var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(DS.display(32)).foregroundStyle(DS.ink)
            if let subtitle { Text(subtitle).font(DS.text(14)).foregroundStyle(DS.sub) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
}

// =====================================================================================
// MARK: - Credit-score style risk report
// =====================================================================================

struct RiskModel: Identifiable {
    let id = UUID()
    let name: String; let ref: String; let verified: Bool; let member: Bool
    let score: Int?; let band: String; let title: String; let advice: String
    let factors: [SafetyFactor]; let counterfactuals: [String]
    let reports: Int; let records: Int; let confidence: Double; let shield: ShieldInfo?

    init(_ l: SafetyLookup) {
        name = l.display_name ?? l.ref; ref = l.ref; verified = l.merchant?.verified == true; member = l.member
        score = l.score; band = l.band; title = l.verdict.title; advice = l.verdict.advice
        factors = l.factors; counterfactuals = l.counterfactuals
        reports = l.community.reports; records = l.history.records; confidence = l.confidence; shield = l.shield
    }
    init(fallback r: RiskResponse, name: String) {
        self.name = name; ref = r.recipient_ref; verified = false; member = true; score = nil
        band = ["review": "review", "caution": "watch", "no_known_warning": "low"][r.level] ?? "insufficient_information"
        title = DS.riskLabel(band); advice = r.disclaimer
        factors = r.reasons.enumerated().map { SafetyFactor(code: "R\($0.offset)", label: $0.element, family: "core", points: 0, detail: "") }
        counterfactuals = []; reports = 0; records = r.observed_transaction_count; confidence = 0; shield = r.shield
    }
}

/// Icon for every factor the scoring engine can produce.
func factorIcon(_ code: String) -> String {
    switch code {
    case "INBOUND_BREADTH": return "person.3.fill"
    case "OUTBOUND_BREADTH": return "arrow.up.right.and.arrow.down.left"
    case "RAPID_ONWARD", "LARGE_RELAY": return "bolt.fill"
    case "PASS_THROUGH", "HIGH_FORWARDING": return "arrow.left.arrow.right"
    case "SHORT_DWELL": return "timer"
    case "FAN_IN_OUT": return "arrow.triangle.merge"
    case "STRUCTURING": return "square.split.2x2.fill"
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
    case "INVESTIGATOR_FLAG": return "shield.lefthalf.filled.slash"
    case "INVESTIGATOR_CLEARED": return "checkmark.shield.fill"
    case "VERIFIED_MERCHANT": return "checkmark.seal.fill"
    case "REGULAR_CUSTOMERS": return "storefront.fill"
    default: return "exclamationmark.circle.fill"
    }
}

/// 270° dial like a credit score: green → red gradient, tick marks, a marker at the score, the percentage in the middle.
struct ScoreDial: View {
    let score: Int?; let band: String
    @State private var progress: Double = 0
    @State private var shown = 0
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75).stroke(DS.hair, style: StrokeStyle(lineWidth: 18, lineCap: .round)).rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * progress)
                .stroke(AngularGradient(colors: [DS.safe, DS.watch, DS.review, DS.high], center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(135))
            ForEach(0..<11, id: \.self) { i in
                Capsule().fill(DS.sub.opacity(0.35)).frame(width: 2, height: i % 5 == 0 ? 10 : 5)
                    .offset(y: -78).rotationEffect(.degrees(-135 + Double(i) * 27))
            }
            Circle().fill(.white).frame(width: 22, height: 22).overlay(Circle().stroke(DS.risk(band), lineWidth: 5))
                .offset(y: -98).rotationEffect(.degrees(-135 + 270 * progress))
                .opacity(score == nil ? 0 : 1)
            VStack(spacing: 2) {
                Text(score == nil ? "—" : "\(shown)%").font(DS.number(54, .heavy)).foregroundStyle(DS.ink).contentTransition(.numericText())
                Text("RISK").font(DS.text(11, .bold)).tracking(2).foregroundStyle(DS.sub)
                Text(DS.riskLabel(band)).font(DS.text(13, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5).background(DS.risk(band), in: Capsule()).padding(.top, 4)
            }
        }
        .frame(width: 220, height: 220)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { progress = Double(score ?? 0) / 100 }
            guard let target = score, target > 0 else { return }
            Task { for v in stride(from: 0, through: target, by: max(1, target / 30)) { try? await Task.sleep(nanoseconds: 30_000_000); withAnimation { shown = v } }; shown = target }
        }
    }
}

struct ScaleBar: View {
    let score: Int?
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [DS.safe, DS.watch, DS.review, DS.high], startPoint: .leading, endPoint: .trailing).frame(height: 8).clipShape(Capsule())
                    if let score { Circle().fill(.white).frame(width: 16, height: 16).overlay(Circle().stroke(DS.ink, lineWidth: 3))
                        .offset(x: max(0, min(geo.size.width - 16, geo.size.width * CGFloat(score) / 100 - 8))) }
                }
            }.frame(height: 16)
            HStack { ForEach(["Safe", "Careful", "Risky", "High"], id: \.self) { Text($0).font(DS.text(10.5, .semibold)).foregroundStyle(DS.sub).frame(maxWidth: .infinity) } }
        }
    }
}

struct FactorLine: View {
    let factor: SafetyFactor
    private var lowers: Bool { factor.points < 0 }
    private var impact: String { abs(factor.points) >= 15 ? "High impact" : abs(factor.points) >= 8 ? "Medium impact" : factor.points == 0 ? "Rule" : "Low impact" }
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: factorIcon(factor.code)).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(lowers ? DS.safe : DS.high).frame(width: 42, height: 42)
                .background((lowers ? DS.safe : DS.high).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(factor.label).font(DS.text(15, .semibold)).foregroundStyle(DS.ink).fixedSize(horizontal: false, vertical: true)
                if !factor.detail.isEmpty { Text(factor.detail).font(DS.text(12.5)).foregroundStyle(DS.sub).fixedSize(horizontal: false, vertical: true) }
                Text(impact).font(DS.text(11, .semibold)).foregroundStyle(DS.sub)
            }
            Spacer(minLength: 8)
            if factor.points != 0 {
                Text("\(factor.points > 0 ? "+" : "−")\(abs(factor.points))").font(DS.number(15, .heavy))
                    .foregroundStyle(lowers ? DS.safe : DS.high).padding(.horizontal, 10).padding(.vertical, 5)
                    .background((lowers ? DS.safe : DS.high).opacity(0.10), in: Capsule())
            }
        }.padding(.vertical, 8)
    }
}

/// The full risk report: dial, verdict, key facts, what raises / lowers risk, how it could change.
struct RiskReportView: View {
    let model: RiskModel
    @AppStorage("tp.voice") private var voice = false
    @State private var synth = AVSpeechSynthesizer()
    private var raises: [SafetyFactor] { model.factors.filter { $0.points >= 0 } }
    private var lowers: [SafetyFactor] { model.factors.filter { $0.points < 0 } }
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.name).font(DS.display(22)).foregroundStyle(DS.ink).lineLimit(1).minimumScaleFactor(0.7)
                    if model.verified { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(hex: 0x1D9BF0)) }
                }
                Text(model.ref).font(DS.text(13)).foregroundStyle(DS.sub)
            }
            ScoreDial(score: model.score, band: model.band)
            ScaleBar(score: model.score).padding(.horizontal, 8)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.band == "low" ? "checkmark.shield.fill" : "exclamationmark.shield.fill").font(.system(size: 22)).foregroundStyle(DS.risk(model.band))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title).font(DS.text(16, .bold)).foregroundStyle(DS.ink)
                    Text(model.advice).font(DS.text(13.5)).foregroundStyle(DS.sub).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { speak() } label: { Image(systemName: "speaker.wave.2.fill").font(.system(size: 14)).foregroundStyle(DS.accent).frame(width: 34, height: 34).background(DS.accentSoft, in: Circle()) }
                    .accessibilityLabel("Read aloud")
            }
            .padding(16).background(DS.risk(model.band).opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                fact("flag.fill", "\(model.reports)", "Reports")
                fact("doc.text.fill", "\(model.records)", "Records seen")
                fact(model.member ? "person.crop.circle.badge.checkmark" : "globe", model.member ? "Member" : "External", "Account type")
                fact("gauge.with.dots.needle.50percent", "\(Int(model.confidence * 100))%", "Confidence")
            }
            if let shield = model.shield, !shield.reasons.isEmpty {
                section("For this payment") {
                    ForEach(shield.reasons, id: \.self) { r in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.fill.questionmark").foregroundStyle(DS.watch).frame(width: 22)
                            Text(r.text).font(DS.text(14)).foregroundStyle(DS.ink).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    }
                }
            }
            if !raises.isEmpty { section("What raises the risk") { ForEach(raises, id: \.code) { FactorLine(factor: $0); if $0.code != raises.last?.code { Divider() } } } }
            if !lowers.isEmpty { section("What lowers the risk") { ForEach(lowers, id: \.code) { FactorLine(factor: $0) } } }
            if model.factors.isEmpty { section("Why") { Text("No warning or trust signals were found for this account.").font(DS.text(14)).foregroundStyle(DS.sub) } }
            if !model.counterfactuals.isEmpty {
                section("How the score could change") {
                    ForEach(model.counterfactuals, id: \.self) { c in
                        HStack(alignment: .top, spacing: 10) { Image(systemName: "lightbulb.fill").foregroundStyle(DS.accent).frame(width: 22)
                            Text(c).font(DS.text(13.5)).foregroundStyle(DS.ink).fixedSize(horizontal: false, vertical: true) }.padding(.vertical, 3)
                    }
                }
            }
            Text("Advisory only. You decide whether to pay.").font(DS.text(11.5)).foregroundStyle(DS.sub)
        }
        .onAppear { if voice { speak() } }
        .onDisappear { synth.stopSpeaking(at: .immediate) }
    }
    private func fact(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.accent).frame(width: 34, height: 34).background(DS.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 1) { Text(value).font(DS.number(17)).foregroundStyle(DS.ink); Text(label).font(DS.text(11.5)).foregroundStyle(DS.sub) }
            Spacer(minLength: 0)
        }.padding(12).background(DS.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.hair))
    }
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DS.text(13, .bold)).foregroundStyle(DS.sub).textCase(.uppercase).tracking(0.6)
            VStack(alignment: .leading, spacing: 0) { content() }.padding(.horizontal, 14).padding(.vertical, 6)
                .background(DS.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.hair))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func speak() {
        synth.stopSpeaking(at: .immediate)
        let pct = model.score.map { "Risk \($0) percent." } ?? ""
        let u = AVSpeechUtterance(string: "\(model.title). \(pct) \(model.factors.prefix(3).map(\.label).joined(separator: ". "))")
        u.voice = AVSpeechSynthesisVoice(language: "en-IN"); u.rate = 0.5; synth.speak(u)
    }
}

/// Native sheet wrapping the report with pinned actions. The chosen action runs only after the sheet has closed.
enum RiskAction { case pay, report }
struct RiskSheet: View {
    let model: RiskModel; let payLabel: String
    let choose: (RiskAction?) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView(showsIndicators: false) { RiskReportView(model: model).padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12) }
            .background(DS.bg)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    PrimaryButton(title: payLabel, icon: "arrow.right.circle.fill", tint: ["high_review", "review"].contains(model.band) ? DS.risk(model.band) : DS.accent) { choose(.pay); dismiss() }
                    HStack(spacing: 10) {
                        SecondaryButton(title: L("cancel")) { choose(nil); dismiss() }
                        SecondaryButton(title: L("report"), icon: "flag.fill", tint: DS.high) { choose(.report); dismiss() }
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8).background(.ultraThinMaterial)
            }
            .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

// =====================================================================================
// MARK: - App shell
// =====================================================================================

enum ShellTab: Hashable { case home, activity, scan, check, profile }
struct PayTarget: Identifiable { let id = UUID(); let vpa: String }

struct ActivityItem: Identifiable, Hashable {
    let id: String; let title: String; let subtitle: String; let amount: String; let incoming: Bool
    let status: String; let app: String; let band: String?; let date: Date
}

struct AppShell: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tp.applock") private var appLock = false
    @AppStorage("tp.lang") private var lang = "en"
    @State private var tab: ShellTab = .home
    @State private var payTarget: PayTarget?
    @State private var external: ExternalQR?
    @State private var showHelp = false
    @State private var externalPayments: [ExternalPaymentItem] = []
    @State private var locked = false
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var items: [ActivityItem] {
        let me = session.pilotProfile?.vpa_id ?? ""
        let local = session.transfers.map { t in
            ActivityItem(id: "tp-\(t.id)", title: t.sender_vpa == me ? t.receiver_vpa : t.sender_vpa, subtitle: "Trace.Pay", amount: t.amount,
                         incoming: t.receiver_vpa == me, status: t.status, app: "Trace.Pay", band: nil, date: parseDate(t.created_at))
        }
        let ext = externalPayments.map { e in
            ActivityItem(id: "ext-\(e.id)", title: e.payee_name ?? e.payee_vpa, subtitle: e.app.capitalized, amount: e.amount, incoming: false,
                         status: e.status, app: e.app, band: e.risk_band, date: parseDate(e.created_at))
        }
        return (local + ext).sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            Group {
                switch tab {
                case .home: HomeScreen7(items: items, onPay: { payTarget = PayTarget(vpa: $0) }, onScan: { tab = .scan }, onCheck: { tab = .check },
                                        onHelp: { showHelp = true }, onSeeAll: { tab = .activity })
                case .activity: ActivityScreen7(items: items)
                case .scan: ScanScreen7(onTracePay: { payTarget = PayTarget(vpa: $0) }, onExternal: { external = ExternalQR(raw: $0) }, onClose: { tab = .home })
                case .check: CheckScreen7()
                case .profile: ProfileScreen7()
                }
            }
            .id(lang)
            .safeAreaInset(edge: .bottom) { if tab != .scan { TabBar7(tab: $tab) } }
            if locked { LockScreen7 { locked = false } }
        }
        .fullScreenCover(item: $payTarget) { t in PayFlow7(prefill: t.vpa) { payTarget = nil; Task { await refresh() } } }
        .fullScreenCover(item: $external) { e in ExternalPay7(raw: e.raw) { external = nil; Task { await refresh() } } }
        .sheet(isPresented: $showHelp) { HelpSheet7() }
        .task { await refresh() }
        .onReceive(ticker) { _ in Task { await refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appLock { locked = true }
            if phase == .active { Task { await refresh() } }
        }
    }

    @MainActor private func refresh() async {
        try? await session.refreshPilotWallet()
        try? await session.refreshPilotTransfers()
        if let ext = try? await session.externalPayments() { externalPayments = ext }
    }
}

struct TabBar7: View {
    @Binding var tab: ShellTab
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.home, "house", L("home")); item(.activity, "list.bullet.rectangle", L("activity"))
            Button { Haptic.tap(); tab = .scan } label: {
                VStack(spacing: 4) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(DS.accent, in: Circle()).shadow(color: DS.accent.opacity(0.35), radius: 10, y: 4)
                    Text(L("scan")).font(DS.text(10.5, .semibold)).foregroundStyle(DS.ink)
                }.frame(maxWidth: .infinity)
            }.accessibilityLabel(L("scan"))
            item(.check, "checkmark.shield", L("check")); item(.profile, "person.crop.circle", L("profile"))
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(DS.hair).frame(height: 1) }
    }
    private func item(_ t: ShellTab, _ icon: String, _ label: String) -> some View {
        Button { Haptic.tap(); tab = t } label: {
            VStack(spacing: 4) {
                Image(systemName: tab == t ? icon + ".fill" : icon).font(.system(size: 20, weight: .medium))
                Text(label).font(DS.text(10.5, .semibold))
            }.foregroundStyle(tab == t ? DS.accent : DS.sub).frame(maxWidth: .infinity).padding(.bottom, 4)
        }
    }
}

struct LockScreen7: View {
    let onUnlock: () -> Void
    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill").font(.system(size: 54)).foregroundStyle(DS.accent)
                Text("Trace.Pay is locked").font(DS.display(26))
                PrimaryButton(title: "Unlock", icon: "faceid") { unlock() }.frame(width: 220)
            }
        }
        .onAppear { unlock() }
    }
    private func unlock() {
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Trace.Pay") { ok, _ in if ok { DispatchQueue.main.async { onUnlock() } } }
    }
}

// =====================================================================================
// MARK: - Home
// =====================================================================================

struct HomeScreen7: View {
    @EnvironmentObject private var session: TracePaySession
    let items: [ActivityItem]
    let onPay: (String) -> Void; let onScan: () -> Void; let onCheck: () -> Void; let onHelp: () -> Void; let onSeeAll: () -> Void

    private var people: [String] {
        let me = session.pilotProfile?.vpa_id ?? ""
        let counts = Dictionary(grouping: session.transfers.filter { $0.sender_vpa == me && $0.status == "SUCCESS" }, by: { $0.receiver_vpa }).mapValues(\.count)
        return Array(counts.sorted { $0.value > $1.value }.map(\.key).prefix(8))
    }
    private let scams: [(icon: String, title: String, text: String)] = [
        ("briefcase.fill", "Task scams", "\"Like videos, earn money\", then pay to unlock. Real jobs never ask you to pay."),
        ("phone.down.fill", "Fake KYC calls", "No bank asks for your UPI PIN or OTP on a call or link."),
        ("chart.line.uptrend.xyaxis", "Investment groups", "Guaranteed high returns on WhatsApp or Telegram are scams."),
        ("arrow.down.circle.fill", "Collect requests", "You never enter a PIN to receive money."),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Text(initials(session.pilotProfile?.vpa_id ?? "TP")).font(DS.number(15, .heavy)).foregroundStyle(DS.accent)
                        .frame(width: 44, height: 44).background(DS.accentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Good to see you").font(DS.text(13)).foregroundStyle(DS.sub)
                        Text(session.pilotProfile?.full_name ?? "Trace.Pay").font(DS.text(17, .semibold)).foregroundStyle(DS.ink)
                    }
                    Spacer()
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 22)).foregroundStyle(DS.safe)
                }.padding(.top, 6)

                // Wallet card
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("trace.pay").font(DS.text(15, .heavy)).foregroundStyle(.white)
                        Spacer()
                        Label("Protected", systemImage: "checkmark.shield.fill").font(DS.text(11.5, .semibold)).foregroundStyle(DS.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(DS.lime, in: Capsule())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wallet balance").font(DS.text(12.5)).foregroundStyle(Color.white.opacity(0.75))
                        Text(rupees(session.pilotWallet?.balance ?? "0")).font(DS.number(40, .heavy)).foregroundStyle(.white).contentTransition(.numericText())
                    }
                    Text(session.pilotProfile?.vpa_id ?? "").font(DS.text(13, .medium)).foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(22)
                .background(LinearGradient(colors: [Color(hex: 0x24104F), DS.accent, Color(hex: 0x8A6BFF)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: DS.accent.opacity(0.25), radius: 18, y: 10)

                HStack(spacing: 0) {
                    action("paperplane.fill", L("pay"), DS.accent) { onPay("") }
                    action("qrcode.viewfinder", L("scan"), DS.ink) { onScan() }
                    action("magnifyingglass", L("check_id"), Color(hex: 0x0E7490)) { onCheck() }
                    action("lifepreserver.fill", L("scammed"), DS.high) { onHelp() }
                }

                Button(action: onCheck) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(DS.sub)
                        Text("Check any UPI ID before you pay").font(DS.text(15)).foregroundStyle(DS.sub)
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(DS.accent)
                    }.padding(16).background(DS.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.hair))
                }

                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("trusted")).font(DS.display(20)).foregroundStyle(DS.ink)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(people, id: \.self) { vpa in
                                    Button { onPay(vpa) } label: {
                                        VStack(spacing: 6) {
                                            Text(initials(vpa)).font(DS.number(16, .heavy)).foregroundStyle(DS.accent).frame(width: 56, height: 56).background(DS.accentSoft, in: Circle())
                                            Text(vpa.components(separatedBy: "@").first ?? vpa).font(DS.text(11.5, .medium)).foregroundStyle(DS.ink).lineLimit(1).frame(width: 66)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(L("recent")).font(DS.display(20)).foregroundStyle(DS.ink); Spacer()
                        Button(L("see_all"), action: onSeeAll).font(DS.text(14, .semibold)).foregroundStyle(DS.accent) }
                    Card(padding: 6) {
                        VStack(spacing: 0) {
                            if items.isEmpty { Text("No payments yet. Scan any UPI QR to pay safely.").font(DS.text(14)).foregroundStyle(DS.sub).padding(14) }
                            ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { i, item in
                                ActivityRow7(item: item)
                                if i < min(items.count, 5) - 1 { Divider().padding(.leading, 64) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("stay_safe")).font(DS.display(20)).foregroundStyle(DS.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(scams.indices, id: \.self) { i in
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: scams[i].icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.high)
                                        .frame(width: 40, height: 40).background(DS.high.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                    Text(scams[i].title).font(DS.text(16, .bold)).foregroundStyle(DS.ink)
                                    Text(scams[i].text).font(DS.text(13)).foregroundStyle(DS.sub).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(16).frame(width: 230, height: 190, alignment: .topLeading)
                                .background(DS.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.hair))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private func action(_ icon: String, _ label: String, _ tint: Color, run: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); run() } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(tint, in: Circle())
                Text(label).font(DS.text(12, .semibold)).foregroundStyle(DS.ink).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(PressScaleStyle())
    }
}

struct ActivityRow7: View {
    let item: ActivityItem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.incoming ? "arrow.down.left" : "arrow.up.right").font(.system(size: 15, weight: .bold))
                .foregroundStyle(item.incoming ? DS.safe : DS.accent).frame(width: 44, height: 44)
                .background((item.incoming ? DS.safe : DS.accent).opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(DS.text(15, .semibold)).foregroundStyle(DS.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.subtitle).font(DS.text(12)).foregroundStyle(DS.sub)
                    if let band = item.band { Text(DS.riskLabel(band)).font(DS.text(10.5, .bold)).foregroundStyle(DS.risk(band))
                        .padding(.horizontal, 7).padding(.vertical, 2).background(DS.risk(band).opacity(0.12), in: Capsule()) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(item.incoming ? "+" : "−")\(rupees(item.amount))").font(DS.number(15)).foregroundStyle(item.status == "SUCCESS" ? (item.incoming ? DS.safe : DS.ink) : DS.sub)
                Text(item.status == "SUCCESS" ? item.date.formatted(.relative(presentation: .named)) : item.status.capitalized).font(DS.text(11.5)).foregroundStyle(DS.sub)
            }
        }.padding(.horizontal, 10).padding(.vertical, 11)
    }
}

// =====================================================================================
// MARK: - Activity
// =====================================================================================

struct ActivityScreen7: View {
    let items: [ActivityItem]
    @State private var filter = 0
    struct DayTotal: Identifiable { let id: String; let total: Double }
    private var shown: [ActivityItem] {
        switch filter { case 1: return items.filter { $0.app == "Trace.Pay" }; case 2: return items.filter { $0.app != "Trace.Pay" }
        case 3: return items.filter { $0.status != "SUCCESS" }; default: return items }
    }
    private var week: [DayTotal] {
        let cal = Calendar.current
        return (0..<7).reversed().map { off in
            let day = cal.date(byAdding: .day, value: -off, to: Date()) ?? Date()
            let total = items.filter { !$0.incoming && $0.status == "SUCCESS" && cal.isDate($0.date, inSameDayAs: day) }.reduce(0.0) { $0 + (Double($1.amount) ?? 0) }
            return DayTotal(id: day.formatted(.dateTime.weekday(.abbreviated)), total: total)
        }
    }
    private var monthSpent: Double {
        items.filter { !$0.incoming && $0.status == "SUCCESS" && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { $0 + (Double($1.amount) ?? 0) }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: L("activity"), subtitle: "Trace.Pay and other UPI apps, together")
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Spent this month").font(DS.text(13)).foregroundStyle(DS.sub)
                        Text(rupees(monthSpent)).font(DS.number(34, .heavy)).foregroundStyle(DS.ink)
                        Chart(week) { d in BarMark(x: .value("Day", d.id), y: .value("₹", d.total)).foregroundStyle(DS.accent.gradient).cornerRadius(6) }
                            .frame(height: 140).chartYAxis(.hidden)
                    }
                }
                Picker("Filter", selection: $filter) { Text("All").tag(0); Text("Trace.Pay").tag(1); Text("Other apps").tag(2); Text("Failed").tag(3) }.pickerStyle(.segmented)
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        if shown.isEmpty { Text("Nothing here yet.").font(DS.text(14)).foregroundStyle(DS.sub).padding(14) }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                            ActivityRow7(item: item); if i < shown.count - 1 { Divider().padding(.leading, 64) }
                        }
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
    }
}

// =====================================================================================
// MARK: - Check (Truecaller-style)
// =====================================================================================

struct CheckScreen7: View {
    @EnvironmentObject private var session: TracePaySession
    @AppStorage("tp.recentChecks") private var recentRaw = ""
    @State private var query = ""
    @State private var result: RiskModel?
    @State private var busy = false
    @State private var message = ""
    @State private var reportRef: ExternalQR?
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: L("check"), subtitle: "Any UPI ID: Trace.Pay, Google Pay, PhonePe, Paytm or a bank")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DS.sub)
                    TextField("name@okaxis", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().font(DS.text(16))
                        .submitLabel(.search).onSubmit { Task { await check() } }
                    Button { if let s = UIPasteboard.general.string { query = s } } label: { Image(systemName: "doc.on.clipboard").foregroundStyle(DS.accent) }.accessibilityLabel("Paste")
                }
                .padding(16).background(DS.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.hair))
                PrimaryButton(title: L("check_id"), icon: "checkmark.shield.fill", busy: busy) { Task { await check() } }
                if !message.isEmpty { Label(message, systemImage: "exclamationmark.circle.fill").font(DS.text(13.5)).foregroundStyle(DS.high) }
                if result == nil && !recent.isEmpty {
                    Text("Recent").font(DS.text(13, .bold)).foregroundStyle(DS.sub).textCase(.uppercase)
                    ForEach(recent, id: \.self) { r in
                        Button { query = r; Task { await check() } } label: {
                            HStack { Image(systemName: "clock").foregroundStyle(DS.sub); Text(r).font(DS.text(15)).foregroundStyle(DS.ink); Spacer(); Image(systemName: "chevron.right").foregroundStyle(DS.sub) }
                                .padding(.vertical, 6)
                        }
                    }
                }
                if let result {
                    RiskReportView(model: result).id(result.id)
                    SecondaryButton(title: "Report this account", icon: "flag.fill", tint: DS.high) { reportRef = ExternalQR(raw: result.ref) }
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .sheet(item: $reportRef) { r in ReportSheetView(ref: r.raw) { _ in reportRef = nil } }
    }
    @MainActor private func check() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !q.isEmpty else { return }
        busy = true; message = ""; result = nil; defer { busy = false }
        do {
            let l = try await session.lookup(ref: q); result = RiskModel(l)
            recentRaw = ([l.ref] + recent.filter { $0 != l.ref }).prefix(6).joined(separator: "\n")
        } catch { message = error.localizedDescription }
    }
}

// =====================================================================================
// MARK: - Scan
// =====================================================================================

struct ScanScreen7: View {
    let onTracePay: (String) -> Void; let onExternal: (String) -> Void; let onClose: () -> Void
    @State private var key = 0
    @State private var message = ""
    var body: some View {
        ZStack(alignment: .top) {
            QRScannerSheet(onScan: { raw in
                if let id = TracePayID.normalize(raw) { onTracePay(id); key += 1 }
                else if UPIQR.parse(raw) != nil { onExternal(raw); key += 1 }
                else { message = "That QR has no UPI ID."; Haptic.error(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { message = ""; key += 1 } }
            }, onClose: onClose)
            .id(key).ignoresSafeArea()
            if !message.isEmpty {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(DS.text(14, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10).background(DS.high, in: Capsule()).padding(.top, 70)
            }
        }
    }
}

// =====================================================================================
// MARK: - Pay a Trace.Pay member
// =====================================================================================

struct PayFlow7: View {
    @EnvironmentObject private var session: TracePaySession
    let prefill: String; let onDone: () -> Void
    enum Step { case recipient, amount, cooling, sending, done }
    @AppStorage("tp.cooling") private var coolingOn = true
    @AppStorage("tp.coolingMinutes") private var coolingMinutes = 1
    @AppStorage("tp.dailyLimit") private var dailyLimit = 50000.0
    @State private var step: Step = .recipient
    @State private var input = ""
    @State private var recipient: PilotRecipient?
    @State private var amount = ""
    @State private var risk: RiskModel?
    @State private var pending: RiskAction?
    @State private var reportRef: ExternalQR?
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
        return session.transfers.filter { $0.sender_vpa == me && $0.status == "SUCCESS" && Calendar.current.isDateInToday(parseDate($0.created_at)) }.reduce(0) { $0 + (Double($1.amount) ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onDone() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink).frame(width: 40, height: 40).background(DS.card, in: Circle()) }
                Spacer()
                Text(step == .done ? "" : L("pay")).font(DS.text(17, .semibold))
                Spacer(); Color.clear.frame(width: 40, height: 40)
            }.padding(.horizontal, 20).padding(.top, 8)
            Group {
                switch step {
                case .recipient: recipientStep
                case .amount: amountStep
                case .cooling: coolingStep
                case .sending: VStack(spacing: 14) { ProgressView().scaleEffect(1.3); Text("Confirm with Face ID or passcode").font(DS.text(15)).foregroundStyle(DS.sub) }.frame(maxHeight: .infinity)
                case .done: doneStep
                }
            }.padding(.horizontal, 20).frame(maxHeight: .infinity, alignment: .top)
        }
        .background(DS.bg.ignoresSafeArea())
        .sheet(item: $risk, onDismiss: runPending) { m in RiskSheet(model: m, payLabel: "Pay \(rupees(amount))") { pending = $0 } }
        .sheet(item: $reportRef) { r in ReportSheetView(ref: r.raw) { _ in reportRef = nil } }
        .onReceive(tick) { _ in if step == .cooling && remaining > 0 { remaining -= 1; if remaining == 0 { authenticate() } } }
        .task { if !prefill.isEmpty { input = prefill; await findRecipient() } }
    }

    private var recipientStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who are you paying?").font(DS.display(30)).padding(.top, 20)
            HStack(spacing: 10) {
                Image(systemName: "at").foregroundStyle(DS.sub)
                TextField("name@tracepay", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().font(DS.text(17))
            }.padding(16).background(DS.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.hair))
            if !message.isEmpty { Label(message, systemImage: "exclamationmark.circle.fill").font(DS.text(13.5)).foregroundStyle(DS.high) }
            PrimaryButton(title: L("continue"), busy: busy) { Task { await findRecipient() } }.disabled(input.isEmpty)
            Text("Paying a Google Pay, PhonePe or Paytm QR? Use Scan.").font(DS.text(13)).foregroundStyle(DS.sub)
        }
    }

    private var amountStep: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(initials(recipient?.vpa_id ?? "TP")).font(DS.number(18, .heavy)).foregroundStyle(DS.accent).frame(width: 60, height: 60).background(DS.accentSoft, in: Circle())
                Text(recipient?.display_name ?? "").font(DS.text(17, .semibold))
                Text(recipient?.vpa_id ?? "").font(DS.text(13)).foregroundStyle(DS.sub)
                if isNewPayee { Label("First payment to this person", systemImage: "sparkles").font(DS.text(12, .semibold)).foregroundStyle(DS.watch) }
            }.padding(.top, 10)
            Text(amount.isEmpty ? "₹0" : "₹\(amount)").font(DS.number(56, .heavy)).foregroundStyle(DS.ink).contentTransition(.numericText()).animation(.snappy, value: amount)
            Text("Balance \(rupees(session.pilotWallet?.balance ?? "0")) · today \(rupees(spentToday)) of \(rupees(dailyLimit))").font(DS.text(12.5)).foregroundStyle(DS.sub)
            if !message.isEmpty { Text(message).font(DS.text(13.5)).foregroundStyle(DS.high).multilineTextAlignment(.center) }
            Spacer(minLength: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { k in
                    Button { press(k) } label: {
                        Group { if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) } }
                            .font(DS.number(26, .semibold)).foregroundStyle(DS.ink).frame(maxWidth: .infinity).frame(height: 56)
                            .background(DS.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(PressScaleStyle())
                }
            }
            PrimaryButton(title: busy ? "Checking safety…" : L("continue"), icon: "checkmark.shield.fill", busy: busy) { Task { await assess() } }
                .disabled(value <= 0).opacity(value > 0 ? 1 : 0.5).padding(.bottom, 8)
        }
    }

    private var coolingStep: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(DS.accentSoft, lineWidth: 12)
                Circle().trim(from: 0, to: CGFloat(remaining) / CGFloat(max(1, coolingMinutes * 60)))
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: remaining)
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60)).font(DS.number(42, .heavy))
            }.frame(width: 190, height: 190)
            Text("Take a moment").font(DS.display(26))
            Text("This is your first payment of \(rupees(amount)) to this person. Scammers rush you. Is this someone you know?")
                .font(DS.text(15)).foregroundStyle(DS.sub).multilineTextAlignment(.center)
            SecondaryButton(title: L("cancel")) { step = .amount }
            Spacer()
        }
    }

    private var doneStep: some View {
        let ok = result?.status == "SUCCESS"
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill").font(.system(size: 88)).foregroundStyle(ok ? DS.safe : DS.high).symbolEffect(.bounce, value: ok)
            Text(ok ? "Paid \(rupees(result?.amount ?? amount))" : "Payment not completed").font(DS.display(28))
            Text(ok ? "to \(recipient?.display_name ?? recipient?.vpa_id ?? "")" : (result?.failure_reason ?? "No money moved. You can try again safely."))
                .font(DS.text(15)).foregroundStyle(DS.sub).multilineTextAlignment(.center)
            if let ref = result?.transfer_ref { Text(ref).font(.system(size: 12, design: .monospaced)).foregroundStyle(DS.sub) }
            Spacer()
            PrimaryButton(title: "Done") { onDone() }.padding(.bottom, 8)
        }
    }

    private func press(_ k: String) {
        Haptic.tap(); message = ""
        if k == "⌫" { if !amount.isEmpty { amount.removeLast() }; return }
        if k == "." && amount.contains(".") { return }
        if let dot = amount.firstIndex(of: "."), amount.distance(from: dot, to: amount.endIndex) > 2 { return }
        if amount.count < 9 { amount += k }
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
        case .pay: if coolingOn && isNewPayee && (Double(amount) ?? 0) >= 5000 { remaining = coolingMinutes * 60; step = .cooling } else { authenticate() }
        case .report: reportRef = ExternalQR(raw: recipient?.vpa_id ?? input)
        case .none: break
        }
    }

    private func authenticate() {
        step = .sending
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Confirm payment of \(rupees(amount))") { ok, err in
            DispatchQueue.main.async { if ok { Task { await send() } } else { step = .amount; message = err?.localizedDescription ?? "Not confirmed." } }
        }
    }

    @MainActor private func send() async {
        guard let r = recipient else { return }
        do {
            result = try await session.makePilotTransfer(receiverVPA: r.vpa_id, amount: value, note: "", idempotencyKey: key)
            if result?.status == "SUCCESS" { Haptic.success() } else { Haptic.error() }
            step = .done
            try? await session.refreshPilotWallet(); try? await session.refreshPilotTransfers()
        } catch { message = "\(error.localizedDescription) Retrying is safe."; step = .amount }
    }
}

// =====================================================================================
// MARK: - Pay any UPI QR (Google Pay, PhonePe, Paytm, BHIM)
// =====================================================================================

struct UPIApp: Identifiable { let id: String; let name: String; let schemes: [String]; let store: String; let tint: Color }

struct ExternalPay7: View {
    @EnvironmentObject private var session: TracePaySession
    @Environment(\.scenePhase) private var scenePhase
    let raw: String; let onDone: () -> Void
    enum Prompt: Identifiable { case confirm, notInstalled; var id: Int { self == .confirm ? 0 : 1 } }
    private let catalogue: [UPIApp] = [
        UPIApp(id: "gpay", name: "Google Pay", schemes: ["gpay://upi/pay", "tez://upi/pay"], store: "https://apps.apple.com/in/app/google-pay/id1193357041", tint: Color(hex: 0x1A73E8)),
        UPIApp(id: "phonepe", name: "PhonePe", schemes: ["phonepe://pay", "phonepe://upi/pay"], store: "https://apps.apple.com/in/app/phonepe/id1170055821", tint: Color(hex: 0x5F259F)),
        UPIApp(id: "paytm", name: "Paytm", schemes: ["paytmmp://pay", "paytm://upi/pay"], store: "https://apps.apple.com/in/app/paytm/id473941634", tint: Color(hex: 0x00BAF2)),
        UPIApp(id: "bhim", name: "BHIM", schemes: ["bhim://upi/pay", "upi://pay"], store: "https://apps.apple.com/in/app/bhim/id1200315258", tint: Color(hex: 0x0B6E4F)),
    ]
    @State private var amount = ""
    @State private var chosen: UPIApp?
    @State private var risk: RiskModel?
    @State private var look: SafetyLookup?
    @State private var pending: RiskAction?
    @State private var reportRef: ExternalQR?
    @State private var prompt: Prompt?
    @State private var awaiting = false
    @State private var busy = false
    @State private var message = ""
    @State private var recorded: String?
    private var qr: [String: String]? { UPIQR.parse(raw) }
    private func installed(_ app: UPIApp) -> Bool { app.schemes.contains { s in URL(string: s).map { UIApplication.shared.canOpenURL($0) } ?? false } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button(action: onDone) { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink).frame(width: 40, height: 40).background(DS.card, in: Circle()) }
                    Spacer(); Text("Pay any UPI QR").font(DS.text(17, .semibold)); Spacer(); Color.clear.frame(width: 40, height: 40)
                }.padding(.top, 8)
                if let qr {
                    VStack(spacing: 8) {
                        Text(initials(qr["pa"] ?? "UP")).font(DS.number(20, .heavy)).foregroundStyle(DS.accent).frame(width: 64, height: 64).background(DS.accentSoft, in: Circle())
                        Text(qr["pn"] ?? qr["pa"] ?? "").font(DS.display(24)).multilineTextAlignment(.center)
                        Text(qr["pa"] ?? "").font(DS.text(13.5)).foregroundStyle(DS.sub)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    HStack(spacing: 6) {
                        Text("₹").font(DS.number(36, .heavy)).foregroundStyle(DS.sub)
                        TextField("0", text: $amount).keyboardType(.decimalPad).font(DS.number(44, .heavy)).foregroundStyle(DS.ink)
                    }.padding(.horizontal, 18).padding(.vertical, 10).background(DS.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.hair))
                    Text("Pay with").font(DS.text(13, .bold)).foregroundStyle(DS.sub).textCase(.uppercase)
                    VStack(spacing: 10) {
                        ForEach(catalogue) { app in
                            let ok = installed(app)
                            Button { chosen = app; Task { await check() } } label: {
                                HStack(spacing: 14) {
                                    Text(String(app.name.prefix(1))).font(DS.number(18, .heavy)).foregroundStyle(.white).frame(width: 44, height: 44).background(app.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name).font(DS.text(16, .semibold)).foregroundStyle(DS.ink)
                                        Text(ok ? "Installed" : "Not installed").font(DS.text(12)).foregroundStyle(ok ? DS.safe : DS.sub)
                                    }
                                    Spacer()
                                    if busy && chosen?.id == app.id { ProgressView() } else { Image(systemName: "chevron.right").foregroundStyle(DS.sub) }
                                }.padding(14).background(DS.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.hair))
                            }.disabled(busy)
                        }
                    }
                    if !message.isEmpty { Label(message, systemImage: "exclamationmark.circle.fill").font(DS.text(13.5)).foregroundStyle(DS.high) }
                    if let recorded {
                        Label(recorded == "SUCCESS" ? "Payment recorded in your activity" : "Recorded as \(recorded.lowercased())", systemImage: "checkmark.circle.fill")
                            .font(DS.text(14, .semibold)).foregroundStyle(DS.safe)
                    }
                    Label("Trace.Pay checks the account first. Your UPI PIN is only entered in your UPI app.", systemImage: "lock.shield").font(DS.text(12.5)).foregroundStyle(DS.sub)
                } else {
                    Text("This QR has no valid UPI ID.").font(DS.text(15)).foregroundStyle(DS.high)
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(DS.bg.ignoresSafeArea())
        .onAppear { amount = qr?["am"] ?? "" }
        .sheet(item: $risk, onDismiss: runPending) { m in RiskSheet(model: m, payLabel: "Pay \(rupees(amount)) with \(chosen?.name ?? "UPI")") { pending = $0 } }
        .sheet(item: $reportRef) { r in ReportSheetView(ref: r.raw) { _ in reportRef = nil } }
        .onChange(of: scenePhase) { _, phase in if phase == .active && awaiting { awaiting = false; prompt = .confirm } }
        .alert(item: $prompt) { p in
            switch p {
            case .confirm:
                return Alert(title: Text("Did the payment go through?"), message: Text("UPI apps on iPhone don't report back, so confirm to record it."),
                             primaryButton: .default(Text("Yes, I paid")) { record("SUCCESS") }, secondaryButton: .cancel(Text("No")) { record("CANCELLED") })
            case .notInstalled:
                return Alert(title: Text("\(chosen?.name ?? "This app") isn't installed"), message: Text("The UPI ID has been copied. Pay in any UPI app, or install this one."),
                             primaryButton: .default(Text("Get \(chosen?.name ?? "app")")) { if let s = chosen?.store, let u = URL(string: s) { UIApplication.shared.open(u) } },
                             secondaryButton: .cancel(Text("OK")))
            }
        }
    }

    @MainActor private func check() async {
        guard let v = Decimal(string: amount), v > 0 else { message = "Enter the amount first."; return }
        busy = true; message = ""; defer { busy = false }
        do { let l = try await session.lookup(ref: raw, amount: v); look = l; risk = RiskModel(l) } catch { message = error.localizedDescription }
    }

    private func runPending() {
        let action = pending; pending = nil
        switch action {
        case .pay: launch()
        case .report: reportRef = ExternalQR(raw: qr?["pa"] ?? raw)
        case .none: break
        }
    }

    /// Open the chosen UPI app with the payment details. Uses the first scheme the phone can open.
    private func launch() {
        guard let qr, let app = chosen else { return }
        let items = [URLQueryItem(name: "pa", value: qr["pa"]), URLQueryItem(name: "pn", value: look?.display_name ?? qr["pn"] ?? qr["pa"]),
                     URLQueryItem(name: "am", value: amount), URLQueryItem(name: "cu", value: "INR"), URLQueryItem(name: "tn", value: qr["tn"] ?? "Checked with Trace.Pay")]
        let urls: [URL] = app.schemes.compactMap { s in var c = URLComponents(string: s); c?.queryItems = items; return c?.url }
        guard let url = urls.first(where: { UIApplication.shared.canOpenURL($0) }) else {
            UIPasteboard.general.string = qr["pa"]; prompt = .notInstalled; return
        }
        UIApplication.shared.open(url, options: [:]) { ok in
            DispatchQueue.main.async {
                if ok { awaiting = true } else { UIPasteboard.general.string = qr["pa"]; prompt = .notInstalled }
            }
        }
    }

    private func record(_ status: String) {
        guard let qr else { return }
        Task {
            do {
                try await session.recordExternalPayment(ExternalPaymentBody(payee: qr["pa"] ?? raw, payee_name: look?.display_name ?? qr["pn"], amount: amount,
                    app: chosen?.id ?? "upi", status: status, source: "manual", upi_txn_id: nil, risk_score: look?.score, risk_band: look?.band))
                recorded = status; if status == "SUCCESS" { Haptic.success() }
            } catch { message = error.localizedDescription }
        }
    }
}

// =====================================================================================
// MARK: - Help (I've been scammed)
// =====================================================================================

struct HelpSheet7: View {
    @State private var scammer = ""
    @State private var report: ExternalQR?
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "lifepreserver.fill").font(.system(size: 40)).foregroundStyle(DS.high).padding(.top, 24)
                Text("Act within the first hour").font(DS.display(28))
                Text("Money reported quickly is the easiest to freeze. Do these now:").font(DS.text(15)).foregroundStyle(DS.sub)
                step("phone.fill", "Call 1930", "National cyber-crime helpline. Share the amount, time and UPI ID you paid.", "tel://1930")
                step("doc.text.fill", "File a complaint", "Report at cybercrime.gov.in. Keep screenshots of the chat and the payment.", "https://cybercrime.gov.in")
                step("building.columns.fill", "Call your bank", "Ask them to block the transaction and raise a dispute. Use the number on your card or bank app.", nil)
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Warn others").font(DS.text(16, .bold))
                        TextField("Scammer's UPI ID", text: $scammer).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(12).background(DS.bg, in: RoundedRectangle(cornerRadius: 12))
                        PrimaryButton(title: "Report on Trace.Pay", icon: "flag.fill", tint: DS.high) { report = ExternalQR(raw: scammer) }
                            .disabled(UPIQR.parse(scammer) == nil).opacity(UPIQR.parse(scammer) == nil ? 0.5 : 1)
                    }
                }
                Text("Never share your UPI PIN or OTP, and never install screen-sharing apps when a caller asks.").font(DS.text(12.5)).foregroundStyle(DS.sub)
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(DS.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .sheet(item: $report) { r in ReportSheetView(ref: r.raw) { _ in report = nil } }
    }
    private func step(_ icon: String, _ title: String, _ text: String, _ link: String?) -> some View {
        Button { if let link, let url = URL(string: link) { UIApplication.shared.open(url) } } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background(DS.high, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(DS.text(16, .bold)).foregroundStyle(DS.ink)
                    Text(text).font(DS.text(13.5)).foregroundStyle(DS.sub).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if link != nil { Image(systemName: "arrow.up.right").foregroundStyle(DS.sub) }
            }.padding(16).background(DS.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.hair))
        }.disabled(link == nil)
    }
}

// =====================================================================================
// MARK: - Profile
// =====================================================================================

func makeQR(_ text: String) -> UIImage? {
    let f = CIFilter.qrCodeGenerator(); f.message = Data(text.utf8); f.correctionLevel = "M"
    guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
    return UIImage(cgImage: cg)
}

struct ProfileScreen7: View {
    @EnvironmentObject private var session: TracePaySession
    @AppStorage("tp.cooling") private var coolingOn = true
    @AppStorage("tp.coolingMinutes") private var coolingMinutes = 1
    @AppStorage("tp.dailyLimit") private var dailyLimit = 50000.0
    @AppStorage("tp.applock") private var appLock = false
    @AppStorage("tp.voice") private var voice = false
    @AppStorage("tp.haptics") private var haptics = true
    @AppStorage("tp.lang") private var lang = "en"
    @State private var showQR = false
    @State private var confirmLogout = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: L("profile"))
                Card {
                    HStack(spacing: 14) {
                        Text(initials(session.pilotProfile?.vpa_id ?? "TP")).font(DS.number(20, .heavy)).foregroundStyle(DS.accent).frame(width: 60, height: 60).background(DS.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.pilotProfile?.full_name ?? "").font(DS.text(18, .semibold))
                            Text(session.pilotProfile?.vpa_id ?? "").font(DS.text(13.5)).foregroundStyle(DS.sub)
                        }
                        Spacer()
                        Button { showQR = true } label: { Image(systemName: "qrcode").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background(DS.accent, in: Circle()) }
                            .accessibilityLabel("My QR")
                    }
                }
                group("Payment safety") {
                    Toggle(isOn: $coolingOn) { row("hourglass", "Cooling-off for new payees", "Wait before a first payment of ₹5,000 or more") }
                    if coolingOn { Picker("Wait", selection: $coolingMinutes) { Text("1 min").tag(1); Text("5 min").tag(5); Text("10 min").tag(10) }.pickerStyle(.segmented).padding(.vertical, 6) }
                    Divider()
                    Stepper(value: $dailyLimit, in: 1000...100000, step: 1000) { row("gauge.with.needle", "Daily limit", rupees(dailyLimit)) }
                    Divider()
                    Toggle(isOn: $voice) { row("speaker.wave.2.fill", "Read risk aloud", "Speaks the verdict on the risk report") }
                }
                group("App") {
                    Toggle(isOn: $appLock) { row("lock.fill", "App lock", "Face ID or passcode when you return") }
                    Divider()
                    Toggle(isOn: $haptics) { row("hand.tap.fill", "Haptics", "Vibration feedback") }
                    Divider()
                    HStack { row("globe", "Language", ""); Spacer()
                        Picker("Language", selection: $lang) { ForEach(Lang.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) } }.tint(DS.accent) }
                }
                SecondaryButton(title: "Sign out", icon: "rectangle.portrait.and.arrow.right", tint: DS.high) { confirmLogout = true }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .sheet(isPresented: $showQR) { MyQR7() }
        .confirmationDialog("Sign out of Trace.Pay?", isPresented: $confirmLogout, titleVisibility: .visible) { Button("Sign out", role: .destructive) { session.lock() } }
    }
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(DS.text(13, .bold)).foregroundStyle(DS.sub).textCase(.uppercase)
            VStack(spacing: 10) { content() }.padding(16).tint(DS.accent)
                .background(DS.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.hair))
        }
    }
    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.accent).frame(width: 34, height: 34).background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.text(15, .medium)).foregroundStyle(DS.ink)
                if !sub.isEmpty { Text(sub).font(DS.text(12)).foregroundStyle(DS.sub) }
            }
        }
    }
}

struct MyQR7: View {
    @EnvironmentObject private var session: TracePaySession
    var body: some View {
        let vpa = session.pilotProfile?.vpa_id ?? ""
        let name = session.pilotProfile?.full_name ?? ""
        let payload = "upi://pay?pa=\(vpa)&pn=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)&cu=INR"
        let image = makeQR(payload)
        VStack(spacing: 16) {
            Text("Scan to pay me").font(DS.display(26)).padding(.top, 28)
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 230, height: 230).padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DS.hair))
            }
            Text(name).font(DS.text(18, .semibold)); Text(vpa).font(DS.text(14)).foregroundStyle(DS.sub)
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("My Trace.Pay QR", image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up").font(DS.text(16, .semibold)).foregroundStyle(.white).padding(.horizontal, 30).padding(.vertical, 14).background(DS.accent, in: Capsule())
                }
            }
            Spacer()
        }.frame(maxWidth: .infinity).background(DS.bg.ignoresSafeArea()).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

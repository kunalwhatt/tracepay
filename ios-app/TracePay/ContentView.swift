import SwiftUI
import Foundation
import CoreImage.CIFilterBuiltins
import LocalAuthentication
import PhotosUI
import UIKit

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
                MainAppScreen()
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
            idempotencyKey = UUID().uuidString   // a new attempt starts here
            stage = .review
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

    private var qrPayload: String {
        let vpa = session.pilotProfile?.vpa_id ?? ""
        let name = (session.pilotProfile?.full_name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "tracepay://pay?pa=\(vpa)&pn=\(name)"
    }

    var body: some View {
        if mode == 0 { cameraView } else { qrBody }
    }

    /// Tapping Scan opens the camera straight away; the animated frame and "Import from photos" live inside it.
    private var cameraView: some View {
        ZStack(alignment: .top) {
            QRScannerSheet(onScan: { raw in
                if let id = TracePayID.normalize(raw) {
                    message = ""; payPrefill = id; tab = .pay
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

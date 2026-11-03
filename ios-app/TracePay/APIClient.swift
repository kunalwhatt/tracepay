import SwiftUI
import Foundation
import LocalAuthentication
import Combine
import Security

// MARK: - Keychain session storage

enum LocalUnlockStore {
    private static let service = "tech.tracepay.ios.localunlock"
    private static let emailKey = "device_account_email"
    private static let tokenKey = "access_token"

    static var savedEmail: String? { read(account: emailKey) }
    static var savedToken: String? { read(account: tokenKey) }
    static var hasSavedSession: Bool { savedToken != nil && savedEmail != nil }
    static var hasDeviceAccount: Bool { savedEmail != nil }

    static func claimDeviceAccount(email: String) { save(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), account: emailKey) }
    static func saveSession(token: String, email: String) { claimDeviceAccount(email: email); save(token, account: tokenKey) }
    static func clearSavedSession() { delete(account: tokenKey); delete(account: emailKey) }
    /// Drop only the token (expired session) while keeping the device-bound account email.
    static func clearToken() { delete(account: tokenKey) }

    private static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
    private static func read(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func delete(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}


struct APIError: Decodable {
    let detail: String?
    private struct FieldError: Decodable { let msg: String?; let loc: [AnyCodableKey]? }
    private enum Keys: String, CodingKey { case detail }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let text = try? c.decode(String.self, forKey: .detail) { detail = text; return }
        if let list = try? c.decode([FieldError].self, forKey: .detail) {
            detail = list.map { e in
                let field = e.loc?.last?.text.replacingOccurrences(of: "_", with: " ").capitalized ?? ""
                return field.isEmpty ? (e.msg ?? "Invalid value") : "\(field): \(e.msg ?? "invalid")"
            }.joined(separator: "; ")
            return
        }
        detail = nil
    }
}
struct AnyCodableKey: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s } else if let i = try? c.decode(Int.self) { text = String(i) } else { text = "" }
    }
}
struct AuthResponse: Decodable { let access_token: String; let token_type: String; let role: String }
struct ShieldReason: Decodable, Hashable { let code: String; let severity: Int; let text: String }
struct ShieldInfo: Decodable, Hashable { let level: String; let reasons: [ShieldReason] }

struct RiskResponse: Decodable, Identifiable {
    var id: Int { assessment_id }
    let shield: ShieldInfo?
    let assessment_id: Int
    let recipient_ref: String
    let level: String
    let reasons: [String]
    let observed_transaction_count: Int
    let data_as_of: Date
    let rule_version: String
    let disclaimer: String
}
struct PaymentIntentResponse: Decodable {
    let id: Int
    let recipient_ref: String
    let amount: Decimal?
    let currency: String
    let status: String
    let created_at: Date
    let disclaimer: String

    private enum CodingKeys: String, CodingKey { case id, recipient_ref, amount, currency, status, created_at, disclaimer }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        recipient_ref = try container.decode(String.self, forKey: .recipient_ref)
        if let number = try? container.decode(Decimal.self, forKey: .amount) { amount = number }
        else if let string = try? container.decode(String.self, forKey: .amount) { amount = Decimal(string: string) }
        else { amount = nil }
        currency = (try? container.decode(String.self, forKey: .currency)) ?? "INR"
        status = (try? container.decode(String.self, forKey: .status)) ?? "unknown"
        created_at = try container.decode(Date.self, forKey: .created_at)
        disclaimer = (try? container.decode(String.self, forKey: .disclaimer)) ?? "Handoff status only. This does not confirm that a payment was completed."
    }
}
private struct PaymentIntentRequest: Encodable {
    let assessment_id: Int
    let recipient_ref: String
    let amount: Decimal?
    let note: String
}

struct PilotWallet: Decodable {
    let wallet_id: Int
    let vpa_id: String
    let balance: String
    let currency: String
    let status: String
    let ledger_type: String
    let disclaimer: String
}
struct PilotTransferResponse: Decodable {
    let id: Int
    let transfer_ref: String
    let sender_vpa: String
    let receiver_vpa: String
    let amount: String
    let currency: String
    let note: String
    let status: String
    let mode: String
    let created_at: String
    let settled: Bool
    let disclaimer: String
    let failure_reason: String?
}
private struct PilotTransferRequest: Encodable {
    let receiver_vpa: String
    let amount: Decimal
    let note: String
    let idempotency_key: String
}

private struct UserResponse: Decodable { let id: Int; let email: String; let role: String }
struct PilotProfile: Decodable {
    let id: Int
    let user_id: Int
    let email: String?
    let full_name: String
    let date_of_birth: String
    let vpa_id: String
    let bank_name: String
    let account_last4: String
    let participant_type: String
    let selfie_status: String
    let gender: String
    let face_count: Int
    let created_at: Date
}
private struct PilotProfileEnvelope: Decodable { let profile: PilotProfile? }
struct PilotRecipient: Decodable {
    let registered: Bool
    let recipient_type: String
    let display_name: String
    let vpa_id: String
    let profile_id: Int
    let message: String
}
struct SystemService: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let role: String
    let technology: String
}
struct ResearchContextStatus: Decodable {
    let provenance_first: Bool
    let explicit_evidence_gaps: Bool
    let risk_is_advisory: Bool
    let graph_scope: String
}
struct SystemObservability: Decodable {
    let checked_at: String
    let services: [SystemService]
    let research_context: ResearchContextStatus
}
private struct ClientEventRequest: Encodable {
    let event_type: String
    let object_ref: String?
    let screen: String?
    let outcome: String?
}
private struct ClientEventAck: Decodable { let accepted: Bool; let event_id: Int }
private struct PilotProfileRequest: Encodable {
    let full_name: String
    let date_of_birth: String
    let vpa_id: String?
    let bank_name: String
    let account_last4: String
    let participant_type: String
    let consent_profile: Bool
    let consent_pilot_ledger: Bool
}
private struct HandoffResponse: Decodable { let id: Int; let status: String; let payment_completed: Bool; let message: String }
private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

@MainActor
final class TracePaySession: ObservableObject {
    @Published var token: String? = nil
    @Published var email: String? = nil
    @Published var isBusy = false
    @Published var errorMessage: String? = nil
    @Published var pilotProfile: PilotProfile? = nil
    @Published var pilotWallet: PilotWallet? = nil
    @Published var transfers: [PilotTransferResponse] = []
    @Published var profileLoaded = false
    /// Set when the server rejects the session (expired or revoked token); the root view shows a sign-in prompt.
    @Published var sessionExpired = false

    /// Expiry read from the JWT itself, so the "Session mm:ss" chip is accurate even after app restarts.
    var tokenExpiry: Date? { token.flatMap(JWTClaims.expiry) }

    /// Renew the access token when less than five minutes remain. Expired tokens cannot be renewed.
    func refreshSessionIfNeeded() async {
        guard let expiry = tokenExpiry else { return }
        let remaining = expiry.timeIntervalSinceNow
        guard remaining > 0, remaining < 300 else { return }
        do {
            let result: AuthResponse = try await send("/api/v1/auth/refresh", method: "POST", body: Optional<String>.none, authenticated: true)
            token = result.access_token
            if let email { LocalUnlockStore.saveSession(token: result.access_token, email: email) }
        } catch { /* send() already handles a 401 by expiring the session */ }
    }

    private func expireSession() {
        token = nil; profileLoaded = false; pilotProfile = nil; pilotWallet = nil; transfers = []
        LocalUnlockStore.clearToken()   // an expired token must not be offered for Face ID unlock again
        sessionExpired = true
    }

    private var baseURL: URL {
        // The build setting is copied into Info.plist. If it is missing, empty or unexpanded,
        // fall back to the always-on Azure API rather than 127.0.0.1 (which is the phone itself).
        let fallback = "https://tracepay-api.livelystone-3bd01cb7.centralindia.azurecontainerapps.io"
        let raw = (Bundle.main.object(forInfoDictionaryKey: "TRACEPAY_API_BASE_URL") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (raw.hasPrefix("http") && !raw.contains("$(")) ? raw : fallback
        #if DEBUG
        print("[Trace.Pay] API base URL: \(value)")
        #endif
        return URL(string: value) ?? URL(string: fallback)!
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = options
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 timestamp: \(value)")
        }
        return decoder
    }()

    func login(email: String, password: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result: AuthResponse = try await send("/api/v1/auth/login", method: "POST", body: ["email": cleanEmail, "password": password], authenticated: false)
        token = result.access_token
        sessionExpired = false
        profileLoaded = false
        pilotProfile = nil
        pilotWallet = nil
        self.email = cleanEmail
        LocalUnlockStore.claimDeviceAccount(email: cleanEmail)
        LocalUnlockStore.saveSession(token: result.access_token, email: cleanEmail)
    }

    func register(email: String, password: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let _: UserResponse = try await send("/api/v1/auth/register", method: "POST", body: ["email": cleanEmail, "password": password], authenticated: false)
        // Claim the device immediately after successful registration, before the follow-up login.
        LocalUnlockStore.claimDeviceAccount(email: cleanEmail)
        try await login(email: cleanEmail, password: password)
    }

    func restoreSavedSession() async throws {
        guard let savedToken = LocalUnlockStore.savedToken, let savedEmail = LocalUnlockStore.savedEmail else {
            throw NSError(domain: "Trace.Pay", code: 401, userInfo: [NSLocalizedDescriptionKey: "No saved session is available."])
        }
        token = savedToken
        profileLoaded = false
        pilotProfile = nil
        pilotWallet = nil
        email = savedEmail
        do {
            let _: UserResponse = try await send("/api/v1/auth/me", method: "GET", body: Optional<String>.none, authenticated: true)
        } catch {
            token = nil
            email = nil
            throw error
        }
    }

    func refreshPilotProfile() async throws {
        let result: PilotProfileEnvelope = try await send("/api/v1/pilot/profile", method: "GET", body: Optional<String>.none, authenticated: true)
        pilotProfile = result.profile
        if result.profile != nil {
            pilotWallet = try await send("/api/v1/pilot/wallet", method: "GET", body: Optional<String>.none, authenticated: true)
        } else {
            pilotWallet = nil
        }
        profileLoaded = true
    }

    func createPilotProfile(fullName: String, dateOfBirth: String, gender: String, photoData: Data, consentProfile: Bool, consentLedger: Bool) async throws {
        guard let token else { throw NSError(domain: "Trace.Pay", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please sign in again."]) }
        let boundary = "TracePay-" + UUID().uuidString
        var request = URLRequest(url: baseURL.appending(path: "api/v1/pilot/profile"))
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("full_name", fullName); field("date_of_birth", dateOfBirth); field("gender", gender)
        field("consent_profile", consentProfile ? "true" : "false"); field("consent_pilot_ledger", consentLedger ? "true" : "false")
        let isVideo = photoData.count > 12 && photoData.subdata(in: 4..<8) == Data("ftyp".utf8)
        body.append(Data((isVideo ? "--\(boundary)\r\nContent-Disposition: form-data; name=\"face_video\"; filename=\"traceid.mp4\"\r\nContent-Type: video/mp4\r\n\r\n"
                                  : "--\(boundary)\r\nContent-Disposition: form-data; name=\"face_photo\"; filename=\"profile.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n").utf8))
        body.append(photoData); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? decoder.decode(APIError.self, from: data).detail) ?? String(data: data, encoding: .utf8) ?? "Profile creation failed (HTTP \(http.statusCode))"
            throw NSError(domain: "Trace.Pay API", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        try await refreshPilotProfile()
    }

    func refreshPilotWallet() async throws {
        pilotWallet = try await send("/api/v1/pilot/wallet", method: "GET", body: Optional<String>.none, authenticated: true)
    }

    func refreshPilotTransfers() async throws {
        transfers = try await send("/api/v1/pilot/transfers?limit=100", method: "GET", body: Optional<String>.none, authenticated: true)
    }

    func lookupPilotRecipient(vpa: String) async throws -> PilotRecipient {
        let clean = vpa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try await send("/api/v1/pilot/recipients/\(clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean)", method: "GET", body: Optional<String>.none, authenticated: true)
    }

    func fetchObservability() async throws -> SystemObservability {
        try await send("/api/v1/pilot/observability", method: "GET", body: Optional<String>.none, authenticated: true)
    }

    func trackEvent(_ eventType: String, objectRef: String? = nil, screen: String? = nil, outcome: String? = nil) async {
        let body = ClientEventRequest(event_type: eventType, object_ref: objectRef, screen: screen, outcome: outcome)
        let _: ClientEventAck? = try? await send("/api/v1/pilot/events", method: "POST", body: body, authenticated: true)
    }

    /// `idempotencyKey` must be created once per payment attempt (when the review screen opens) and reused
    /// for every retry of that attempt, so a dropped connection can never move value twice.
    func makePilotTransfer(receiverVPA: String, amount: Decimal, note: String, idempotencyKey: String) async throws -> PilotTransferResponse {
        let request = PilotTransferRequest(receiver_vpa: receiverVPA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), amount: amount, note: note, idempotency_key: idempotencyKey)
        let result: PilotTransferResponse = try await send("/api/v1/pilot/transfers", method: "POST", body: request, authenticated: true)
        // The transfer is already decided; a failed refresh must not turn a committed payment into an error.
        try? await refreshPilotWallet()
        try? await refreshPilotTransfers()
        return result
    }

    /// The amount (when known) lets TraceShield compare this payment with the payer's usual payments.
    func assess(recipientRef: String, amount: Decimal? = nil) async throws -> RiskResponse {
        var body = ["recipient_ref": recipientRef]
        if let amount { body["amount"] = "\(amount)" }
        return try await send("/api/v1/risk/check", method: "POST", body: body, authenticated: true)
    }

    func createPaymentIntent(assessmentID: Int, recipientRef: String, amount: Decimal?, note: String) async throws -> PaymentIntentResponse {
        let body = PaymentIntentRequest(assessment_id: assessmentID, recipient_ref: recipientRef, amount: amount, note: note)
        return try await send("/api/v1/payment-intents", method: "POST", body: body, authenticated: true)
    }

    func recordHandoff(intentID: Int, opened: Bool) async throws {
        let _: HandoffResponse = try await send("/api/v1/payment-intents/\(intentID)/handoff-result?opened=\(opened)", method: "POST", body: Optional<String>.none, authenticated: true)
    }

    /// Lock the UI but retain the device-bound account, token and MPIN for quick unlock.
    func lock() { token = nil; email = nil; profileLoaded = false; pilotProfile = nil; pilotWallet = nil; transfers = [] }

    /// Explicit local session reset helper; not exposed as the normal logout action.
    func clearSavedCredentials() { CredentialVault.clear(); token = nil; email = nil; profileLoaded = false; pilotProfile = nil; pilotWallet = nil; transfers = []; LocalUnlockStore.clearSavedSession() }

    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B?, authenticated: Bool) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        if authenticated, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 && authenticated && token != nil { expireSession() }
        guard (200..<300).contains(http.statusCode) else {
            let apiDetail = (try? decoder.decode(APIError.self, from: data).detail) ?? String(data: data, encoding: .utf8)
            let detail = apiDetail?.isEmpty == false ? apiDetail! : "Request failed (HTTP \(http.statusCode))"
            throw NSError(domain: "Trace.Pay API", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        do { return try decoder.decode(T.self, from: data) }
        catch {
            let responseText = String(data: data.prefix(700), encoding: .utf8) ?? "(non-text response)"
            throw NSError(domain: "Trace.Pay API decoding", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "The server response did not match the expected format. Response: \(responseText). Decoder: \(error.localizedDescription)"])
        }
    }
}


// MARK: - Trace.Pay ID rules (mirror of backend app/ids.py)
enum TracePayID {
    static let invalidMessage = "Trace.Pay IDs look like name@tracepay. Other UPI handles are not Trace.Pay accounts."
    private static let pattern = try! NSRegularExpression(pattern: "^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?@tracepay$")

    /// Accepts "name", "name@tracepay", or a scanned upi:// / tracepay:// QR with pa=name@tracepay.
    static func normalize(_ input: String) -> String? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.hasPrefix("upi://") || raw.hasPrefix("tracepay://") {
            raw = URLComponents(string: raw)?.queryItems?.first(where: { $0.name == "pa" })?.value?.lowercased() ?? ""
        }
        if !raw.isEmpty && !raw.contains("@") { raw += "@tracepay" }
        let range = NSRange(raw.startIndex..., in: raw)
        return pattern.firstMatch(in: raw, range: range) != nil ? raw : nil
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - JWT helpers (read-only; the server remains the authority)
enum JWTClaims {
    static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - Safety layer (lookup any UPI ID, report scams, record payments made in other UPI apps)

struct SafetyFactor: Decodable, Hashable {
    let code: String; let label: String; let family: String; let points: Int; let detail: String
    init(code: String, label: String, family: String, points: Int, detail: String) { self.code = code; self.label = label; self.family = family; self.points = points; self.detail = detail }
    private enum K: String, CodingKey { case code, label, family, points, detail }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        code = (try? c.decode(String.self, forKey: .code)) ?? "SIGNAL"
        label = (try? c.decode(String.self, forKey: .label)) ?? "Signal"
        family = (try? c.decode(String.self, forKey: .family)) ?? "deep"
        points = (try? c.decode(Int.self, forKey: .points)) ?? Int((try? c.decode(Double.self, forKey: .points)) ?? 0)
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
    }
}
struct SafetyVerdict: Decodable, Hashable { let title: String; let advice: String }
struct SafetyMerchant: Decodable, Hashable { let display_name: String?; let verified: Bool? }
struct SafetyLookup: Decodable, Identifiable, Hashable {
    var id: String { ref }
    let ref: String; let display_name: String?; let member: Bool; let merchant: SafetyMerchant?
    let score: Int?; let band: String; let verdict: SafetyVerdict; let factors: [SafetyFactor]
    let confidence: Double; let counterfactuals: [String]; let reports: Int; let records: Int
    let qrName: String?; let qrAmount: String?; let shield: ShieldInfo?
    let coolingSeconds: Int; let stage: LifecycleStage?; let badge: MerchantBadge?; let nameMismatch: Bool
    private enum K: String, CodingKey { case ref, display_name, member, merchant, score, band, verdict, factors, confidence, counterfactuals, community, history, qr, shield,
                                        cooling_seconds, stage, badge, name_mismatch }
    private enum CK: String, CodingKey { case reports }
    private enum HK: String, CodingKey { case records }
    private enum QK: String, CodingKey { case name, amount }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        ref = (try? c.decode(String.self, forKey: .ref)) ?? ""
        display_name = try? c.decode(String.self, forKey: .display_name)
        member = (try? c.decode(Bool.self, forKey: .member)) ?? false
        merchant = try? c.decode(SafetyMerchant.self, forKey: .merchant)
        score = (try? c.decode(Int.self, forKey: .score)) ?? (try? c.decode(Double.self, forKey: .score)).map { Int($0.rounded()) }
        band = (try? c.decode(String.self, forKey: .band)) ?? "insufficient_information"
        verdict = (try? c.decode(SafetyVerdict.self, forKey: .verdict)) ?? SafetyVerdict(title: "Not enough history", advice: "Pay only people you know.")
        factors = (try? c.decode([SafetyFactor].self, forKey: .factors)) ?? []
        confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 0
        counterfactuals = (try? c.decode([String].self, forKey: .counterfactuals)) ?? []
        reports = (try? c.nestedContainer(keyedBy: CK.self, forKey: .community).decode(Int.self, forKey: .reports)) ?? 0
        records = (try? c.nestedContainer(keyedBy: HK.self, forKey: .history).decode(Int.self, forKey: .records)) ?? 0
        let q = try? c.nestedContainer(keyedBy: QK.self, forKey: .qr)
        qrName = try? q?.decode(String.self, forKey: .name)
        qrAmount = try? q?.decode(String.self, forKey: .amount)
        shield = try? c.decode(ShieldInfo.self, forKey: .shield)
        coolingSeconds = (try? c.decode(Int.self, forKey: .cooling_seconds)) ?? 0
        stage = try? c.decode(LifecycleStage.self, forKey: .stage)
        badge = try? c.decode(MerchantBadge.self, forKey: .badge)
        nameMismatch = (try? c.decode(Bool.self, forKey: .name_mismatch)) ?? false
    }
    static func == (a: SafetyLookup, b: SafetyLookup) -> Bool { a.ref == b.ref && a.score == b.score }
    func hash(into h: inout Hasher) { h.combine(ref); h.combine(score) }
}
struct ExternalPaymentBody: Encodable {
    let payee: String; let payee_name: String?; let amount: String; let app: String; let status: String; let source: String
    let upi_txn_id: String?; let risk_score: Int?; let risk_band: String?
}
struct ExternalPaymentRecord: Decodable { let id: Int; let status: String }

extension TracePaySession {
    /// Truecaller-style check of any UPI ID or UPI QR text, with every factor explained.
    func lookup(ref: String, amount: Decimal? = nil) async throws -> SafetyLookup {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/lookup"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ref", value: ref)] + (amount.map { [URLQueryItem(name: "amount", value: "\($0)")] } ?? [])
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 25
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 && token != nil { expireSession() }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? decoder.decode(APIError.self, from: data).detail) ?? "Could not check this account"
            throw NSError(domain: "Trace.Pay API", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return try decoder.decode(SafetyLookup.self, from: data)
    }

    func reportScam(ref: String, category: String, description: String, amount: String) async throws {
        var body = ["target_ref": ref, "category": category, "description": description]
        if Decimal(string: amount) != nil { body["amount"] = amount }
        let _: AnyDecodableIgnored = try await send("/api/v1/community/reports", method: "POST", body: body, authenticated: true)
    }

    func recordExternalPayment(_ body: ExternalPaymentBody) async throws {
        let _: ExternalPaymentRecord = try await send("/api/v1/external-payments", method: "POST", body: body, authenticated: true)
    }
}

/// Accepts any JSON response when only success matters.
struct AnyDecodableIgnored: Decodable { init(from decoder: Decoder) throws {} }

/// Any UPI QR (GPay, PhonePe, Paytm, BHIM, bank apps) or bare UPI ID.
enum UPIQR {
    static func parse(_ raw: String) -> [String: String]? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: String] = [:]
        if text.lowercased().hasPrefix("upi://"), let items = URLComponents(string: text)?.queryItems {
            for item in items { if let v = item.value, !v.isEmpty { fields[item.name.lowercased()] = v.replacingOccurrences(of: "+", with: " ") } }
        } else { fields["pa"] = text }
        guard let pa = fields["pa"]?.lowercased(),
              pa.range(of: #"^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9.]{1,40}$"#, options: .regularExpression) != nil else { return nil }
        fields["pa"] = pa
        return fields
    }
}

struct ExternalPaymentItem: Decodable, Identifiable, Hashable {
    let id: Int; let payee_vpa: String; let payee_name: String?; let amount: String; let app: String
    let status: String; let source: String; let risk_score: Int?; let risk_band: String?; let created_at: String; let paid_at: String?; let upi_txn_id: String?
    private enum K: String, CodingKey { case id, payee_vpa, payee_name, amount, app, status, source, risk_score, risk_band, created_at, paid_at, upi_txn_id }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0; payee_vpa = (try? c.decode(String.self, forKey: .payee_vpa)) ?? ""
        payee_name = try? c.decode(String.self, forKey: .payee_name)
        amount = (try? c.decode(String.self, forKey: .amount)) ?? ((try? c.decode(Double.self, forKey: .amount)).map { String($0) } ?? "0")
        app = (try? c.decode(String.self, forKey: .app)) ?? "upi"; status = (try? c.decode(String.self, forKey: .status)) ?? "SUBMITTED"
        source = (try? c.decode(String.self, forKey: .source)) ?? "manual"; risk_score = try? c.decode(Int.self, forKey: .risk_score)
        risk_band = try? c.decode(String.self, forKey: .risk_band); created_at = (try? c.decode(String.self, forKey: .created_at)) ?? ""
        paid_at = try? c.decode(String.self, forKey: .paid_at); upi_txn_id = try? c.decode(String.self, forKey: .upi_txn_id)
    }
}

extension TracePaySession {
    func externalPayments() async throws -> [ExternalPaymentItem] {
        let none: [String: String]? = nil
        return try await send("/api/v1/external-payments", method: "GET", body: none, authenticated: true)
    }
}

// MARK: - Sign in / sign up with a mobile number or email (no OTP), 5.3+
extension TracePaySession {
    /// `identifier` is an email address or a 10-digit mobile number.
    func signIn(identifier: String, password: String) async throws {
        let clean = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result: AuthResponse = try await send("/api/v1/auth/login", method: "POST",
                                                  body: ["identifier": clean, "email": clean, "password": password], authenticated: false)
        token = result.access_token
        sessionExpired = false
        profileLoaded = false
        pilotProfile = nil
        pilotWallet = nil
        email = clean
        LocalUnlockStore.saveSession(token: result.access_token, email: clean)
        CredentialVault.save(identifier: clean, password: password)
    }

    func signUp(email: String?, mobile: String?, password: String) async throws {
        var body = ["password": password]
        if let email, !email.isEmpty { body["email"] = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let mobile, !mobile.isEmpty { body["mobile"] = mobile }
        let _: AnyDecodableIgnored = try await send("/api/v1/auth/register", method: "POST", body: body, authenticated: false)
        try await signIn(identifier: body["email"] ?? (mobile ?? ""), password: password)
    }
}


// MARK: - Credential vault: the sign-in is stored in the Keychain, readable only after Face ID / Touch ID / passcode.
enum CredentialVault {
    private static let service = "tech.tracepay.ios.vault"
    private static let account = "member"
    static var hasCredential: Bool { UserDefaults.standard.bool(forKey: "tp.vault.saved") }
    static func save(identifier: String, password: String) {
        guard let data = try? JSONEncoder().encode([identifier, password]) else { return }
        clear()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecValueData as String: data, kSecAttrAccessControl as String: access]
        if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { UserDefaults.standard.set(true, forKey: "tp.vault.saved") }
    }
    /// Shows the system Face ID / Touch ID / passcode prompt. Returns nil if cancelled or nothing is stored.
    static func read(reason: String) async -> (identifier: String, password: String)? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let ctx = LAContext(); ctx.localizedReason = reason
                let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: ctx]
                var item: CFTypeRef?
                guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
                      let pair = try? JSONDecoder().decode([String].self, from: data), pair.count == 2 else { cont.resume(returning: nil); return }
                cont.resume(returning: (pair[0], pair[1]))
            }
        }
    }
    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        UserDefaults.standard.set(false, forKey: "tp.vault.saved")
    }
}

// MARK: - Email verification code (sent by Supabase via the trace.pay server)
extension TracePaySession {
    func sendEmailCode(name: String) async throws {
        let _: AnyDecodableIgnored = try await send("/api/v1/auth/email/send-otp", method: "POST", body: ["full_name": name], authenticated: true)
    }
    func verifyEmailCode(_ code: String) async throws {
        let _: AnyDecodableIgnored = try await send("/api/v1/auth/email/verify-otp", method: "POST", body: ["code": code], authenticated: true)
    }
}

struct EmailStatus: Decodable { let email: String?; let verified: Bool; let required: Bool }
extension TracePaySession {
    func emailStatus() async throws -> EmailStatus {
        let none: [String: String]? = nil
        return try await send("/api/v1/auth/email/status", method: "GET", body: none, authenticated: true)
    }
}

// MARK: - 6.1: sign-up verification, forgot password, scoring rules, receipts
struct VerifyTicket: Decodable { let ticket: String }
struct ScoringRule: Decodable, Identifiable { var id: String { code }; let code: String; let label: String; let rule: String; let family: String; let pointsText: String
    private enum K: String, CodingKey { case code, label, rule, family, points }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        code = (try? c.decode(String.self, forKey: .code)) ?? ""; label = (try? c.decode(String.self, forKey: .label)) ?? ""
        rule = (try? c.decode(String.self, forKey: .rule)) ?? ""; family = (try? c.decode(String.self, forKey: .family)) ?? ""
        if let n = try? c.decode(Int.self, forKey: .points) { pointsText = n > 0 ? "+\(n)" : "\(n)" } else { pointsText = (try? c.decode(String.self, forKey: .points)) ?? "" }
    }
}
struct ScoringBand: Decodable, Identifiable { var id: String { range }; let range: String; let label: String; let band: String; let meaning: String }
struct ScoringModel: Decodable { let summary: String; let bands: [ScoringBand]; let signals: [ScoringRule]; let community: [ScoringRule]; let window: String }

struct ReceiptBody: Encodable {
    let payee: String; let payee_name: String?; let amount: String; let app: String; let status: String; let source: String
    let upi_txn_id: String?; let risk_score: Int?; let risk_band: String?; let paid_at: String?; let payee_mobile: String?
}

extension TracePaySession {
    func startVerification(channel: String, target: String, name: String) async throws {
        let _: AnyDecodableIgnored = try await send("/api/v1/auth/verify/start", method: "POST", body: ["channel": channel, "target": target, "full_name": name], authenticated: false)
    }
    func checkVerification(channel: String, target: String, code: String) async throws -> String {
        let r: VerifyTicket = try await send("/api/v1/auth/verify/check", method: "POST", body: ["channel": channel, "target": target, "code": code], authenticated: false)
        return r.ticket
    }
    func signUpVerified(email: String, mobile: String, password: String, emailTicket: String, smsTicket: String) async throws {
        let body = ["email": email.lowercased(), "mobile": mobile, "password": password, "email_ticket": emailTicket, "sms_ticket": smsTicket]
        let _: AnyDecodableIgnored = try await send("/api/v1/auth/register", method: "POST", body: body, authenticated: false)
        try await signIn(identifier: email, password: password)
    }
    func forgotPassword(identifier: String) async throws {
        let _: AnyDecodableIgnored = try await send("/api/v1/auth/password/forgot", method: "POST", body: ["identifier": identifier], authenticated: false)
    }
    func resetPassword(identifier: String, code: String, newPassword: String) async throws {
        let _: AnyDecodableIgnored = try await send("/api/v1/auth/password/reset", method: "POST", body: ["identifier": identifier, "code": code, "new_password": newPassword], authenticated: false)
    }
    func scoringModel() async throws -> ScoringModel {
        let none: [String: String]? = nil
        return try await send("/api/v1/scoring/model", method: "GET", body: none, authenticated: true)
    }
    func recordReceipt(_ body: ReceiptBody) async throws {
        let _: ExternalPaymentRecord = try await send("/api/v1/external-payments", method: "POST", body: body, authenticated: true)
    }
}


// MARK: - v1.1: TraceID, fraud intelligence, recovery, research
struct LifecycleStage: Decodable, Hashable { let stage: String; let label: String; let detail: String }
struct MerchantBadge: Decodable, Hashable { let tier: String; let label: String; let detail: String }
struct TraceIDResult: Decodable { let live: Bool; let reason: String; let blinks: Int; let duplicate: Bool }
struct MessageSignal: Decodable, Identifiable { var id: String { code }; let code: String; let label: String; let points: Int; let matched: [String]? }
struct MessageUPICheck: Decodable, Identifiable { var id: String { ref }; let ref: String; let name: String?; let score: Int?; let band: String; let title: String; let reports: Int }
struct MessagePhoneCheck: Decodable, Identifiable { var id: String { number }; let number: String; let reports: Int; let score: Int; let band: String }
struct LinkCheck: Decodable, Identifiable { var id: String { url }; let url: String; let host: String; let score: Int; let band: String; let signals: [LinkSignal] }
struct LinkSignal: Decodable, Hashable { let code: String; let label: String; let points: Int }
struct MessageAnalysis: Decodable {
    let overall: Int; let overall_band: String; let verdict: String; let signals: [MessageSignal]
    let upi_checks: [MessageUPICheck]; let phone_checks: [MessagePhoneCheck]; let link_checks: [LinkCheck]
}
struct TrailHop: Decodable, Identifiable { var id: String { from + to + at }; let from: String; let to: String; let amount: String; let at: String; let hop: Int }
struct RecoveryStep: Decodable, Identifiable { var id: String { title }; let title: String; let detail: String; let action: String? }
struct RecoveryPack: Decodable {
    let payee: String; let payee_name: String?; let amount: String; let paid_at: String; let reference: String?; let app: String
    let complaint_text: String; let bank_letter: String; let money_trail: [TrailHop]; let steps: [RecoveryStep]
}
struct MyReport: Decodable, Identifiable { let id: Int; let target_ref: String; let category_label: String; let status: String; let created_at: String; let warned: Int }

extension TracePaySession {
    func traceIDCheck(video: Data) async throws -> TraceIDResult {
        guard let token else { throw NSError(domain: "Trace.Pay", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please sign in again."]) }
        let boundary = "TracePay-" + UUID().uuidString
        var request = URLRequest(url: baseURL.appending(path: "api/v1/traceid/check"))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"face_video\"; filename=\"traceid.mp4\"\r\nContent-Type: video/mp4\r\n\r\n".utf8)
        body.append(video); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? decoder.decode(APIError.self, from: data).detail) ?? "Couldn't check the video. Try again."
            throw NSError(domain: "Trace.Pay API", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return try decoder.decode(TraceIDResult.self, from: data)
    }
    func analyzeMessage(_ text: String) async throws -> MessageAnalysis {
        try await send("/api/v1/intel/message", method: "POST", body: ["text": text], authenticated: true)
    }
    func recoveryPack(paymentId: Int?, transferRef: String?) async throws -> RecoveryPack {
        let none: [String: String]? = nil
        let q = paymentId.map { "payment_id=\($0)" } ?? "transfer_ref=\(transferRef?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        return try await send("/api/v1/recovery/pack?\(q)", method: "GET", body: none, authenticated: true)
    }
    func myReports() async throws -> [MyReport] {
        let none: [String: String]? = nil
        return try await send("/api/v1/community/reports/mine", method: "GET", body: none, authenticated: true)
    }
    /// Explanation study: what the person did after seeing a TraceScore report. Best effort; never blocks the payment.
    func logDecision(ref: String, score: Int?, band: String, action: String, explained: Bool, seconds: Double) {
        Task {
            var body: [String: String] = ["ref": ref, "band": band, "action": action, "explanation_opened": explained ? "true" : "false", "seconds_on_report": String(format: "%.1f", seconds)]
            if let score { body["score"] = String(score) }
            let _: AnyDecodableIgnored? = try? await send("/api/v1/research/decision", method: "POST", body: body, authenticated: true)
        }
    }
}

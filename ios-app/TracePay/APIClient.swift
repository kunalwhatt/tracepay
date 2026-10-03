import SwiftUI
import Foundation
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


struct APIError: Decodable { let detail: String? }
struct AuthResponse: Decodable { let access_token: String; let token_type: String; let role: String }
struct RiskResponse: Decodable, Identifiable {
    var id: Int { assessment_id }
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
        let value = Bundle.main.object(forInfoDictionaryKey: "TRACEPAY_API_BASE_URL") as? String ?? "http://127.0.0.1:8000"
        return URL(string: value) ?? URL(string: "http://127.0.0.1:8000")!
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
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"face_photo\"; filename=\"profile.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
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

    func assess(recipientRef: String) async throws -> RiskResponse {
        try await send("/api/v1/risk/check", method: "POST", body: ["recipient_ref": recipientRef], authenticated: true)
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
    func clearSavedCredentials() { token = nil; email = nil; profileLoaded = false; pilotProfile = nil; pilotWallet = nil; transfers = []; LocalUnlockStore.clearSavedSession() }

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

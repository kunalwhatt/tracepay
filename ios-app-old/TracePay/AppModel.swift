import SwiftUI
import LocalAuthentication

// MARK: - Device lock: only the phone's own authentication (no app PIN)

enum DeviceLock {
    struct Method { let name: String; let icon: String; let available: Bool }

    /// The lock this phone has: Face ID, Touch ID, Optic ID or the passcode.
    static var method: Method {
        let ctx = LAContext()
        var err: NSError?
        let any = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return Method(name: "Face ID", icon: Icon.face, available: any)
        case .touchID: return Method(name: "Touch ID", icon: Icon.finger, available: any)
        case .opticID: return Method(name: "Optic ID", icon: "opticid", available: any)
        default: return Method(name: "Passcode", icon: Icon.pin, available: any)
        }
    }

    /// `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`: biometrics with the passcode as fallback.
    @MainActor
    static func authenticate(_ reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use device passcode"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        do { return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }
}

// MARK: - Local, per-device state (settings, check history, safety stats)

struct CheckRecord: Codable, Identifiable, Hashable {
    var id: String { ref }
    let ref: String
    var name: String
    var score: Int?
    var reports: Int
    var at: Date
}

struct StoppedPayment: Codable, Hashable { let ref: String; let amount: Double; let at: Date }

/// One row in Activity: a Trace.Pay transfer or a payment recorded from another UPI app.
struct ActivityItem: Identifiable, Hashable {
    let id: String
    let name: String
    let vpa: String
    let via: String
    let amount: Double
    let incoming: Bool
    let date: Date
    let score: Int?
    let reference: String
    let status: String
    let note: String
    var isTracePay: Bool { via == "Trace.Pay" }
    var succeeded: Bool { status == "SUCCESS" }
}

@MainActor
final class AppModel: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var lockEnabled: Bool { didSet { defaults.set(lockEnabled, forKey: "lockEnabled") } }
    @Published var coolingOn: Bool { didSet { defaults.set(coolingOn, forKey: "coolingOn") } }
    @Published var coolingMinutes: Int { didSet { defaults.set(coolingMinutes, forKey: "coolingMinutes") } }
    @Published var dailyLimit: Double { didSet { defaults.set(dailyLimit, forKey: "dailyLimit") } }
    @Published var readAloud: Bool { didSet { defaults.set(readAloud, forKey: "readAloud") } }
    @Published var alertsReadAt: Date { didSet { defaults.set(alertsReadAt, forKey: "alertsReadAt") } }
    @Published private(set) var checks: [CheckRecord] = []
    @Published private(set) var checkLog: [Date] = []
    @Published private(set) var stopped: [StoppedPayment] = []
    @Published var externals: [ExternalPaymentItem] = []

    init() {
        lockEnabled = defaults.bool(forKey: "lockEnabled")
        coolingOn = defaults.object(forKey: "coolingOn") as? Bool ?? true
        coolingMinutes = defaults.object(forKey: "coolingMinutes") as? Int ?? 5
        dailyLimit = defaults.object(forKey: "dailyLimit") as? Double ?? 50_000
        readAloud = defaults.bool(forKey: "readAloud")
        alertsReadAt = defaults.object(forKey: "alertsReadAt") as? Date ?? .distantPast
        checks = load("checks") ?? []
        checkLog = load("checkLog") ?? []
        stopped = load("stopped") ?? []
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    /// The score from the previous check of `ref`, for "▲ 16 since last check".
    func previousScore(_ ref: String) -> Int? { checks.first { $0.ref == ref }?.score }

    func recordCheck(ref: String, name: String, score: Int?, reports: Int) {
        checks.removeAll { $0.ref == ref }
        checks.insert(CheckRecord(ref: ref, name: name, score: score, reports: reports, at: Date()), at: 0)
        if checks.count > 30 { checks = Array(checks.prefix(30)) }
        checkLog.append(Date())
        checkLog = checkLog.filter { $0 > Date().addingTimeInterval(-62 * 86_400) }
        save(checks, "checks"); save(checkLog, "checkLog")
    }

    /// A risky (Poor) payment the member chose not to make.
    func recordStopped(ref: String, amount: Double) {
        stopped.append(StoppedPayment(ref: ref, amount: amount, at: Date()))
        save(stopped, "stopped")
    }

    func clearLocal() {
        for k in ["checks", "checkLog", "stopped", "lockEnabled", "alertsReadAt"] { defaults.removeObject(forKey: k) }
        checks = []; checkLog = []; stopped = []; externals = []; lockEnabled = false; alertsReadAt = .distantPast
    }

    // MARK: Monthly safety

    private func thisMonth(_ d: Date) -> Bool { Calendar.current.isDate(d, equalTo: Date(), toGranularity: .month) }
    var checkedThisMonth: Int { checkLog.filter(thisMonth).count }
    var stoppedThisMonth: Int { stopped.filter { thisMonth($0.at) }.count }
    var keptSafeThisMonth: Double { stopped.filter { thisMonth($0.at) }.reduce(0) { $0 + $1.amount } }

    // MARK: Activity

    func activity(transfers: [PilotTransferResponse], myVPA: String?) -> [ActivityItem] {
        let me = myVPA?.lowercased() ?? ""
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func date(_ s: String) -> Date { iso.date(from: s) ?? isoPlain.date(from: s) ?? Self.parseNaive(s) ?? Date() }
        let tp: [ActivityItem] = transfers.map { t in
            let incoming = t.receiver_vpa.lowercased() == me && t.sender_vpa.lowercased() != me
            let other = incoming ? t.sender_vpa : t.receiver_vpa
            return ActivityItem(id: "tp-\(t.id)", name: Fmt.nameFromVPA(other), vpa: other, via: "Trace.Pay", amount: Double(t.amount) ?? 0,
                                incoming: incoming, date: date(t.created_at), score: incoming ? nil : previousScore(other),
                                reference: t.transfer_ref, status: t.status, note: t.note)
        }
        let ext: [ActivityItem] = externals.map { e in
            ActivityItem(id: "ext-\(e.id)", name: e.payee_name ?? Fmt.nameFromVPA(e.payee_vpa), vpa: e.payee_vpa, via: Self.appName(e.app),
                         amount: Double(e.amount) ?? 0, incoming: false, date: date(e.created_at), score: e.risk_score,
                         reference: "EXT-\(e.id)", status: e.status, note: "")
        }
        return (tp + ext).sorted { $0.date > $1.date }
    }

    static func parseNaive(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }

    static func appName(_ code: String) -> String {
        switch code.lowercased() {
        case "gpay", "google pay", "googlepay", "tez": "Google Pay"
        case "phonepe": "PhonePe"
        case "paytm": "Paytm"
        case "bhim": "BHIM"
        default: code.isEmpty ? "UPI app" : code.prefix(1).uppercased() + code.dropFirst()
        }
    }
}

import SwiftUI

@main
struct TracePayApp: App {
    @StateObject private var session = TracePaySession()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.light)
        }
    }
}

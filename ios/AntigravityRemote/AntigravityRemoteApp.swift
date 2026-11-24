import SwiftUI

@main
struct AntigravityRemoteApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var client = BridgeClient()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(client)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handlePairingURL(url)
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        client.reconnectIfNeeded()
                    }
                }
        }
    }

    private func handlePairingURL(_ url: URL) {
        guard let payload = PairingParser.parse(url.absoluteString) else { return }
        let profile = settings.upsertProfile(
            name: payload.name,
            baseURL: payload.url,
            token: payload.token
        )
        client.connect(to: profile)
    }
}

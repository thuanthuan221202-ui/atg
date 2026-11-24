import SwiftUI

struct RootView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var client: BridgeClient
    @State private var showConnectionScreen = false
    @State private var didAutoConnect = false

    var body: some View {
        Group {
            if settings.activeProfile == nil || showConnectionScreen {
                ConnectionView(
                    canDismiss: settings.activeProfile != nil,
                    onConnected: {
                        showConnectionScreen = false
                    }
                )
            } else {
                ChatWorkspaceView(onOpenConnections: {
                    showConnectionScreen = true
                })
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .onAppear {
            guard !didAutoConnect else { return }
            didAutoConnect = true
            if let profile = settings.activeProfile {
                client.connect(to: profile)
            }
        }
    }
}

import SwiftUI

@main
struct NFTMapsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    @State private var session = WalletSession()

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                ZStack {
                    BrandBackground()
                    PawOrb(size: 96)
                }
            case .signedOut:
                LoginView(session: session)
            case .ready(let account):
                AppShell(session: session, account: account)
            }
        }
        .tint(.purple)
        .task { await session.restore() }
    }
}

import SwiftUI
import Services
import Features
import Core

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    private let logger = Logger.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                #if os(macOS)
                TabbedTreeView()
                    .onAppear {
                        logger.debug("🧭 Showing TabbedTreeView (authenticated)", category: "UI")
                    }
                #else
                TreeView()
                    .onAppear {
                        logger.debug("🧭 Showing TreeView (authenticated)", category: "UI")
                    }
                #endif
            } else {
                LoginView()
                    .onAppear {
                        logger.debug("🧭 Showing LoginView (not authenticated)", category: "UI")
                    }
            }
        }
        .onAppear {
            logger.info("📞 ContentView appeared with auth status: \(authManager.isAuthenticated)", category: "UI")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(DataManager())
}
import SwiftUI
import Services
import Core

@main
struct SwiftGTDApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var dataManager = DataManager()
    private let logger = Logger.shared
    
    init() {
        logger.info("========== APP LAUNCH: \(Date()) ==========", category: "App")
        logger.debug("📞 Initializing app", category: "App")
        logger.debug("✅ AuthManager created", category: "App")
        logger.debug("✅ DataManager created", category: "App")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(dataManager)
                .onAppear {
                    logger.debug("🧭 Main window appeared", category: "App")
                }
        }
    }
}
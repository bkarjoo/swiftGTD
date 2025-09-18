import SwiftUI
import Core
import Models
import Services
import Features

@main
struct SwiftGTDApp_macOS: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var dataManager = DataManager()
    
    init() {
        Logger.shared.log("📞 Initializing macOS app", level: .debug, category: "App")
        Logger.shared.log("✅ AuthManager created", level: .debug, category: "App")
        Logger.shared.log("✅ DataManager created", level: .debug, category: "App")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(dataManager)
                .frame(minWidth: 400, minHeight: 300)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .windowResizability(.automatic)
        
        Settings {
            SettingsView()
                .environmentObject(authManager)
        }
    }
}

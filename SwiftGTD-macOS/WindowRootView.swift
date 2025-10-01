import SwiftUI
import Features
import Services
import Core

/// WindowRootView creates a unique view hierarchy for each window instance.
/// This ensures each window has independent UI state (tabs, focus, selection)
/// while sharing the same data layer (authManager, dataManager).
struct WindowRootView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var dataManager: DataManager

    // Each window gets its own UUID for state isolation
    @State private var windowId = UUID()
    private let logger = Logger.shared

    var body: some View {
        ContentView()
            .environment(\.windowId, windowId)
            .onAppear {
                logger.log("🪟 Window created with ID: \(windowId)", category: "Window")
            }
            .onDisappear {
                logger.log("🪟 Window closed with ID: \(windowId)", category: "Window")
            }
    }
}

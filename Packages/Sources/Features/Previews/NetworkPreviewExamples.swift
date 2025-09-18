#if DEBUG
import SwiftUI
import Services
import Core

/// Example view that shows network status
struct NetworkStatusDemoView: View {
    @StateObject private var dataManager = DataManager()
    
    var body: some View {
        VStack(spacing: 20) {
            // Network status from factory
            if let monitor = NetworkMonitorFactory.shared as? TestableNetworkMonitor {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: monitor.connectionType.symbolName)
                            .foregroundColor(monitor.isConnected ? .green : .red)
                        Text(monitor.connectionType.displayName)
                            .font(.headline)
                    }
                    
                    if monitor.isConnected {
                        HStack {
                            if monitor.isExpensive {
                                Label("Expensive", systemImage: "dollarsign.circle.fill")
                                    .foregroundColor(.orange)
                            }
                            if monitor.isConstrained {
                                Label("Constrained", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
            }
            
            // Offline queue status
            Text("Offline: \(dataManager.isOffline ? "Yes" : "No")")
                .foregroundColor(dataManager.isOffline ? .red : .green)
            
            // Simulated content
            if dataManager.isOffline {
                Text("📵 Working Offline")
                    .font(.title2)
                    .padding()
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
            } else {
                Text("✅ Online - Syncing")
                    .font(.title2)
                    .padding()
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Network Status Demo")
    }
}

// MARK: - Previews with Different Network Conditions

struct NetworkStatusDemoView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // WiFi Connection
            NavigationView {
                NetworkStatusDemoView()
                    .withNetworkPreview(.wifi)
            }
            .previewDisplayName("WiFi Connected")
            
            // Cellular Connection (Expensive)
            NavigationView {
                NetworkStatusDemoView()
                    .withCellularPreview()
            }
            .previewDisplayName("Cellular (Expensive)")
            
            // Offline
            NavigationView {
                NetworkStatusDemoView()
                    .withOfflinePreview()
            }
            .previewDisplayName("Offline")
            
            // Constrained WiFi
            NavigationView {
                NetworkStatusDemoView()
                    .withNetworkPreview(.wifi, isConstrained: true)
            }
            .previewDisplayName("Constrained WiFi")
            
            // Wired Connection
            NavigationView {
                NetworkStatusDemoView()
                    .withNetworkPreview(.wired)
            }
            .previewDisplayName("Wired Connection")
        }
    }
}

// MARK: - Development Mode Toggle View

/// Settings view for toggling development offline mode
public struct DevelopmentNetworkSettings: View {
    @State private var isOfflineMode = NetworkMonitorFactory.isDevelopmentOfflineEnabled
    
    public init() {}
    
    public var body: some View {
        #if DEBUG
        Section("Development Network Settings") {
            Toggle("Simulate Offline Mode", isOn: $isOfflineMode)
                .onChange(of: isOfflineMode) { _ in
                    NetworkMonitorFactory.toggleDevelopmentOfflineMode()
                }
            
            Text("When enabled, the app will simulate being offline for testing purposes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        #else
        EmptyView()
        #endif
    }
}

// MARK: - App Initialization Example

/// Example of how to initialize the factory in your app
struct NetworkFactoryInitExample {
    @MainActor
    static func initializeApp() {
        #if DEBUG
        // Initialize factory based on environment
        NetworkMonitorFactory.initializeForCurrentEnvironment()
        
        // Log current configuration
        Logger.shared.log("🚀 App starting with network factory configured", category: "App")
        #endif
    }
}
#endif
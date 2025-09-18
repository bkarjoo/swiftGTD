import Foundation
import Core

/// Factory for creating NetworkMonitor instances
/// Allows switching between real and testable implementations for different environments
@MainActor
public enum NetworkMonitorFactory {
    /// Environment configuration for NetworkMonitor
    public enum Environment {
        case production
        case preview
        case testing
        case development(simulateOffline: Bool)
    }
    
    /// Current environment - can be overridden for testing/previews
    private static var currentEnvironment: Environment = .production
    
    /// Shared instance based on current environment
    public static var shared: NetworkMonitorProtocol {
        switch currentEnvironment {
        case .production:
            return NetworkMonitor.shared
        case .preview:
            return createPreviewMonitor()
        case .testing:
            return TestableNetworkMonitor()
        case .development(let simulateOffline):
            return createDevelopmentMonitor(simulateOffline: simulateOffline)
        }
    }
    
    /// Configure the environment for the factory
    public static func configure(environment: Environment) {
        currentEnvironment = environment
        Logger.shared.log("🏭 NetworkMonitor factory configured for: \(String(describing: environment))", category: "NetworkMonitorFactory")
    }
    
    /// Reset to production environment
    public static func reset() {
        currentEnvironment = .production
    }
    
    /// Create a monitor suitable for SwiftUI previews
    private static func createPreviewMonitor() -> NetworkMonitorProtocol {
        let monitor = TestableNetworkMonitor()
        // Default to WiFi connection for previews
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi
        )
        return monitor
    }
    
    /// Create a monitor for development with configurable offline mode
    private static func createDevelopmentMonitor(simulateOffline: Bool) -> NetworkMonitorProtocol {
        let monitor = TestableNetworkMonitor()
        if simulateOffline {
            monitor.simulateConnectionChange(isConnected: false)
        } else {
            monitor.simulateConnectionChange(
                isConnected: true,
                connectionType: .wifi
            )
        }
        return monitor
    }
}

// MARK: - SwiftUI Preview Helpers

#if DEBUG
import SwiftUI

/// Preview helper for simulating different network conditions
public struct NetworkPreviewModifier: ViewModifier {
    let connectionType: NetworkMonitor.ConnectionType?
    let isExpensive: Bool
    let isConstrained: Bool
    
    public init(
        connectionType: NetworkMonitor.ConnectionType? = .wifi,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.connectionType = connectionType
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                NetworkMonitorFactory.configure(environment: .preview)
                if let shared = NetworkMonitorFactory.shared as? TestableNetworkMonitor {
                    if let connectionType = connectionType {
                        shared.simulateConnectionChange(
                            isConnected: true,
                            connectionType: connectionType,
                            isExpensive: isExpensive,
                            isConstrained: isConstrained
                        )
                    } else {
                        shared.simulateConnectionChange(isConnected: false)
                    }
                }
            }
    }
}

public extension View {
    /// Simulate network conditions for SwiftUI previews
    /// - Parameters:
    ///   - connectionType: The type of connection to simulate (nil for disconnected)
    ///   - isExpensive: Whether the connection should be marked as expensive
    ///   - isConstrained: Whether the connection should be marked as constrained
    func withNetworkPreview(
        _ connectionType: NetworkMonitor.ConnectionType? = .wifi,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) -> some View {
        modifier(NetworkPreviewModifier(
            connectionType: connectionType,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        ))
    }
    
    /// Simulate offline state for previews
    func withOfflinePreview() -> some View {
        withNetworkPreview(nil)
    }
    
    /// Simulate cellular connection for previews
    func withCellularPreview(isExpensive: Bool = true) -> some View {
        withNetworkPreview(.cellular, isExpensive: isExpensive)
    }
}

// MARK: - Development Mode Toggle

/// UserDefaults key for development mode network simulation
private let kDevelopmentModeOfflineKey = "com.swiftgtd.development.simulateOffline"

public extension NetworkMonitorFactory {
    /// Check if development mode offline simulation is enabled
    static var isDevelopmentOfflineEnabled: Bool {
        UserDefaults.standard.bool(forKey: kDevelopmentModeOfflineKey)
    }
    
    /// Toggle development mode offline simulation
    static func toggleDevelopmentOfflineMode() {
        let newValue = !isDevelopmentOfflineEnabled
        UserDefaults.standard.set(newValue, forKey: kDevelopmentModeOfflineKey)
        
        // Reconfigure factory
        configure(environment: .development(simulateOffline: newValue))
        
        Logger.shared.log("🔄 Development offline mode: \(newValue ? "ON" : "OFF")", category: "NetworkMonitorFactory")
    }
    
    /// Initialize factory based on build configuration and preferences
    static func initializeForCurrentEnvironment() {
        #if DEBUG
        // In debug builds, check for development mode preference
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            configure(environment: .preview)
        } else if CommandLine.arguments.contains("--uitesting") {
            configure(environment: .testing)
        } else if isDevelopmentOfflineEnabled {
            configure(environment: .development(simulateOffline: true))
        }
        #endif
    }
}
#endif
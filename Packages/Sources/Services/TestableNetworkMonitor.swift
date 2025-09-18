import Foundation
import Network
import Combine
import Core

/// A testable version of NetworkMonitor that allows state manipulation for testing
@MainActor
public class TestableNetworkMonitor: ObservableObject, NetworkMonitorProtocol {
    @Published public private(set) var isConnected = true
    @Published public private(set) var connectionType: NetworkMonitor.ConnectionType = .unknown
    @Published public private(set) var isExpensive = false
    @Published public private(set) var isConstrained = false
    @Published public private(set) var hasCheckedConnection = false
    
    private let logger = Logger.shared
    
    public init() {}
    
    /// Simulate a connection state change for testing
    public func simulateConnectionChange(
        isConnected: Bool,
        connectionType: NetworkMonitor.ConnectionType = .unavailable,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        let wasConnected = self.isConnected
        
        self.isConnected = isConnected
        self.connectionType = isConnected ? connectionType : .unavailable
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.hasCheckedConnection = true
        
        // Log connection changes
        if wasConnected != self.isConnected {
            if self.isConnected {
                logger.log("✅ [TEST] Network connected (\(self.connectionType.displayName))", category: "TestableNetworkMonitor")
            } else {
                logger.log("❌ [TEST] Network disconnected", category: "TestableNetworkMonitor")
            }
        }
    }
    
    /// Reset to initial state
    public func reset() {
        isConnected = true
        connectionType = .unknown
        isExpensive = false
        isConstrained = false
        hasCheckedConnection = false
    }
}
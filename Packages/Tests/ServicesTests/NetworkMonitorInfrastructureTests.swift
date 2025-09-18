import XCTest
import Foundation
import Combine
@testable import Services
@testable import Core

/// Tests for NetworkMonitor test infrastructure
@MainActor
final class NetworkMonitorInfrastructureTests: XCTestCase {
    
    // MARK: - TestableNetworkMonitor Infrastructure Tests
    
    func testTestableNetworkMonitor_canSimulateConnectedState() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Verify initial state
        XCTAssertTrue(monitor.isConnected, "Should start connected")
        XCTAssertEqual(monitor.connectionType, .unknown, "Should start with unknown type")
        XCTAssertFalse(monitor.hasCheckedConnection, "Should not be checked initially")
        
        // Act - Simulate WiFi connection
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi
        )
        
        // Assert
        XCTAssertTrue(monitor.isConnected, "Should be connected")
        XCTAssertEqual(monitor.connectionType, .wifi, "Should be WiFi")
        XCTAssertTrue(monitor.hasCheckedConnection, "Should be marked as checked")
        XCTAssertFalse(monitor.isExpensive, "WiFi should not be expensive")
        XCTAssertFalse(monitor.isConstrained, "WiFi should not be constrained")
    }
    
    func testTestableNetworkMonitor_canSimulateDisconnectedState() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act - Simulate disconnection
        monitor.simulateConnectionChange(isConnected: false)
        
        // Assert
        XCTAssertFalse(monitor.isConnected, "Should be disconnected")
        XCTAssertEqual(monitor.connectionType, .unavailable, "Should be unavailable when disconnected")
        XCTAssertTrue(monitor.hasCheckedConnection, "Should be marked as checked")
    }
    
    func testTestableNetworkMonitor_canSimulateCellularConnection() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act - Simulate expensive cellular connection
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true
        )
        
        // Assert
        XCTAssertTrue(monitor.isConnected, "Should be connected")
        XCTAssertEqual(monitor.connectionType, .cellular, "Should be cellular")
        XCTAssertTrue(monitor.isExpensive, "Cellular should be expensive")
        XCTAssertFalse(monitor.isConstrained, "Should not be constrained")
    }
    
    func testTestableNetworkMonitor_canSimulateWiredConnection() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act - Simulate wired connection
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wired
        )
        
        // Assert
        XCTAssertTrue(monitor.isConnected, "Should be connected")
        XCTAssertEqual(monitor.connectionType, .wired, "Should be wired")
        XCTAssertFalse(monitor.isExpensive, "Wired should not be expensive")
        XCTAssertFalse(monitor.isConstrained, "Wired should not be constrained")
    }
    
    func testTestableNetworkMonitor_canSimulateConstrainedConnection() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act - Simulate constrained connection
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi,
            isConstrained: true
        )
        
        // Assert
        XCTAssertTrue(monitor.isConnected, "Should be connected")
        XCTAssertEqual(monitor.connectionType, .wifi, "Should be WiFi")
        XCTAssertFalse(monitor.isExpensive, "Should not be expensive")
        XCTAssertTrue(monitor.isConstrained, "Should be constrained")
    }
    
    func testTestableNetworkMonitor_canSimulateMultipleStateChanges() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act & Assert - WiFi connection
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi
        )
        XCTAssertTrue(monitor.isConnected)
        XCTAssertEqual(monitor.connectionType, .wifi)
        
        // Disconnect
        monitor.simulateConnectionChange(isConnected: false)
        XCTAssertFalse(monitor.isConnected)
        XCTAssertEqual(monitor.connectionType, .unavailable)
        
        // Cellular connection
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true
        )
        XCTAssertTrue(monitor.isConnected)
        XCTAssertEqual(monitor.connectionType, .cellular)
        XCTAssertTrue(monitor.isExpensive)
        
        // Wired connection
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wired
        )
        XCTAssertTrue(monitor.isConnected)
        XCTAssertEqual(monitor.connectionType, .wired)
        XCTAssertFalse(monitor.isExpensive) // Should reset to false
    }
    
    func testTestableNetworkMonitor_disconnectionAlwaysSetsUnavailable() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act - Try to set a connection type while disconnected (should be ignored)
        monitor.simulateConnectionChange(
            isConnected: false,
            connectionType: .wifi // This should be ignored
        )
        
        // Assert
        XCTAssertFalse(monitor.isConnected, "Should be disconnected")
        XCTAssertEqual(monitor.connectionType, .unavailable, "Should always be unavailable when disconnected")
    }
    
    func testTestableNetworkMonitor_resetClearsState() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Setup some state
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true,
            isConstrained: true
        )
        
        // Verify state was set
        XCTAssertTrue(monitor.hasCheckedConnection)
        XCTAssertEqual(monitor.connectionType, .cellular)
        XCTAssertTrue(monitor.isExpensive)
        XCTAssertTrue(monitor.isConstrained)
        
        // Act - Reset
        monitor.reset()
        
        // Assert - Should return to initial state
        XCTAssertTrue(monitor.isConnected, "Should reset to connected")
        XCTAssertEqual(monitor.connectionType, .unknown, "Should reset to unknown")
        XCTAssertFalse(monitor.isExpensive, "Should reset to not expensive")
        XCTAssertFalse(monitor.isConstrained, "Should reset to not constrained")
        XCTAssertFalse(monitor.hasCheckedConnection, "Should reset to not checked")
    }
    
    func testTestableNetworkMonitor_conformsToProtocol() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act - Use as protocol
        let protocolMonitor: NetworkMonitorProtocol = monitor
        
        // Assert - Can access all protocol properties
        XCTAssertTrue(protocolMonitor.isConnected)
        XCTAssertEqual(protocolMonitor.connectionType, .unknown)
        XCTAssertFalse(protocolMonitor.isExpensive)
        XCTAssertFalse(protocolMonitor.isConstrained)
        XCTAssertFalse(protocolMonitor.hasCheckedConnection)
    }
    
    func testTestableNetworkMonitor_deterministicBehavior() {
        // Run the same sequence multiple times to ensure deterministic behavior
        for iteration in 1...3 {
            // Arrange
            let monitor = TestableNetworkMonitor()
            
            // Act & Assert - Same sequence each time
            monitor.simulateConnectionChange(
                isConnected: true,
                connectionType: .wifi
            )
            XCTAssertEqual(monitor.connectionType, .wifi, "Iteration \(iteration): Should be WiFi")
            XCTAssertFalse(monitor.isExpensive, "Iteration \(iteration): Should not be expensive")
            
            monitor.simulateConnectionChange(
                isConnected: true,
                connectionType: .cellular,
                isExpensive: true
            )
            XCTAssertEqual(monitor.connectionType, .cellular, "Iteration \(iteration): Should be cellular")
            XCTAssertTrue(monitor.isExpensive, "Iteration \(iteration): Should be expensive")
            
            monitor.simulateConnectionChange(isConnected: false)
            XCTAssertEqual(monitor.connectionType, .unavailable, "Iteration \(iteration): Should be unavailable")
            XCTAssertFalse(monitor.isConnected, "Iteration \(iteration): Should be disconnected")
        }
    }
}
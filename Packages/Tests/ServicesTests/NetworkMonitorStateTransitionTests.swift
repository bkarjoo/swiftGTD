import XCTest
import Foundation
import Combine
@testable import Services
@testable import Core

/// Tests for NetworkMonitor state transitions and connection type detection
@MainActor
final class NetworkMonitorStateTransitionTests: XCTestCase {
    
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        NetworkMonitorFactory.reset() // Ensure clean state
    }
    
    override func tearDown() {
        cancellables = nil
        NetworkMonitorFactory.reset()
        super.tearDown()
    }
    
    // MARK: - State Transition Tests
    
    func testNetworkMonitor_stateTransition_fromConnectedToDisconnected() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        XCTAssertTrue(monitor.isConnected, "Should start connected")
        
        // Act - Disconnect
        monitor.simulateConnectionChange(isConnected: false)
        
        // Assert
        XCTAssertFalse(monitor.isConnected, "Should be disconnected")
        XCTAssertEqual(monitor.connectionType, .unavailable, "Should be unavailable when disconnected")
        XCTAssertTrue(monitor.hasCheckedConnection, "Should mark as checked")
    }
    
    func testNetworkMonitor_stateTransition_fromDisconnectedToConnected() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        monitor.simulateConnectionChange(isConnected: false)
        XCTAssertFalse(monitor.isConnected, "Should be disconnected")
        
        // Act - Connect with WiFi
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi
        )
        
        // Assert
        XCTAssertTrue(monitor.isConnected, "Should be connected")
        XCTAssertEqual(monitor.connectionType, .wifi, "Should be WiFi")
        XCTAssertTrue(monitor.hasCheckedConnection, "Should remain checked")
    }
    
    func testNetworkMonitor_stateTransition_betweenConnectionTypes() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act & Assert - WiFi
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi
        )
        XCTAssertEqual(monitor.connectionType, .wifi, "Should be WiFi")
        XCTAssertFalse(monitor.isExpensive, "WiFi should not be expensive")
        
        // Cellular
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true
        )
        XCTAssertEqual(monitor.connectionType, .cellular, "Should be cellular")
        XCTAssertTrue(monitor.isExpensive, "Cellular should be expensive")
        
        // Wired
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wired
        )
        XCTAssertEqual(monitor.connectionType, .wired, "Should be wired")
        XCTAssertFalse(monitor.isExpensive, "Wired should not be expensive")
        
        // Unknown
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .unknown
        )
        XCTAssertEqual(monitor.connectionType, .unknown, "Should be unknown")
    }
    
    func testNetworkMonitor_stateTransition_preservesConstrainedFlag() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act - Set constrained WiFi
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi,
            isConstrained: true
        )
        
        // Assert
        XCTAssertTrue(monitor.isConstrained, "Should be constrained")
        
        // Act - Change to cellular, keep constrained
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true,
            isConstrained: true
        )
        
        // Assert
        XCTAssertTrue(monitor.isConstrained, "Should remain constrained")
        XCTAssertTrue(monitor.isExpensive, "Should also be expensive")
        
        // Act - Remove constraint
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true,
            isConstrained: false
        )
        
        // Assert
        XCTAssertFalse(monitor.isConstrained, "Should not be constrained")
        XCTAssertTrue(monitor.isExpensive, "Should still be expensive")
    }
    
    func testNetworkMonitor_stateTransition_rapidChanges() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        var states: [(Bool, NetworkMonitor.ConnectionType)] = []
        
        // Track all state changes
        monitor.$isConnected
            .combineLatest(monitor.$connectionType)
            .sink { isConnected, connectionType in
                states.append((isConnected, connectionType))
            }
            .store(in: &cancellables)
        
        // Act - Rapid state changes
        monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
        monitor.simulateConnectionChange(isConnected: false)
        monitor.simulateConnectionChange(isConnected: true, connectionType: .cellular)
        monitor.simulateConnectionChange(isConnected: true, connectionType: .wired)
        monitor.simulateConnectionChange(isConnected: false)
        
        // Assert - All transitions recorded
        XCTAssertGreaterThanOrEqual(states.count, 6, "Should record all state changes including initial")
        XCTAssertEqual(states.last?.0, false, "Should end disconnected")
        XCTAssertEqual(states.last?.1, .unavailable, "Should end unavailable")
    }
    
    // MARK: - Connection Type Detection Tests
    
    func testNetworkMonitor_connectionTypeDetection_wifi() {
        // Arrange & Act
        let monitor = TestableNetworkMonitor()
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi
        )
        
        // Assert
        XCTAssertEqual(monitor.connectionType, .wifi)
        XCTAssertEqual(monitor.connectionType.displayName, "Wi-Fi")
        XCTAssertEqual(monitor.connectionType.symbolName, "wifi")
    }
    
    func testNetworkMonitor_connectionTypeDetection_cellular() {
        // Arrange & Act
        let monitor = TestableNetworkMonitor()
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true
        )
        
        // Assert
        XCTAssertEqual(monitor.connectionType, .cellular)
        XCTAssertEqual(monitor.connectionType.displayName, "Cellular")
        XCTAssertEqual(monitor.connectionType.symbolName, "antenna.radiowaves.left.and.right")
        XCTAssertTrue(monitor.isExpensive)
    }
    
    func testNetworkMonitor_connectionTypeDetection_wired() {
        // Arrange & Act
        let monitor = TestableNetworkMonitor()
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wired
        )
        
        // Assert
        XCTAssertEqual(monitor.connectionType, .wired)
        XCTAssertEqual(monitor.connectionType.displayName, "Wired")
        XCTAssertEqual(monitor.connectionType.symbolName, "cable.connector")
    }
    
    func testNetworkMonitor_connectionTypeDetection_unknown() {
        // Arrange & Act
        let monitor = TestableNetworkMonitor()
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .unknown
        )
        
        // Assert
        XCTAssertEqual(monitor.connectionType, .unknown)
        XCTAssertEqual(monitor.connectionType.displayName, "Unknown")
        XCTAssertEqual(monitor.connectionType.symbolName, "questionmark.circle")
    }
    
    func testNetworkMonitor_connectionTypeDetection_unavailable() {
        // Arrange & Act
        let monitor = TestableNetworkMonitor()
        monitor.simulateConnectionChange(isConnected: false)
        
        // Assert
        XCTAssertEqual(monitor.connectionType, .unavailable)
        XCTAssertEqual(monitor.connectionType.displayName, "No Connection")
        XCTAssertEqual(monitor.connectionType.symbolName, "wifi.slash")
    }
    
    // MARK: - Combine Publisher Tests
    
    func testNetworkMonitor_publisher_notifiesOnConnectionChange() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        var receivedValues: [Bool] = []
        let expectation = XCTestExpectation(description: "Publisher updates")
        expectation.expectedFulfillmentCount = 3 // Initial + 2 changes
        
        monitor.$isConnected
            .sink { isConnected in
                receivedValues.append(isConnected)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Act
        monitor.simulateConnectionChange(isConnected: false)
        monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
        
        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, [true, false, true], "Should receive all state changes")
    }
    
    func testNetworkMonitor_publisher_notifiesOnConnectionTypeChange() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        var receivedTypes: [NetworkMonitor.ConnectionType] = []
        let expectation = XCTestExpectation(description: "Connection type updates")
        expectation.expectedFulfillmentCount = 4 // Initial + 3 changes
        
        monitor.$connectionType
            .sink { type in
                receivedTypes.append(type)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Act
        monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
        monitor.simulateConnectionChange(isConnected: true, connectionType: .cellular)
        monitor.simulateConnectionChange(isConnected: false)
        
        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedTypes, [.unknown, .wifi, .cellular, .unavailable])
    }
    
    func testNetworkMonitor_publisher_notifiesOnExpensiveChange() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        var receivedValues: [Bool] = []
        let expectation = XCTestExpectation(description: "Expensive flag updates")
        expectation.expectedFulfillmentCount = 4
        
        monitor.$isExpensive
            .sink { isExpensive in
                receivedValues.append(isExpensive)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Act
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi,
            isExpensive: false
        )
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true
        )
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wired,
            isExpensive: false
        )
        
        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, [false, false, true, false])
    }
    
    func testNetworkMonitor_publisher_notifiesOnConstrainedChange() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        var receivedValues: [Bool] = []
        let expectation = XCTestExpectation(description: "Constrained flag updates")
        expectation.expectedFulfillmentCount = 3
        
        monitor.$isConstrained
            .sink { isConstrained in
                receivedValues.append(isConstrained)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Act
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi,
            isConstrained: true
        )
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi,
            isConstrained: false
        )
        
        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, [false, true, false])
    }
    
    func testNetworkMonitor_publisher_combineLatestWorks() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        var receivedStates: [(Bool, NetworkMonitor.ConnectionType, Bool)] = []
        
        Publishers.CombineLatest3(
            monitor.$isConnected,
            monitor.$connectionType,
            monitor.$isExpensive
        )
        .sink { isConnected, type, isExpensive in
            receivedStates.append((isConnected, type, isExpensive))
        }
        .store(in: &cancellables)
        
        // Act
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .wifi,
            isExpensive: false
        )
        monitor.simulateConnectionChange(
            isConnected: true,
            connectionType: .cellular,
            isExpensive: true
        )
        
        // Assert - We get many updates as each property changes
        XCTAssertGreaterThanOrEqual(receivedStates.count, 3, "Should have at least 3 updates")
        XCTAssertEqual(receivedStates.last?.0, true, "Should be connected")
        XCTAssertEqual(receivedStates.last?.1, .cellular, "Should be cellular")
        XCTAssertEqual(receivedStates.last?.2, true, "Should be expensive")
    }
    
    // MARK: - hasCheckedConnection Flag Tests
    
    func testNetworkMonitor_hasCheckedConnection_startsAsFalse() {
        // Arrange & Act
        let monitor = TestableNetworkMonitor()
        
        // Assert
        XCTAssertFalse(monitor.hasCheckedConnection, "Should start as false")
    }
    
    func testNetworkMonitor_hasCheckedConnection_becomesTrue() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act
        monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
        
        // Assert
        XCTAssertTrue(monitor.hasCheckedConnection, "Should be true after first check")
    }
    
    func testNetworkMonitor_hasCheckedConnection_remainsTrue() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        
        // Act
        monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
        monitor.simulateConnectionChange(isConnected: false)
        monitor.simulateConnectionChange(isConnected: true, connectionType: .cellular)
        
        // Assert
        XCTAssertTrue(monitor.hasCheckedConnection, "Should remain true")
    }
    
    func testNetworkMonitor_hasCheckedConnection_resetsWithReset() {
        // Arrange
        let monitor = TestableNetworkMonitor()
        monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
        XCTAssertTrue(monitor.hasCheckedConnection, "Should be true after check")
        
        // Act
        monitor.reset()
        
        // Assert
        XCTAssertFalse(monitor.hasCheckedConnection, "Should reset to false")
    }
}
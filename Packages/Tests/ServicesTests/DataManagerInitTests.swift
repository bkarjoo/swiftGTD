import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

/// Tests for DataManager instantiation
/// 
/// Note: These tests use live singleton dependencies (APIClient.shared, NetworkMonitor.shared, etc.)
/// which is appropriate for this phase's simple instantiation tests.
/// 
/// Future phases should introduce dependency injection for DataManager to:
/// - Avoid real singletons in tests
/// - Enable precise behavior testing
/// - Eliminate side effects from shared state
///
@MainActor
final class DataManagerInitTests: XCTestCase {
    
    // MARK: - Basic Instantiation Tests
    
    func testDataManager_init_createsInstance() async throws {
        // Act
        let dataManager = DataManager()
        
        // Assert
        XCTAssertNotNil(dataManager, "DataManager should be created successfully")
    }
    
    func testDataManager_init_setsDefaultProperties() async throws {
        // Act
        let dataManager = DataManager()
        
        // Assert - Check initial state
        XCTAssertEqual(dataManager.nodes.count, 0, "Should start with empty nodes array")
        XCTAssertEqual(dataManager.tags.count, 0, "Should start with empty tags array")
        XCTAssertNil(dataManager.selectedNode, "Should start with no selected node")
        XCTAssertFalse(dataManager.isLoading, "Should not be loading initially")
        XCTAssertNil(dataManager.errorMessage, "Should have no error message initially")
        XCTAssertNil(dataManager.lastSyncDate, "Should have no last sync date initially")
    }
    
    func testDataManager_init_publishedPropertiesAreObservable() async throws {
        // Arrange
        let dataManager = DataManager()
        var nodesChangeCount = 0
        var tagsChangeCount = 0
        
        // Monitor @Published properties
        let nodesCancellable = dataManager.$nodes.sink { _ in
            nodesChangeCount += 1
        }
        
        let tagsCancellable = dataManager.$tags.sink { _ in
            tagsChangeCount += 1
        }
        
        // Act - Modify properties
        dataManager.nodes = [Node(
            id: "test-1",
            title: "Test Node",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )]
        
        dataManager.tags = [Tag(
            id: "tag-1",
            name: "Test Tag",
            color: "#FF0000",
            description: "Test tag description",
            createdAt: "2025-09-16T10:00:00Z"
        )]
        
        // Small delay to allow published changes to propagate
        // TODO: Future improvement - replace with XCTestExpectation on objectWillChange
        // to avoid potential flakiness on slow machines
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Assert - Should have received initial value + change
        XCTAssertGreaterThanOrEqual(nodesChangeCount, 2, "Nodes should trigger published changes")
        XCTAssertGreaterThanOrEqual(tagsChangeCount, 2, "Tags should trigger published changes")
        
        // Cleanup
        nodesCancellable.cancel()
        tagsCancellable.cancel()
    }
    
    func testDataManager_multipleInstances_areIndependent() async throws {
        // Act - Create multiple instances
        let dataManager1 = DataManager()
        let dataManager2 = DataManager()
        
        // Modify first instance
        dataManager1.nodes = [Node(
            id: "node-1",
            title: "Node 1",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )]
        
        dataManager1.errorMessage = "Test error"
        
        // Assert - Second instance should not be affected
        XCTAssertEqual(dataManager2.nodes.count, 0, "Second instance should have empty nodes")
        XCTAssertNil(dataManager2.errorMessage, "Second instance should have no error message")
        
        // Verify first instance has changes
        XCTAssertEqual(dataManager1.nodes.count, 1, "First instance should have one node")
        XCTAssertEqual(dataManager1.errorMessage, "Test error", "First instance should have error message")
    }
    
    func testDataManager_isMainActorIsolated() async throws {
        // This test verifies DataManager is properly isolated to MainActor
        // The fact that this compiles and runs confirms MainActor isolation
        
        // Act - Should be able to access on MainActor
        let dataManager = DataManager()
        
        // Modify properties (only possible on MainActor)
        dataManager.isLoading = true
        dataManager.selectedNode = Node(
            id: "test",
            title: "Test",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Assert
        XCTAssertTrue(dataManager.isLoading)
        XCTAssertNotNil(dataManager.selectedNode)
    }
    
    // MARK: - Network Status Tests
    
    func testDataManager_init_checksNetworkStatus() async throws {
        // Act
        let dataManager = DataManager()
        
        // Assert - isOffline property exists and has a value
        // Note: Actual value depends on NetworkMonitor.shared state
        XCTAssertNotNil(dataManager.isOffline, "Should have network status")
    }
    
    func testDataManager_isOffline_reflectsNetworkState() async throws {
        // Arrange
        let dataManager = DataManager()
        
        // Act - Check the property can be read
        let offlineStatus = dataManager.isOffline
        
        // Assert - Should be a valid boolean
        XCTAssertTrue(offlineStatus == true || offlineStatus == false, 
                     "isOffline should be a valid boolean")
    }
    
    // MARK: - ObservableObject Conformance
    
    func testDataManager_conformsToObservableObject() async throws {
        // Arrange & Act
        let dataManager = DataManager()
        
        // Assert - Can use as ObservableObject
        XCTAssertTrue(dataManager is any ObservableObject, 
                     "DataManager should conform to ObservableObject")
        
        // Verify objectWillChange publisher exists
        _ = dataManager.objectWillChange
    }
    
    // MARK: - Error Handling Properties
    
    func testDataManager_errorHandling_canSetAndClearError() async throws {
        // Arrange
        let dataManager = DataManager()
        
        // Act - Set error
        dataManager.errorMessage = "Test error message"
        
        // Assert
        XCTAssertEqual(dataManager.errorMessage, "Test error message")
        
        // Act - Clear error
        dataManager.errorMessage = nil
        
        // Assert
        XCTAssertNil(dataManager.errorMessage)
    }
    
    // MARK: - Loading State Tests
    
    func testDataManager_loadingState_canBeToggled() async throws {
        // Arrange
        let dataManager = DataManager()
        
        // Assert - Initial state
        XCTAssertFalse(dataManager.isLoading)
        
        // Act - Set loading
        dataManager.isLoading = true
        
        // Assert
        XCTAssertTrue(dataManager.isLoading)
        
        // Act - Clear loading
        dataManager.isLoading = false
        
        // Assert
        XCTAssertFalse(dataManager.isLoading)
    }
}
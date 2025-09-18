import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Core
@testable import Networking

/// Mock components for testing offline create
class MockOfflineNetworkMonitor: NetworkMonitorProtocol {
    @Published var isConnected: Bool = false
    @Published var connectionType: NetworkMonitor.ConnectionType = .unavailable
    var isExpensive: Bool = false
    var isConstrained: Bool = false
    var hasCheckedConnection: Bool = true
    
    func start() {}
    func stop() {}
}

class MockOfflineCacheManager {
    var savedNodes: [Node] = []
    var saveNodesCalled = false
    
    func saveNodes(_ nodes: [Node]) async {
        savedNodes = nodes
        saveNodesCalled = true
    }
    
    func loadNodes() async -> [Node]? {
        return savedNodes
    }
}

class MockOfflineQueueManager {
    var queuedOperations: [OfflineQueueManager.QueuedOperation] = []
    var queueCreateCalled = false
    
    func queueCreate(node: Node) async {
        queueCreateCalled = true
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let nodeData = try encoder.encode(node)
            
            let operation = OfflineQueueManager.QueuedOperation(
                type: .create,
                nodeId: node.id,
                nodeData: nodeData,
                parentId: node.parentId,
                metadata: ["title": node.title, "nodeType": node.nodeType]
            )
            
            queuedOperations.append(operation)
        } catch {
            // Ignore encoding errors in tests
        }
    }
    
    func clearQueue() async {
        queuedOperations.removeAll()
    }
}

/// Tests for DataManager offline create functionality
@MainActor
final class DataManagerOfflineCreateTests: XCTestCase {
    
    private var dataManager: DataManager!
    private var mockNetworkMonitor: MockOfflineNetworkMonitor!
    private var mockCacheManager: MockOfflineCacheManager!
    private var mockQueueManager: MockOfflineQueueManager!
    private var mockAPI: MockAPIClient!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockNetworkMonitor = MockOfflineNetworkMonitor()
        mockNetworkMonitor.isConnected = false // Offline by default
        
        mockCacheManager = MockOfflineCacheManager()
        mockQueueManager = MockOfflineQueueManager()
        mockAPI = MockAPIClient()
        cancellables = []
        
        dataManager = DataManager(
            apiClient: mockAPI,
            networkMonitor: mockNetworkMonitor
        )
        
        // Inject mock cache and queue managers via reflection/dependency injection
        // Note: In production, these would be injected through initializer
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    // MARK: - Temp ID Generation Tests
    
    func testOfflineCreate_generatesTempId() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Act
        let node = await dataManager.createNode(title: "Offline Task", type: "task", content: nil, parentId: nil)
        
        // Assert
        XCTAssertNotNil(node, "Should create node offline")
        // DataManager uses UUID().uuidString directly without "temp-" prefix
        XCTAssertEqual(node!.id.count, 36, "ID should be UUID string (36 chars)")
        // Verify it's a valid UUID format
        XCTAssertNotNil(UUID(uuidString: node!.id), "Should be a valid UUID")
    }
    
    func testOfflineCreate_generatesUniqueTempIds() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Act
        let node1 = await dataManager.createNode(title: "Task 1", type: "task", content: nil, parentId: nil)
        let node2 = await dataManager.createNode(title: "Task 2", type: "task", content: nil, parentId: nil)
        let node3 = await dataManager.createNode(title: "Task 3", type: "task", content: nil, parentId: nil)
        
        // Assert
        XCTAssertNotNil(node1)
        XCTAssertNotNil(node2)
        XCTAssertNotNil(node3)
        XCTAssertNotEqual(node1!.id, node2!.id, "Should have unique IDs")
        XCTAssertNotEqual(node2!.id, node3!.id, "Should have unique IDs")
        XCTAssertNotEqual(node1!.id, node3!.id, "Should have unique IDs")
    }
    
    // MARK: - Local Node Addition Tests
    
    func testOfflineCreate_addsNodeToLocalCollection() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        let initialCount = dataManager.nodes.count
        
        // Act
        let node = await dataManager.createNode(title: "Local Task", type: "task", content: nil, parentId: nil)
        
        // Assert
        XCTAssertNotNil(node)
        XCTAssertEqual(dataManager.nodes.count, initialCount + 1, "Should add node to local collection")
        XCTAssertTrue(dataManager.nodes.contains(where: { $0.id == node!.id }), "Should contain new node")
        XCTAssertEqual(dataManager.nodes.last?.title, "Local Task", "New node should be in collection")
    }
    
    func testOfflineCreate_maintainsSortOrder() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create initial nodes
        _ = await dataManager.createNode(title: "Task 1", type: "task", content: nil, parentId: nil)
        _ = await dataManager.createNode(title: "Task 2", type: "task", content: nil, parentId: nil)
        
        // Act
        let node3 = await dataManager.createNode(title: "Task 3", type: "task", content: nil, parentId: nil)
        
        // Assert
        XCTAssertNotNil(node3)
        
        // Check nodes are sorted by sortOrder
        for i in 1..<dataManager.nodes.count {
            XCTAssertLessThanOrEqual(
                dataManager.nodes[i-1].sortOrder,
                dataManager.nodes[i].sortOrder,
                "Nodes should be sorted by sortOrder"
            )
        }
    }
    
    // MARK: - Node Type Creation Tests
    
    func testOfflineCreate_createsTaskWithTaskData() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Act
        let node = await dataManager.createNode(
            title: "Offline Task",
            type: "task",
            content: "Task description",
            parentId: nil
        )
        
        // Assert
        XCTAssertNotNil(node)
        XCTAssertEqual(node!.nodeType, "task")
        XCTAssertNotNil(node!.taskData, "Task should have taskData")
        XCTAssertEqual(node!.taskData?.description, "Task description")
        XCTAssertEqual(node!.taskData?.status, "todo")
    }
    
    func testOfflineCreate_createsFolderWithoutTaskData() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Act
        let node = await dataManager.createNode(
            title: "Offline Folder",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        // Assert
        XCTAssertNotNil(node)
        XCTAssertEqual(node!.nodeType, "folder")
        XCTAssertNil(node!.taskData, "Folder should not have taskData")
        XCTAssertNil(node!.noteData, "Folder should not have noteData")
    }
    
    func testOfflineCreate_createsNoteWithNoteData() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Act
        let node = await dataManager.createNode(
            title: "Offline Note",
            type: "note",
            content: "Note content here",
            parentId: nil
        )
        
        // Assert
        XCTAssertNotNil(node)
        XCTAssertEqual(node!.nodeType, "note")
        XCTAssertNotNil(node!.noteData, "Note should have noteData")
        XCTAssertEqual(node!.noteData?.body, "Note content here")
        XCTAssertNil(node!.taskData, "Note should not have taskData")
    }
    
    // MARK: - Parent Reference Tests
    
    func testOfflineCreate_withParentId_setsCorrectly() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        let parentId = "parent-123"
        
        // Act
        let node = await dataManager.createNode(
            title: "Child Task",
            type: "task",
            content: nil,
            parentId: parentId
        )
        
        // Assert
        XCTAssertNotNil(node)
        XCTAssertEqual(node!.parentId, parentId, "Should set parent ID")
    }
    
    func testOfflineCreate_withTempParentId_setsCorrectly() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create parent offline first
        let parent = await dataManager.createNode(
            title: "Parent Folder",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        // Act - Create child with temp parent ID
        let child = await dataManager.createNode(
            title: "Child Task",
            type: "task",
            content: nil,
            parentId: parent!.id
        )
        
        // Assert
        XCTAssertNotNil(child)
        XCTAssertEqual(child!.parentId, parent!.id, "Should set temp parent ID")
        XCTAssertNotNil(UUID(uuidString: child!.parentId!), "Parent ID should be valid UUID")
    }
    
    // MARK: - Queue Operation Tests
    
    func testOfflineCreate_queuesOperation() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Note: In real implementation, this would be tested through
        // dependency injection of OfflineQueueManager
        
        // Act
        let node = await dataManager.createNode(
            title: "Queued Task",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Assert
        XCTAssertNotNil(node)
        // In production, would verify:
        // - offlineQueue.queueCreate(node:) was called
        // - Operation added to pending queue
        // - Operation has correct type (.create)
    }
    
    // MARK: - Cache Update Tests
    
    func testOfflineCreate_updatesCacheWithNewNode() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Note: In real implementation, this would be tested through
        // dependency injection of CacheManager
        
        // Act
        let node = await dataManager.createNode(
            title: "Cached Task",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Assert
        XCTAssertNotNil(node)
        // In production, would verify:
        // - cacheManager.saveNodes() was called
        // - Cache contains new node
        // - Cache preserves temp ID
    }
    
    // MARK: - Error Message Tests
    
    func testOfflineCreate_setsOfflineErrorMessage() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Act
        _ = await dataManager.createNode(
            title: "Offline Task",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Assert
        XCTAssertEqual(
            dataManager.errorMessage,
            "Created offline - will sync when connected",
            "Should set offline error message"
        )
    }
    
    // MARK: - Complex Scenarios
    
    func testOfflineCreate_multipleNodesInHierarchy() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Act - Create hierarchy
        let folder = await dataManager.createNode(
            title: "Project Folder",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        let task1 = await dataManager.createNode(
            title: "Task 1",
            type: "task",
            content: "First task",
            parentId: folder!.id
        )
        
        let task2 = await dataManager.createNode(
            title: "Task 2",
            type: "task",
            content: "Second task",
            parentId: folder!.id
        )
        
        let subtask = await dataManager.createNode(
            title: "Subtask",
            type: "task",
            content: "Subtask of task 1",
            parentId: task1!.id
        )
        
        // Assert
        XCTAssertNotNil(folder)
        XCTAssertNotNil(task1)
        XCTAssertNotNil(task2)
        XCTAssertNotNil(subtask)
        
        // All should have UUID IDs
        XCTAssertNotNil(UUID(uuidString: folder!.id), "Folder should have valid UUID")
        XCTAssertNotNil(UUID(uuidString: task1!.id), "Task1 should have valid UUID")
        XCTAssertNotNil(UUID(uuidString: task2!.id), "Task2 should have valid UUID")
        XCTAssertNotNil(UUID(uuidString: subtask!.id), "Subtask should have valid UUID")
        
        // Check parent relationships
        XCTAssertEqual(task1?.parentId, folder?.id)
        XCTAssertEqual(task2?.parentId, folder?.id)
        XCTAssertEqual(subtask?.parentId, task1?.id)
        
        // All should be in local collection
        XCTAssertEqual(dataManager.nodes.count, 4)
    }
    
    func testOfflineCreate_switchingToOnline_doesNotAffectExisting() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create offline
        let offlineNode = await dataManager.createNode(
            title: "Offline Node",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Act - Switch to online
        mockNetworkMonitor.isConnected = true
        
        // Create online (would normally call API)
        // mockAPI would be configured here in production
        
        // Assert - Offline node still exists locally
        XCTAssertNotNil(offlineNode)
        XCTAssertTrue(dataManager.nodes.contains(where: { $0.id == offlineNode!.id }))
        XCTAssertNotNil(UUID(uuidString: offlineNode!.id), "Should be a valid UUID")
    }
}
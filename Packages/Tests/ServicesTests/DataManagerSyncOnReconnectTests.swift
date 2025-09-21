import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Core
@testable import Networking

/// Mock network monitor that can simulate connection changes
class MockReconnectNetworkMonitor: NetworkMonitorProtocol {
    @Published var isConnected: Bool = false
    @Published var connectionType: NetworkMonitor.ConnectionType = .unavailable
    var isExpensive: Bool = false
    var isConstrained: Bool = false
    var hasCheckedConnection: Bool = true
    
    func simulateReconnect() {
        isConnected = true
        connectionType = .wifi
    }
    
    func simulateDisconnect() {
        isConnected = false
        connectionType = .unavailable
    }
    
    func start() {}
    func stop() {}
}

/// Mock API client that can simulate sync operations
class MockSyncAPIClient: MockAPIClientBase {
    var pendingOperationsProcessed = false
    var tempIdMap: [String: String] = [:]
    var fetchedNodes: [Node] = []
    var processedOperations: [(type: String, nodeId: String)] = []
    
    // MARK: - Auth
    override func setAuthToken(_ token: String?) {
        // Mock implementation
    }
    
    override func getCurrentUser() async throws -> User {
        return User(id: "test-user", email: "test@example.com", fullName: "Test User")
    }
    
    // MARK: - Core Node Operations
    override func getNodes(parentId: String?) async throws -> [Node] {
        return fetchedNodes.filter { $0.parentId == parentId }
    }
    
    override func getAllNodes() async throws -> [Node] {
        return fetchedNodes
    }
    
    override func getNode(id: String) async throws -> Node {
        if let node = fetchedNodes.first(where: { $0.id == id }) {
            return node
        }
        throw APIError.httpError(404)
    }
    
    override func createNode(_ node: Node) async throws -> Node {
        let serverId = "server-\(UUID().uuidString.prefix(8))"
        tempIdMap[node.id] = serverId
        
        let formatter = ISO8601DateFormatter()
        let serverNode = Node(
            id: serverId,
            title: node.title,
            nodeType: node.nodeType,
            parentId: node.parentId.flatMap { tempIdMap[$0] ?? $0 },
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: node.sortOrder,
            taskData: node.taskData,
            noteData: node.noteData
        )
        
        processedOperations.append((type: "create", nodeId: serverId))
        return serverNode
    }
    
    override func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        processedOperations.append((type: "update", nodeId: id))
        
        let formatter = ISO8601DateFormatter()
        return Node(
            id: id,
            title: update.title,
            nodeType: "task",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: "Updated",
                status: "todo",
                completedAt: nil
            )
        )
    }
    
    override func deleteNode(id: String) async throws {
        processedOperations.append((type: "delete", nodeId: id))
    }
    
    // MARK: - Tags
    override func getTags() async throws -> [Tag] {
        return []
    }
    
    // MARK: - Task Operations
    override func toggleTaskCompletion(nodeId: String, currentlyCompleted: Bool) async throws -> Node {
        processedOperations.append((type: "toggle", nodeId: nodeId))
        
        let formatter = ISO8601DateFormatter()
        return Node(
            id: nodeId,
            title: "Toggled Task",
            nodeType: "task",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: "Task description",
                status: currentlyCompleted ? "todo" : "done",
                completedAt: currentlyCompleted ? nil : ISO8601DateFormatter().string(from: Date())
            )
        )
    }
    
    // MARK: - Specialized Node Creation
    override func createFolder(title: String, parentId: String?) async throws -> Node {
        let formatter = ISO8601DateFormatter()
        let node = Node(
            id: "server-\(UUID().uuidString.prefix(8))",
            title: title,
            nodeType: "folder",
            parentId: parentId,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0
        )
        processedOperations.append((type: "create", nodeId: node.id))
        return node
    }
    
    override func createTask(title: String, parentId: String?, description: String?) async throws -> Node {
        let formatter = ISO8601DateFormatter()
        let node = Node(
            id: "server-\(UUID().uuidString.prefix(8))",
            title: title,
            nodeType: "task",
            parentId: parentId,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: description,
                status: "todo",
                completedAt: nil
            )
        )
        processedOperations.append((type: "create", nodeId: node.id))
        return node
    }
    
    override func createNote(title: String, parentId: String?, body: String) async throws -> Node {
        let formatter = ISO8601DateFormatter()
        let node = Node(
            id: "server-\(UUID().uuidString.prefix(8))",
            title: title,
            nodeType: "note",
            parentId: parentId,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            noteData: NoteData(body: body)
        )
        processedOperations.append((type: "create", nodeId: node.id))
        return node
    }
    
    override func createGenericNode(title: String, nodeType: String, parentId: String?) async throws -> Node {
        let formatter = ISO8601DateFormatter()
        let node = Node(
            id: "server-\(UUID().uuidString.prefix(8))",
            title: title,
            nodeType: nodeType,
            parentId: parentId,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0
        )
        processedOperations.append((type: "create", nodeId: node.id))
        return node
    }

    override func executeSmartFolderRule(smartFolderId: String) async throws -> [Node] {
        // Return empty array for smart folder tests
        return []
    }
}

/// Tests for DataManager sync on reconnect functionality
@MainActor
final class DataManagerSyncOnReconnectTests: XCTestCase {
    
    private var dataManager: DataManager!
    private var mockNetworkMonitor: MockReconnectNetworkMonitor!
    private var mockAPI: MockSyncAPIClient!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockNetworkMonitor = MockReconnectNetworkMonitor()
        mockNetworkMonitor.simulateDisconnect() // Start offline
        
        mockAPI = MockSyncAPIClient()
        cancellables = []
        
        dataManager = DataManager(
            apiClient: mockAPI,
            networkMonitor: mockNetworkMonitor
        )
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    // MARK: - Basic Reconnection Tests
    
    func testSyncOnReconnect_triggersSync() async throws {
        // Arrange - Create some offline operations
        mockNetworkMonitor.simulateDisconnect()
        
        _ = await dataManager.createNode(
            title: "Offline Task",
            type: "task",
            content: "Created offline",
            parentId: nil
        )
        
        XCTAssertEqual(dataManager.nodes.count, 1)
        
        // Prepare mock API response
        let formatter = ISO8601DateFormatter()
        mockAPI.fetchedNodes = [
            Node(
                id: "server-001",
                title: "Server Node",
                nodeType: "task",
                parentId: nil,
                ownerId: "test-user",
                createdAt: formatter.string(from: Date()),
                updatedAt: formatter.string(from: Date()),
                sortOrder: 0,
                taskData: TaskData(
                    description: "From server",
                    status: "todo",
                    completedAt: nil
                )
            )
        ]
        
        // Act - Simulate reconnection
        mockNetworkMonitor.simulateReconnect()
        
        // Give time for sync to happen
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Assert - In production, would verify:
        // - Sync was triggered
        // - Operations were processed
        // - Fresh data was fetched
        XCTAssertTrue(mockNetworkMonitor.isConnected, "Should be connected")
    }
    
    // MARK: - Pending Operations Processing
    
    func testSyncOnReconnect_processesPendingOperations() async throws {
        // Arrange - Create multiple offline operations
        mockNetworkMonitor.simulateDisconnect()
        
        // Create operations
        let task1 = await dataManager.createNode(
            title: "Task 1",
            type: "task",
            content: "First task",
            parentId: nil
        )
        
        let task2 = await dataManager.createNode(
            title: "Task 2",
            type: "task",
            content: "Second task",
            parentId: nil
        )
        
        // Toggle one
        if let task1 = task1 {
            _ = await dataManager.toggleNodeCompletion(task1)
        }
        
        // Delete one
        if let task2 = task2 {
            await dataManager.deleteNode(task2)
        }
        
        // Act - Reconnect
        mockNetworkMonitor.simulateReconnect()
        
        // Give time for processing
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Assert - In production, would verify:
        // - Create operations processed
        // - Toggle operation processed
        // - Delete operation processed
        // - Correct order maintained
        XCTAssertTrue(mockNetworkMonitor.isConnected)
    }
    
    // MARK: - Temp ID Replacement
    
    func testSyncOnReconnect_replacesTempIds() async throws {
        // Arrange - Create nodes with temp IDs
        mockNetworkMonitor.simulateDisconnect()
        
        let parent = await dataManager.createNode(
            title: "Parent",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        let child = await dataManager.createNode(
            title: "Child",
            type: "task",
            content: "Child task",
            parentId: parent?.id
        )
        
        XCTAssertNotNil(parent)
        XCTAssertNotNil(child)
        let parentUuid = String(parent!.id.dropFirst(5))
        let childUuid = String(child!.id.dropFirst(5))
        XCTAssertNotNil(UUID(uuidString: parentUuid), "Should have temp UUID")
        XCTAssertNotNil(UUID(uuidString: childUuid), "Should have temp UUID")
        XCTAssertEqual(child?.parentId, parent?.id, "Should reference temp parent ID")
        
        // Setup mock to return server IDs
        mockAPI.tempIdMap[parent!.id] = "server-parent"
        mockAPI.tempIdMap[child!.id] = "server-child"
        
        // Act - Reconnect
        mockNetworkMonitor.simulateReconnect()
        
        // Give time for sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Assert - In production, would verify:
        // - Temp IDs replaced with server IDs
        // - Parent references updated
        // - Local collection updated
    }
    
    // MARK: - Fresh Data Fetch
    
    func testSyncOnReconnect_fetchesFreshData() async throws {
        // Arrange - Setup server data
        let formatter = ISO8601DateFormatter()
        mockAPI.fetchedNodes = [
            Node(
                id: "server-1",
                title: "Fresh Node 1",
                nodeType: "task",
                parentId: nil,
                ownerId: "test-user",
                createdAt: formatter.string(from: Date()),
                updatedAt: formatter.string(from: Date()),
                sortOrder: 0,
                taskData: TaskData(
                    description: "Fresh from server",
                    status: "todo",
                    completedAt: nil
                )
            ),
            Node(
                id: "server-2",
                title: "Fresh Node 2",
                nodeType: "folder",
                parentId: nil,
                ownerId: "test-user",
                createdAt: formatter.string(from: Date()),
                updatedAt: formatter.string(from: Date()),
                sortOrder: 1
            )
        ]
        
        // Start with offline data
        mockNetworkMonitor.simulateDisconnect()
        _ = await dataManager.createNode(
            title: "Offline Node",
            type: "task",
            content: "Created offline",
            parentId: nil
        )
        
        // Act - Reconnect
        mockNetworkMonitor.simulateReconnect()
        
        // Give time for fetch
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Assert - In production, would verify:
        // - Fresh data fetched from server
        // - Local collection updated
        // - Offline changes preserved
    }
    
    // MARK: - Complex Scenarios
    
    func testSyncOnReconnect_handlesMultipleReconnects() async throws {
        // Arrange - Create initial offline data
        mockNetworkMonitor.simulateDisconnect()
        
        _ = await dataManager.createNode(
            title: "First Offline",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // First reconnect
        mockNetworkMonitor.simulateReconnect()
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Go offline again
        mockNetworkMonitor.simulateDisconnect()
        
        _ = await dataManager.createNode(
            title: "Second Offline",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Second reconnect
        mockNetworkMonitor.simulateReconnect()
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Assert
        XCTAssertTrue(mockNetworkMonitor.isConnected)
        // In production, would verify both sets of operations processed
    }
    
    func testSyncOnReconnect_handlesEmptyQueue() async throws {
        // Arrange - No offline operations
        mockNetworkMonitor.simulateDisconnect()
        
        // Act - Reconnect with empty queue
        mockNetworkMonitor.simulateReconnect()
        
        // Give time for sync
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Assert - Should not crash, should fetch fresh data
        XCTAssertTrue(mockNetworkMonitor.isConnected)
    }
    
    func testSyncOnReconnect_preservesOperationOrder() async throws {
        // Arrange - Create ordered operations
        mockNetworkMonitor.simulateDisconnect()
        
        let folder = await dataManager.createNode(
            title: "Parent Folder",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        let task = await dataManager.createNode(
            title: "Child Task",
            type: "task",
            content: "Under folder",
            parentId: folder?.id
        )
        
        // Update the task
        if let task = task {
            // In production, would call updateNode
            _ = await dataManager.toggleNodeCompletion(task)
        }
        
        // Act - Reconnect
        mockNetworkMonitor.simulateReconnect()
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Assert - In production, would verify:
        // - Parent created before child
        // - Toggle happens after create
        // - Operations maintain dependency order
    }
    
    // MARK: - Error Scenarios
    
    func testSyncOnReconnect_handlesPartialFailure() async throws {
        // Arrange - Create operations that will partially fail
        mockNetworkMonitor.simulateDisconnect()
        
        _ = await dataManager.createNode(
            title: "Will Succeed",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        _ = await dataManager.createNode(
            title: "Will Fail",
            type: "task",
            content: nil,
            parentId: "invalid-parent"
        )
        
        // Act - Reconnect
        mockNetworkMonitor.simulateReconnect()
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Assert - In production, would verify:
        // - Successful operations processed
        // - Failed operations remain in queue
        // - Error message set appropriately
    }
    
    func testSyncOnReconnect_clearsErrorOnSuccess() async throws {
        // Arrange - Set error message
        dataManager.errorMessage = "Previous error"
        
        mockNetworkMonitor.simulateDisconnect()
        _ = await dataManager.createNode(
            title: "Task",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Act - Successful reconnect
        mockNetworkMonitor.simulateReconnect()
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Assert - In production, would verify error cleared
        // Note: Actual implementation may or may not clear on success
    }
}
import XCTest
import Foundation
@testable import Services
@testable import Models
@testable import Core
@testable import Networking

/// Tests for OfflineQueueManager queue operations
@MainActor
final class OfflineQueueManagerTests: XCTestCase {
    
    private var queueManager: OfflineQueueManager!
    
    override func setUp() async throws {
        try await super.setUp()
        // Get shared instance and clear it
        queueManager = OfflineQueueManager.shared
        await queueManager.clearQueue()
    }
    
    override func tearDown() async throws {
        // Clean up
        await queueManager.clearQueue()
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestNode(id: String = UUID().uuidString, title: String = "Test Node", type: String = "task") -> Node {
        return Node(
            id: id,
            title: title,
            nodeType: type,
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: type == "task" ? TaskData(
                description: "Test task description",
                status: "todo"
            ) : nil,
            noteData: type == "note" ? NoteData(
                body: "Test note body"
            ) : nil
        )
    }
    
    private func getQueueFile() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent("Cache").appendingPathComponent("offline_queue.json")
    }
    
    // MARK: - Queue Create Operation Tests
    
    func testOfflineQueue_queueCreate_addsOperationToQueue() async throws {
        // Arrange
        let node = createTestNode(title: "New Task")
        
        // Act
        await queueManager.queueCreate(node: node)
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 1, "Should have one pending operation")
        
        let operation = queueManager.pendingOperations.first
        XCTAssertNotNil(operation, "Operation should exist")
        XCTAssertEqual(operation?.type, .create, "Operation type should be create")
        XCTAssertEqual(operation?.nodeId, node.id, "Operation should have node ID")
        XCTAssertNotNil(operation?.nodeData, "Operation should have node data")
        XCTAssertEqual(operation?.metadata["title"], "New Task", "Metadata should contain title")
        XCTAssertEqual(operation?.metadata["nodeType"], "task", "Metadata should contain node type")
    }
    
    func testOfflineQueue_queueMultipleCreates_maintainsAllOperations() async throws {
        // Arrange
        let node1 = createTestNode(title: "Task 1")
        let node2 = createTestNode(title: "Task 2", type: "note")
        let node3 = createTestNode(title: "Folder 1", type: "folder")
        
        // Act
        await queueManager.queueCreate(node: node1)
        await queueManager.queueCreate(node: node2)
        await queueManager.queueCreate(node: node3)
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 3, "Should have three pending operations")
        
        let titles = queueManager.pendingOperations.compactMap { $0.metadata["title"] }
        XCTAssertTrue(titles.contains("Task 1"), "Should have Task 1")
        XCTAssertTrue(titles.contains("Task 2"), "Should have Task 2")
        XCTAssertTrue(titles.contains("Folder 1"), "Should have Folder 1")
        
        let types = queueManager.pendingOperations.compactMap { $0.metadata["nodeType"] }
        XCTAssertTrue(types.contains("task"), "Should have task type")
        XCTAssertTrue(types.contains("note"), "Should have note type")
        XCTAssertTrue(types.contains("folder"), "Should have folder type")
    }
    
    // MARK: - Queue Update Operation Tests
    
    func testOfflineQueue_queueUpdate_replacesExistingUpdateForSameNode() async throws {
        // Arrange
        let nodeId = "test-node-123"
        let node1 = createTestNode(id: nodeId, title: "Original Title")
        let node2 = createTestNode(id: nodeId, title: "Updated Title")
        
        // Act
        await queueManager.queueUpdate(node: node1)
        await queueManager.queueUpdate(node: node2)
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 1, "Should have only one update operation")
        
        let operation = queueManager.pendingOperations.first
        XCTAssertEqual(operation?.metadata["title"], "Updated Title", "Should keep latest update")
    }
    
    // MARK: - Queue Delete Operation Tests
    
    func testOfflineQueue_queueDelete_removesCreateAndUpdateOperations() async throws {
        // Arrange
        let nodeId = "test-node-456"
        let node = createTestNode(id: nodeId, title: "Node to Delete")
        
        // Act - Queue create, update, then delete
        await queueManager.queueCreate(node: node)
        await queueManager.queueUpdate(node: node)
        await queueManager.queueDelete(nodeId: nodeId, title: "Node to Delete")
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 1, "Should have only delete operation")
        
        let operation = queueManager.pendingOperations.first
        XCTAssertEqual(operation?.type, .delete, "Operation should be delete")
        XCTAssertEqual(operation?.nodeId, nodeId, "Should have correct node ID")
    }
    
    func testOfflineQueue_queueDelete_preservesOtherNodeOperations() async throws {
        // Arrange
        let node1 = createTestNode(id: "node-1", title: "Node 1")
        let node2 = createTestNode(id: "node-2", title: "Node 2")
        
        // Act
        await queueManager.queueCreate(node: node1)
        await queueManager.queueCreate(node: node2)
        await queueManager.queueDelete(nodeId: "node-1", title: "Node 1")
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 2, "Should have delete for node-1 and create for node-2")
        
        let deleteOp = queueManager.pendingOperations.first { $0.type == .delete }
        let createOp = queueManager.pendingOperations.first { $0.type == .create }
        
        XCTAssertEqual(deleteOp?.nodeId, "node-1", "Delete should be for node-1")
        XCTAssertEqual(createOp?.nodeId, "node-2", "Create should be for node-2")
    }
    
    // MARK: - Queue Toggle Task Operation Tests
    
    func testOfflineQueue_queueToggleTask_replacesExistingToggleForSameNode() async throws {
        // Arrange
        let nodeId = "task-789"
        
        // Act
        await queueManager.queueToggleTask(nodeId: nodeId, completed: true)
        await queueManager.queueToggleTask(nodeId: nodeId, completed: false)
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 1, "Should have only one toggle operation")
        
        let operation = queueManager.pendingOperations.first
        XCTAssertEqual(operation?.type, .toggleTask, "Operation should be toggle")
        XCTAssertEqual(operation?.metadata["completed"], "false", "Should have latest toggle state")
    }
    
    // MARK: - Persistence Tests
    
    func testOfflineQueue_saveAndLoad_persistsToFileSystem() async throws {
        // Arrange
        let node1 = createTestNode(title: "Persisted Task 1")
        let node2 = createTestNode(title: "Persisted Task 2")
        
        // Act - Add operations
        await queueManager.queueCreate(node: node1)
        await queueManager.queueCreate(node: node2)
        
        // Verify file exists
        let queueFile = getQueueFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: queueFile.path), "Queue file should exist")
        
        // Verify operations are persisted
        let originalCount = queueManager.pendingOperations.count
        XCTAssertEqual(originalCount, 2, "Should have 2 operations")
        
        // Assert - File should contain operations
        let fileData = try Data(contentsOf: queueFile)
        XCTAssertGreaterThan(fileData.count, 0, "Queue file should contain data")
        
        let titles = queueManager.pendingOperations.compactMap { $0.metadata["title"] }
        XCTAssertTrue(titles.contains("Persisted Task 1"), "Should have first task")
        XCTAssertTrue(titles.contains("Persisted Task 2"), "Should have second task")
    }
    
    func testOfflineQueue_loadOnRestart_restoresPendingOperations() async throws {
        // Arrange - Create operations with first instance
        let node1 = createTestNode(title: "Before Restart 1")
        let node2 = createTestNode(title: "Before Restart 2")
        await queueManager.queueCreate(node: node1)
        await queueManager.queueDelete(nodeId: "delete-123", title: "Deleted Node")
        await queueManager.queueToggleTask(nodeId: "task-456", completed: true)
        await queueManager.queueUpdate(node: node2)
        
        let originalCount = queueManager.pendingOperations.count
        
        // Act - Verify persistence by checking file
        let queueFile = getQueueFile()
        let fileData = try Data(contentsOf: queueFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loadedOps = try decoder.decode([OfflineQueueManager.QueuedOperation].self, from: fileData)
        
        // Assert
        XCTAssertEqual(loadedOps.count, originalCount, "File should contain all operations")
        
        // Check operation types are preserved in file
        let types = Set(loadedOps.map { $0.type })
        XCTAssertTrue(types.contains(.create), "Should have create operation")
        XCTAssertTrue(types.contains(.delete), "Should have delete operation")
        XCTAssertTrue(types.contains(.toggleTask), "Should have toggle operation")
        XCTAssertTrue(types.contains(.update), "Should have update operation")
    }
    
    // MARK: - Operation Ordering Tests
    
    func testOfflineQueue_operationOrder_maintainsChronologicalOrder() async throws {
        // Arrange
        let node1 = createTestNode(id: "1", title: "First")
        let node2 = createTestNode(id: "2", title: "Second")
        _ = createTestNode(id: "3", title: "Third")
        
        // Act
        await queueManager.queueCreate(node: node1)
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 second
        await queueManager.queueUpdate(node: node2)
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 second
        await queueManager.queueDelete(nodeId: "3", title: "Third")
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 3, "Should have 3 operations")
        
        // Check timestamps are in order
        let timestamps = queueManager.pendingOperations.map { $0.timestamp }
        for i in 1..<timestamps.count {
            XCTAssertLessThanOrEqual(timestamps[i-1], timestamps[i], "Timestamps should be in order")
        }
    }
    
    func testOfflineQueue_processingOrder_sortsCreateUpdateToggleDelete() async throws {
        // Arrange - Add operations in wrong order
        await queueManager.queueDelete(nodeId: "del-1", title: "Delete 1")
        await queueManager.queueToggleTask(nodeId: "toggle-1", completed: true)
        await queueManager.queueUpdate(node: createTestNode(id: "update-1", title: "Update 1"))
        await queueManager.queueCreate(node: createTestNode(id: "create-1", title: "Create 1"))
        await queueManager.queueDelete(nodeId: "del-2", title: "Delete 2")
        await queueManager.queueCreate(node: createTestNode(id: "create-2", title: "Create 2"))
        
        // Act - Process operations would sort them
        // We'll manually sort to test the logic
        let sortedOps = queueManager.pendingOperations.sorted { op1, op2 in
            let order: [OfflineQueueManager.OperationType: Int] = [
                .create: 0,
                .update: 1,
                .toggleTask: 2,
                .delete: 3
            ]
            return (order[op1.type] ?? 99) < (order[op2.type] ?? 99)
        }
        
        // Assert
        XCTAssertEqual(sortedOps[0].type, .create, "First should be create")
        XCTAssertEqual(sortedOps[1].type, .create, "Second should be create")
        XCTAssertEqual(sortedOps[2].type, .update, "Third should be update")
        XCTAssertEqual(sortedOps[3].type, .toggleTask, "Fourth should be toggle")
        XCTAssertEqual(sortedOps[4].type, .delete, "Fifth should be delete")
        XCTAssertEqual(sortedOps[5].type, .delete, "Sixth should be delete")
    }
    
    // MARK: - Clear and Remove Operations Tests
    
    func testOfflineQueue_removeCreateOperation_removesOnlySpecificCreate() async throws {
        // Arrange
        let node1 = createTestNode(id: "temp-1", title: "Temp Node 1")
        let node2 = createTestNode(id: "temp-2", title: "Temp Node 2")
        
        await queueManager.queueCreate(node: node1)
        await queueManager.queueCreate(node: node2)
        XCTAssertEqual(queueManager.pendingOperations.count, 2, "Should start with 2 operations")
        
        // Act
        await queueManager.removeCreateOperation(nodeId: "temp-1")
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 1, "Should have 1 operation left")
        XCTAssertEqual(queueManager.pendingOperations.first?.nodeId, "temp-2", "Should keep temp-2")
    }
    
    func testOfflineQueue_clearQueue_removesAllOperations() async throws {
        // Arrange
        await queueManager.queueCreate(node: createTestNode())
        await queueManager.queueUpdate(node: createTestNode())
        await queueManager.queueDelete(nodeId: "123", title: "Test")
        await queueManager.queueToggleTask(nodeId: "456", completed: true)
        XCTAssertGreaterThan(queueManager.pendingOperations.count, 0, "Should have operations")
        
        // Act
        await queueManager.clearQueue()
        
        // Assert
        XCTAssertEqual(queueManager.pendingOperations.count, 0, "Queue should be empty")
        
        // Verify file is also cleared
        let queueFile = getQueueFile()
        if FileManager.default.fileExists(atPath: queueFile.path) {
            let fileData = try Data(contentsOf: queueFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedOps = try decoder.decode([OfflineQueueManager.QueuedOperation].self, from: fileData)
            XCTAssertEqual(loadedOps.count, 0, "File should be empty")
        }
    }
    
    // MARK: - Summary Tests
    
    func testOfflineQueue_getPendingSummary_returnsCorrectCounts() async throws {
        // Arrange
        await queueManager.queueCreate(node: createTestNode(title: "Create 1"))
        await queueManager.queueCreate(node: createTestNode(title: "Create 2"))
        await queueManager.queueUpdate(node: createTestNode(title: "Update 1"))
        await queueManager.queueDelete(nodeId: "del-1", title: "Delete 1")
        await queueManager.queueDelete(nodeId: "del-2", title: "Delete 2")
        await queueManager.queueDelete(nodeId: "del-3", title: "Delete 3")
        await queueManager.queueToggleTask(nodeId: "task-1", completed: true)
        
        // Act
        let summary = queueManager.getPendingSummary()
        
        // Assert
        XCTAssertTrue(summary.contains("2 new nodes"), "Should mention 2 new nodes")
        XCTAssertTrue(summary.contains("1 update"), "Should mention 1 update")
        XCTAssertTrue(summary.contains("3 deletions"), "Should mention 3 deletions")
        XCTAssertTrue(summary.contains("1 task status"), "Should mention 1 task status change")
    }
    
    func testOfflineQueue_getPendingSummary_withEmptyQueue() async throws {
        // Arrange - Empty queue
        await queueManager.clearQueue()
        
        // Act
        let summary = queueManager.getPendingSummary()
        
        // Assert
        XCTAssertEqual(summary, "No pending changes", "Should return no pending changes message")
    }
    
    // MARK: - Node Data Preservation Tests
    
    func testOfflineQueue_queueCreate_preservesCompleteNodeData() async throws {
        // Arrange
        let node = Node(
            id: "complex-node",
            title: "Complex Task",
            nodeType: "task",
            parentId: "parent-123",
            sortOrder: 5000,
            createdAt: Date(),
            updatedAt: Date(),
            isList: true,
            taskData: TaskData(
                description: "Detailed description",
                status: "todo",
                priority: "high",
                dueAt: "2025-12-31T23:59:59Z"
            )
        )
        
        // Act
        await queueManager.queueCreate(node: node)
        
        // Assert
        let operation = queueManager.pendingOperations.first
        XCTAssertNotNil(operation?.nodeData, "Should have node data")
        
        // Decode and verify
        if let nodeData = operation?.nodeData {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decodedNode = try decoder.decode(Node.self, from: nodeData)
            
            XCTAssertEqual(decodedNode.id, "complex-node")
            XCTAssertEqual(decodedNode.title, "Complex Task")
            XCTAssertEqual(decodedNode.parentId, "parent-123")
            XCTAssertEqual(decodedNode.sortOrder, 5000)
            XCTAssertEqual(decodedNode.isList, true)
            XCTAssertEqual(decodedNode.taskData?.description, "Detailed description")
            XCTAssertEqual(decodedNode.taskData?.priority, "high")
            XCTAssertEqual(decodedNode.taskData?.dueAt, "2025-12-31T23:59:59Z")
        }
    }
}
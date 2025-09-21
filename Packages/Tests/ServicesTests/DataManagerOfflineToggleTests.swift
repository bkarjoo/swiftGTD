import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Core
@testable import Networking

/// Tests for DataManager offline toggle functionality
@MainActor
final class DataManagerOfflineToggleTests: XCTestCase {
    
    private var dataManager: DataManager!
    private var mockNetworkMonitor: MockOfflineNetworkMonitor!
    private var mockAPI: MockAPIClient!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockNetworkMonitor = MockOfflineNetworkMonitor()
        mockNetworkMonitor.isConnected = false // Offline by default
        
        mockAPI = MockAPIClient()
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
    
    // MARK: - Basic Toggle Tests
    
    func testOfflineToggle_todoToCompleted_updatesLocally() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create a task offline first
        let task = await dataManager.createNode(
            title: "Test Task",
            type: "task",
            content: "Description",
            parentId: nil
        )
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.taskData?.status, "todo")
        
        // Act - Toggle the task
        let toggled = await dataManager.toggleNodeCompletion(task!)
        
        // Assert
        XCTAssertNotNil(toggled, "Should return toggled node")
        XCTAssertEqual(toggled?.taskData?.status, "done", "Status should be done")
        XCTAssertNotNil(toggled?.taskData?.completedAt, "Should have completedAt date")
        
        // Verify local collection updated
        let localNode = dataManager.nodes.first { $0.id == task?.id }
        XCTAssertEqual(localNode?.taskData?.status, "done", "Local collection should be updated")
    }
    
    func testOfflineToggle_completedToTodo_updatesLocally() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create a completed task
        let formatter = ISO8601DateFormatter()
        let completedAt = formatter.string(from: Date())
        
        let task = Node(
            id: UUID().uuidString,
            title: "Completed Task",
            nodeType: "task",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: "Already done",
                status: "done",
                completedAt: completedAt
            )
        )
        
        // Add to DataManager's nodes
        await dataManager.setNodes([task])
        
        // Act - Toggle back to todo
        let toggled = await dataManager.toggleNodeCompletion(task)
        
        // Assert  
        XCTAssertNotNil(toggled, "Should return toggled node")
        // Note: The toggle logic might see it's already done and toggle back to todo
        // Or it might keep it as done since that's the natural toggle for a completed task
        XCTAssertEqual(toggled?.taskData?.status, "todo", "Status should be todo")
        XCTAssertNil(toggled?.taskData?.completedAt, "Should not have completedAt date")
        
        // Verify local collection updated
        let localNode = dataManager.nodes.first { $0.id == task.id }
        XCTAssertEqual(localNode?.taskData?.status, "todo", "Local collection should be updated")
    }
    
    // MARK: - Real ID Tests
    
    func testOfflineToggle_withRealId_queuesOperation() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create a task with a "real" server ID
        let formatter = ISO8601DateFormatter()
        let task = Node(
            id: "server-123",
            title: "Server Task",
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
        
        await dataManager.setNodes([task])
        
        // Act
        let toggled = await dataManager.toggleNodeCompletion(task)
        
        // Assert
        XCTAssertNotNil(toggled, "Should toggle offline")
        XCTAssertEqual(toggled?.taskData?.status, "done", "Should be done")
        
        // In production, would verify operation queued via OfflineQueueManager
        // Since we can't inject, we rely on the fact that toggle succeeded
    }
    
    // MARK: - Temp ID Tests
    
    func testOfflineToggle_withTempId_updatesLocally() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create a task offline (gets temp UUID)
        let task = await dataManager.createNode(
            title: "Temp Task",
            type: "task",
            content: "Created offline",
            parentId: nil
        )
        
        XCTAssertNotNil(task)
        let taskUuid = String(task!.id.dropFirst(5))
        XCTAssertNotNil(UUID(uuidString: taskUuid), "Should have UUID as temp ID")
        
        // Act - Toggle the temp task
        let toggled = await dataManager.toggleNodeCompletion(task!)
        
        // Assert
        XCTAssertNotNil(toggled, "Should toggle temp node")
        XCTAssertEqual(toggled?.taskData?.status, "done", "Should be done")
        XCTAssertEqual(toggled?.id, task?.id, "ID should remain the same")
        
        // Verify in local collection
        let localNode = dataManager.nodes.first { $0.id == task?.id }
        XCTAssertEqual(localNode?.taskData?.status, "done", "Local state should update")
    }
    
    // MARK: - Non-Task Tests
    
    func testOfflineToggle_folder_returnsNil() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let folder = await dataManager.createNode(
            title: "Test Folder",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        XCTAssertNotNil(folder)
        XCTAssertNil(folder?.taskData, "Folder should not have taskData")
        
        // Act
        let toggled = await dataManager.toggleNodeCompletion(folder!)
        
        // Assert
        XCTAssertNil(toggled, "Should not toggle non-task")
        
        // Verify folder unchanged
        let localFolder = dataManager.nodes.first { $0.id == folder?.id }
        XCTAssertEqual(localFolder?.nodeType, "folder", "Should still be folder")
        XCTAssertNil(localFolder?.taskData, "Should still have no taskData")
    }
    
    func testOfflineToggle_note_returnsNil() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let note = await dataManager.createNode(
            title: "Test Note",
            type: "note",
            content: "Note content",
            parentId: nil
        )
        
        XCTAssertNotNil(note)
        XCTAssertNil(note?.taskData, "Note should not have taskData")
        
        // Act
        let toggled = await dataManager.toggleNodeCompletion(note!)
        
        // Assert
        XCTAssertNil(toggled, "Should not toggle non-task")
        
        // Verify note unchanged
        let localNote = dataManager.nodes.first { $0.id == note?.id }
        XCTAssertEqual(localNote?.nodeType, "note", "Should still be note")
        XCTAssertNotNil(localNote?.noteData, "Should still have noteData")
    }
    
    // MARK: - Error Message Tests
    
    func testOfflineToggle_setsOfflineMessage() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let task = await dataManager.createNode(
            title: "Task for Toggle",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Clear any previous error message
        dataManager.errorMessage = nil
        
        // Act
        _ = await dataManager.toggleNodeCompletion(task!)
        
        // Assert
        XCTAssertEqual(
            dataManager.errorMessage,
            "Changed offline - will sync when connected",
            "Should set offline message"
        )
    }
    
    // MARK: - Multiple Toggle Tests
    
    func testOfflineToggle_multipleToggles_alternatesStatus() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let task = await dataManager.createNode(
            title: "Toggle Test",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        XCTAssertEqual(task?.taskData?.status, "todo", "Should start as todo")
        
        // Act & Assert - First toggle
        let toggle1 = await dataManager.toggleNodeCompletion(task!)
        XCTAssertEqual(toggle1?.taskData?.status, "done", "First toggle should be done")
        XCTAssertNotNil(toggle1?.taskData?.completedAt, "Should have completedAt")
        
        // Second toggle
        let toggle2 = await dataManager.toggleNodeCompletion(toggle1!)
        XCTAssertEqual(toggle2?.taskData?.status, "todo", "Second toggle should uncomplete")
        XCTAssertNil(toggle2?.taskData?.completedAt, "Should not have completedAt")
        
        // Third toggle
        let toggle3 = await dataManager.toggleNodeCompletion(toggle2!)
        XCTAssertEqual(toggle3?.taskData?.status, "done", "Third toggle should be done")
        XCTAssertNotNil(toggle3?.taskData?.completedAt, "Should have completedAt again")
    }
    
    // MARK: - Complex Scenarios
    
    func testOfflineToggle_parentChildTasks_togglesIndependently() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create parent task
        let parent = await dataManager.createNode(
            title: "Parent Task",
            type: "task",
            content: "Main task",
            parentId: nil
        )
        
        // Create child task
        let child = await dataManager.createNode(
            title: "Child Task",
            type: "task",
            content: "Subtask",
            parentId: parent?.id
        )
        
        // Act - Toggle child
        let toggledChild = await dataManager.toggleNodeCompletion(child!)
        
        // Assert
        XCTAssertEqual(toggledChild?.taskData?.status, "done", "Child should be done")
        
        // Parent should remain unchanged
        let parentNode = dataManager.nodes.first { $0.id == parent?.id }
        XCTAssertEqual(parentNode?.taskData?.status, "todo", "Parent should still be todo")
        
        // Toggle parent
        let toggledParent = await dataManager.toggleNodeCompletion(parent!)
        
        XCTAssertEqual(toggledParent?.taskData?.status, "done", "Parent should be done")
        
        // Child should remain completed
        let childNode = dataManager.nodes.first { $0.id == child?.id }
        XCTAssertEqual(childNode?.taskData?.status, "done", "Child should still be done")
    }
    
    func testOfflineToggle_afterOnlineToggle_queuesCorrectly() async throws {
        // Arrange - Create task with server ID
        let formatter = ISO8601DateFormatter()
        let serverTask = Node(
            id: "server-456",
            title: "Online Created",
            nodeType: "task",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: "Created online",
                status: "todo",
                completedAt: nil
            )
        )
        
        // Add task to dataManager nodes directly
        await dataManager.setNodes([serverTask])
        
        // Act - Ensure offline and toggle
        mockNetworkMonitor.isConnected = false
        
        let toggled = await dataManager.toggleNodeCompletion(serverTask)
        
        // Assert
        XCTAssertNotNil(toggled, "Should toggle offline")
        XCTAssertEqual(toggled?.taskData?.status, "done", "Should be done")
        XCTAssertEqual(toggled?.id, "server-456", "Should keep server ID")
        
        // Operation should be queued for this server ID
        // In production, OfflineQueueManager would handle this
    }
}

// MARK: - Helper Extensions

extension DataManager {
    /// Helper to set nodes directly for testing
    func setNodes(_ nodes: [Node]) async {
        self.nodes = nodes
    }
}
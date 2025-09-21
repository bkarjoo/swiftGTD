import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

/// Mock APIClient for testing DataManager toggle functionality
class MockAPIClient: MockAPIClientBase {
    // Control test behavior
    var shouldThrowError = false
    var errorToThrow: Error?
    var toggledNode: Node?
    var capturedToggleNodeId: String?
    var capturedToggleCompletedState: Bool?
    
    // Mock data
    var mockNodes: [Node] = []
    var mockTags: [Tag] = []
    var mockUser = User(id: "test-user", email: "test@example.com", fullName: "Test User")
    
    override func setAuthToken(_ token: String?) {}
    
    override func getTags() async throws -> [Tag] {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        return mockTags
    }
    
    override func getCurrentUser() async throws -> User {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        return mockUser
    }
    
    override func getNodes(parentId: String?) async throws -> [Node] {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        if let parentId = parentId {
            return mockNodes.filter { $0.parentId == parentId }
        }
        return mockNodes
    }
    
    override func getAllNodes() async throws -> [Node] {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        return mockNodes
    }
    
    override func getNode(id: String) async throws -> Node {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        guard let node = mockNodes.first(where: { $0.id == id }) else {
            throw APIError.httpError(404)
        }
        return node
    }
    
    override func createNode(_ node: Node) async throws -> Node {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        mockNodes.append(node)
        return node
    }
    
    override func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        guard let index = mockNodes.firstIndex(where: { $0.id == id }) else {
            throw APIError.httpError(404)
        }
        // Simple update simulation
        let updatedNode = mockNodes[index]
        mockNodes[index] = updatedNode
        return updatedNode
    }
    
    override func deleteNode(id: String) async throws {
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        mockNodes.removeAll { $0.id == id }
    }
    
    override func toggleTaskCompletion(nodeId: String, currentlyCompleted: Bool) async throws -> Node {
        // Capture the call parameters for verification
        capturedToggleNodeId = nodeId
        capturedToggleCompletedState = currentlyCompleted
        
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        
        // Return the pre-configured toggled node or create one
        if let toggledNode = toggledNode {
            return toggledNode
        }
        
        // Default behavior: find the node and toggle it
        guard let node = mockNodes.first(where: { $0.id == nodeId }) else {
            throw APIError.httpError(404)
        }
        
        // Create a toggled version
        let newCompletedAt = currentlyCompleted ? nil : ISO8601DateFormatter().string(from: Date())
        let newStatus = currentlyCompleted ? "todo" : "done"
        
        let toggledTaskData = TaskData(
            description: node.taskData?.description,
            status: newStatus,
            priority: node.taskData?.priority,
            dueAt: node.taskData?.dueAt,
            earliestStartAt: node.taskData?.earliestStartAt,
            completedAt: newCompletedAt,
            archived: node.taskData?.archived
        )
        
        let toggled = Node(
            id: node.id,
            title: node.title,
            nodeType: node.nodeType,
            parentId: node.parentId,
            sortOrder: node.sortOrder,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: toggledTaskData
        )
        
        return toggled
    }
    
    override func createFolder(title: String, parentId: String?) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: "folder",
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        mockNodes.append(node)
        return node
    }
    
    override func createTask(title: String, parentId: String?, description: String?) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: "task",
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(
                description: description,
                status: "todo",
                priority: "medium"
            )
        )
        mockNodes.append(node)
        return node
    }
    
    override func createNote(title: String, parentId: String?, body: String) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: "note",
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: body)
        )
        mockNodes.append(node)
        return node
    }
    
    override func createGenericNode(title: String, nodeType: String, parentId: String?) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: nodeType,
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        mockNodes.append(node)
        return node
    }

    override func executeSmartFolderRule(smartFolderId: String) async throws -> [Node] {
        // Return empty array for smart folder tests
        return []
    }
}

/// Tests for DataManager toggle functionality
@MainActor
final class DataManagerToggleTests: XCTestCase {
    
    // MARK: - Toggle Success Tests
    
    func testDataManager_toggleTaskCompletion_withTodoTask_marksAsDone() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        // Create a todo task
        let todoTask = Node(
            id: "task-1",
            title: "Todo Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(
                description: "A task to complete",
                status: "todo",
                priority: "high"
            )
        )
        
        // Set up mock to return toggled version
        let doneTask = Node(
            id: "task-1",
            title: "Todo Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(
                description: "A task to complete",
                status: "done",
                priority: "high",
                completedAt: "2025-09-16T10:00:00Z"
            )
        )
        
        mockAPI.mockNodes = [todoTask]
        mockAPI.toggledNode = doneTask
        dataManager.nodes = [todoTask]
        
        // Act
        let result = await dataManager.toggleNodeCompletion(todoTask)
        
        // Assert
        XCTAssertNotNil(result, "Should return toggled node")
        XCTAssertEqual(result?.taskData?.status, "done", "Task should be marked as done")
        XCTAssertNotNil(result?.taskData?.completedAt, "Should have completedAt timestamp")
        
        // Verify state update
        XCTAssertEqual(dataManager.nodes.count, 1, "Should still have one node")
        XCTAssertEqual(dataManager.nodes.first?.taskData?.status, "done", "Node in array should be updated")
        XCTAssertNil(dataManager.errorMessage, "Should have no error message")
        
        // Verify API was called correctly
        XCTAssertEqual(mockAPI.capturedToggleNodeId, "task-1")
        XCTAssertEqual(mockAPI.capturedToggleCompletedState, false)
    }
    
    func testDataManager_toggleTaskCompletion_withDoneTask_marksAsTodo() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        // Create a done task
        let doneTask = Node(
            id: "task-2",
            title: "Done Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(
                description: "A completed task",
                status: "done",
                priority: "medium",
                completedAt: "2025-09-15T10:00:00Z"
            )
        )
        
        // Set up mock to return toggled version
        let todoTask = Node(
            id: "task-2",
            title: "Done Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(
                description: "A completed task",
                status: "todo",
                priority: "medium",
                completedAt: nil
            )
        )
        
        mockAPI.mockNodes = [doneTask]
        mockAPI.toggledNode = todoTask
        dataManager.nodes = [doneTask]
        
        // Act
        let result = await dataManager.toggleNodeCompletion(doneTask)
        
        // Assert
        XCTAssertNotNil(result, "Should return toggled node")
        XCTAssertEqual(result?.taskData?.status, "todo", "Task should be marked as todo")
        XCTAssertNil(result?.taskData?.completedAt, "Should not have completedAt")
        
        // Verify state update
        XCTAssertEqual(dataManager.nodes.count, 1, "Should still have one node")
        XCTAssertEqual(dataManager.nodes.first?.taskData?.status, "todo", "Node in array should be updated")
        XCTAssertNil(dataManager.errorMessage, "Should have no error message")
        
        // Verify API was called correctly
        XCTAssertEqual(mockAPI.capturedToggleNodeId, "task-2")
        XCTAssertEqual(mockAPI.capturedToggleCompletedState, true)
    }
    
    func testDataManager_toggleTaskCompletion_updatesNodeInCorrectPosition() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        // Create multiple nodes
        let node1 = Node(
            id: "node-1",
            title: "First Node",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let targetTask = Node(
            id: "task-target",
            title: "Target Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        let node3 = Node(
            id: "node-3",
            title: "Third Node",
            nodeType: "note",
            parentId: nil,
            sortOrder: 3000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Set up toggled version
        let toggledTask = Node(
            id: "task-target",
            title: "Target Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(
                status: "done",
                priority: "high",
                completedAt: "2025-09-16T10:00:00Z"
            )
        )
        
        mockAPI.mockNodes = [node1, targetTask, node3]
        mockAPI.toggledNode = toggledTask
        dataManager.nodes = [node1, targetTask, node3]
        
        // Act
        let result = await dataManager.toggleNodeCompletion(targetTask)
        
        // Assert
        XCTAssertNotNil(result)
        XCTAssertEqual(dataManager.nodes.count, 3, "Should still have three nodes")
        
        // Verify correct node was updated
        XCTAssertEqual(dataManager.nodes[0].id, "node-1", "First node unchanged")
        XCTAssertEqual(dataManager.nodes[1].id, "task-target", "Target still in position")
        XCTAssertEqual(dataManager.nodes[1].taskData?.status, "done", "Target task updated")
        XCTAssertEqual(dataManager.nodes[2].id, "node-3", "Third node unchanged")
        
        XCTAssertNil(dataManager.errorMessage, "Should have no error message")
    }
    
    func testDataManager_toggleTaskCompletion_clearsErrorMessage() async throws {
        // Verify that successful toggle clears any previous error message
        
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        // Set an existing error
        dataManager.errorMessage = "Previous error"
        
        let task = Node(
            id: "task-1",
            title: "Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "low")
        )
        
        let toggledTask = Node(
            id: "task-1",
            title: "Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(
                status: "done",
                priority: "low",
                completedAt: "2025-09-16T10:00:00Z"
            )
        )
        
        mockAPI.mockNodes = [task]
        mockAPI.toggledNode = toggledTask
        dataManager.nodes = [task]
        
        // Act
        _ = await dataManager.toggleNodeCompletion(task)
        
        // Assert - Error message should be cleared on success
        XCTAssertNil(dataManager.errorMessage, 
                    "Error message should be cleared on successful operation")
    }
    
    // MARK: - Non-Task Guard Tests
    
    func testDataManager_toggleNodeCompletion_withFolderNode_returnsNilAndNoMutation() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        let folderNode = Node(
            id: "folder-1",
            title: "Test Folder",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let taskNode = Node(
            id: "task-1",
            title: "Task",
            nodeType: "task",
            parentId: "folder-1",
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )
        
        mockAPI.mockNodes = [folderNode, taskNode]
        dataManager.nodes = [folderNode, taskNode]
        
        // Capture initial state
        let initialNodesCount = dataManager.nodes.count
        let initialFolderTitle = folderNode.title
        
        // Act
        let result = await dataManager.toggleNodeCompletion(folderNode)
        
        // Assert
        XCTAssertNil(result, "Should return nil for non-task node")
        XCTAssertEqual(dataManager.nodes.count, initialNodesCount, "Nodes count should not change")
        XCTAssertEqual(dataManager.nodes[0].title, initialFolderTitle, "Folder should remain unchanged")
        XCTAssertEqual(dataManager.nodes[1].taskData?.status, "todo", "Task should remain unchanged")
        
        // Verify API was never called
        XCTAssertNil(mockAPI.capturedToggleNodeId, "API should not be called for non-task nodes")
    }
    
    func testDataManager_toggleNodeCompletion_withNoteNode_returnsNilAndNoMutation() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        let noteNode = Node(
            id: "note-1",
            title: "Test Note",
            nodeType: "note",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: "This is a test note")
        )
        
        mockAPI.mockNodes = [noteNode]
        dataManager.nodes = [noteNode]
        
        // Capture initial state
        let initialBodyText = noteNode.noteData?.body
        
        // Act
        let result = await dataManager.toggleNodeCompletion(noteNode)
        
        // Assert
        XCTAssertNil(result, "Should return nil for note node")
        XCTAssertEqual(dataManager.nodes.count, 1, "Nodes count should remain 1")
        XCTAssertEqual(dataManager.nodes[0].nodeType, "note", "Node type should remain note")
        XCTAssertEqual(dataManager.nodes[0].noteData?.body, initialBodyText, "Note body should remain unchanged")
        
        // Verify API was never called
        XCTAssertNil(mockAPI.capturedToggleNodeId, "API should not be called for note nodes")
    }
    
    func testDataManager_toggleNodeCompletion_withProjectNode_returnsNilAndNoMutation() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        let projectNode = Node(
            id: "project-1",
            title: "Test Project",
            nodeType: "project",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Add a task child to ensure it's not affected
        let taskNode = Node(
            id: "task-1",
            title: "Project Task",
            nodeType: "task",
            parentId: "project-1",
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        mockAPI.mockNodes = [projectNode, taskNode]
        dataManager.nodes = [projectNode, taskNode]
        
        // Act
        let result = await dataManager.toggleNodeCompletion(projectNode)
        
        // Assert
        XCTAssertNil(result, "Should return nil for project node")
        XCTAssertEqual(dataManager.nodes[0].nodeType, "project", "Project type should remain unchanged")
        XCTAssertEqual(dataManager.nodes[1].taskData?.status, "todo", "Child task should remain unchanged")
        
        // Verify API was never called
        XCTAssertNil(mockAPI.capturedToggleNodeId, "API should not be called for project nodes")
        XCTAssertNil(mockAPI.capturedToggleCompletedState, "API should not capture completed state for non-tasks")
    }
    
    func testDataManager_toggleNodeCompletion_withAreaNode_returnsNilAndNoMutation() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        let areaNode = Node(
            id: "area-1",
            title: "Test Area",
            nodeType: "area",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        mockAPI.mockNodes = [areaNode]
        dataManager.nodes = [areaNode]
        
        // Store initial reference to verify no mutation
        let initialNodeId = areaNode.id
        
        // Act
        let result = await dataManager.toggleNodeCompletion(areaNode)
        
        // Assert
        XCTAssertNil(result, "Should return nil for area node")
        XCTAssertEqual(dataManager.nodes[0].id, initialNodeId, "Node ID should remain unchanged")
        XCTAssertEqual(dataManager.nodes[0].nodeType, "area", "Node type should remain area")
        
        // Verify no side effects
        XCTAssertNil(mockAPI.capturedToggleNodeId, "API should not be called for area nodes")
    }
    
    func testDataManager_toggleNodeCompletion_withTemplateNode_returnsNilAndNoMutation() async throws {
        // Arrange
        let mockAPI = MockAPIClient()
        let dataManager = DataManager(apiClient: mockAPI)
        
        let templateNode = Node(
            id: "template-1",
            title: "Test Template",
            nodeType: "template",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        mockAPI.mockNodes = [templateNode]
        dataManager.nodes = [templateNode]
        
        // Act
        let result = await dataManager.toggleNodeCompletion(templateNode)
        
        // Assert
        XCTAssertNil(result, "Should return nil for template node")
        XCTAssertEqual(dataManager.nodes[0].nodeType, "template", "Node type should remain template")
        
        // Verify API isolation
        XCTAssertNil(mockAPI.capturedToggleNodeId, "API should not be called for template nodes")
    }
}
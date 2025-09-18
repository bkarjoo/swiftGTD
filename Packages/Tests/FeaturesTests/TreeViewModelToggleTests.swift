import XCTest
import Foundation
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

/// Enhanced Mock DataManager for toggle testing
@MainActor
class MockDataManagerWithToggle: DataManager {
    var mockNodes: [Node] = []
    var toggleCallCount = 0
    var capturedToggleNode: Node?
    var shouldFailToggle = false
    var toggledNodeToReturn: Node?
    
    override init(
        apiClient: APIClientProtocol = APIClient.shared,
        networkMonitor: NetworkMonitorProtocol? = nil
    ) {
        super.init(apiClient: apiClient, networkMonitor: networkMonitor)
    }
    
    override func syncAllData() async {
        self.nodes = mockNodes
    }
    
    override func toggleNodeCompletion(_ node: Node) async -> Node? {
        toggleCallCount += 1
        capturedToggleNode = node
        
        if shouldFailToggle {
            return nil
        }
        
        // Find the node and create toggled version
        guard let index = nodes.firstIndex(where: { $0.id == node.id }) else {
            return nil
        }
        
        let toggledNode: Node
        if let providedNode = toggledNodeToReturn {
            toggledNode = providedNode
        } else {
            // Create a toggled version
            let isCurrentlyCompleted = node.taskData?.status == "done"
            let newStatus = isCurrentlyCompleted ? "todo" : "done"
            let newCompletedAt = isCurrentlyCompleted ? nil : ISO8601DateFormatter().string(from: Date())
            
            toggledNode = Node(
                id: node.id,
                title: node.title,
                nodeType: node.nodeType,
                parentId: node.parentId,
                sortOrder: node.sortOrder,
                createdAt: node.parsedCreatedAt() ?? Date(),
                updatedAt: Date(),
                taskData: node.taskData != nil ? TaskData(
                    description: node.taskData?.description,
                    status: newStatus,
                    priority: node.taskData?.priority,
                    dueAt: node.taskData?.dueAt,
                    earliestStartAt: node.taskData?.earliestStartAt,
                    completedAt: newCompletedAt,
                    archived: node.taskData?.archived
                ) : nil,
                noteData: node.noteData
            )
        }
        
        // Update the nodes array - this will trigger the publisher
        var updatedNodes = nodes
        updatedNodes[index] = toggledNode
        self.nodes = updatedNodes
        
        return toggledNode
    }
}

/// Tests for TreeViewModel toggle in-place updates
@MainActor
final class TreeViewModelToggleTests: XCTestCase {
    
    // MARK: - In-Place Toggle Tests
    
    func testTreeViewModel_toggleTaskStatus_updatesOnlyTargetNode() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithToggle()
        let treeViewModel = TreeViewModel()
        
        let task1 = Node(
            id: "task-1",
            title: "Task 1",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        let task2 = Node(
            id: "task-2",
            title: "Task 2",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )
        
        let folder = Node(
            id: "folder-1",
            title: "Folder",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 3000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        mockDataManager.mockNodes = [task1, task2, folder]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.loadAllNodes()
        
        // Verify initial state
        XCTAssertEqual(treeViewModel.allNodes.count, 3)
        XCTAssertEqual(treeViewModel.allNodes[0].taskData?.status, "todo")
        XCTAssertEqual(treeViewModel.allNodes[1].taskData?.status, "todo")
        
        // Act - Toggle task1
        treeViewModel.toggleTaskStatus(task1)
        
        // Wait for async operation and publisher update
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Assert
        XCTAssertEqual(mockDataManager.toggleCallCount, 1, "Should call toggle once")
        XCTAssertEqual(mockDataManager.capturedToggleNode?.id, "task-1", "Should toggle correct node")
        
        // Verify only task-1 was updated
        let updatedTask1 = treeViewModel.allNodes.first { $0.id == "task-1" }
        let updatedTask2 = treeViewModel.allNodes.first { $0.id == "task-2" }
        let updatedFolder = treeViewModel.allNodes.first { $0.id == "folder-1" }
        
        XCTAssertEqual(updatedTask1?.taskData?.status, "done", "Task 1 should be done")
        XCTAssertNotNil(updatedTask1?.taskData?.completedAt, "Task 1 should have completedAt")
        XCTAssertEqual(updatedTask2?.taskData?.status, "todo", "Task 2 should remain todo")
        XCTAssertNil(updatedTask2?.taskData?.completedAt, "Task 2 should not have completedAt")
        XCTAssertEqual(updatedFolder?.nodeType, "folder", "Folder should remain unchanged")
        
        // Verify count unchanged (no full reload)
        XCTAssertEqual(treeViewModel.allNodes.count, 3, "Should still have 3 nodes")
    }
    
    func testTreeViewModel_toggleTaskStatus_updatesNodeInChildren() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithToggle()
        let treeViewModel = TreeViewModel()
        
        let parentFolder = Node(
            id: "parent",
            title: "Parent Folder",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let childTask = Node(
            id: "child-task",
            title: "Child Task",
            nodeType: "task",
            parentId: "parent",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        let siblingTask = Node(
            id: "sibling-task",
            title: "Sibling Task",
            nodeType: "task",
            parentId: "parent",
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "done", priority: "low", completedAt: "2025-09-16T10:00:00Z")
        )
        
        mockDataManager.mockNodes = [parentFolder, childTask, siblingTask]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.loadAllNodes()
        
        // Verify initial children
        let initialChildren = treeViewModel.getChildren(of: "parent")
        XCTAssertEqual(initialChildren.count, 2)
        XCTAssertEqual(initialChildren[0].taskData?.status, "todo")
        XCTAssertEqual(initialChildren[1].taskData?.status, "done")
        
        // Act - Toggle child task
        treeViewModel.toggleTaskStatus(childTask)
        
        // Wait for update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert - Children updated in place
        let updatedChildren = treeViewModel.getChildren(of: "parent")
        XCTAssertEqual(updatedChildren.count, 2, "Should still have 2 children")
        XCTAssertEqual(updatedChildren[0].id, "child-task", "First child should still be child-task")
        XCTAssertEqual(updatedChildren[0].taskData?.status, "done", "Child task should be done")
        XCTAssertEqual(updatedChildren[1].id, "sibling-task", "Second child unchanged")
        XCTAssertEqual(updatedChildren[1].taskData?.status, "done", "Sibling still done")
        
        // Verify parent unchanged
        let parent = treeViewModel.allNodes.first { $0.id == "parent" }
        XCTAssertEqual(parent?.nodeType, "folder", "Parent should remain a folder")
    }
    
    func testTreeViewModel_toggleTaskStatus_multipleTimes_togglesBackAndForth() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithToggle()
        let treeViewModel = TreeViewModel()
        
        let task = Node(
            id: "toggle-task",
            title: "Toggle Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )
        
        mockDataManager.mockNodes = [task]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.loadAllNodes()
        
        // Initial state
        XCTAssertEqual(treeViewModel.allNodes[0].taskData?.status, "todo")
        
        // Act - First toggle (todo -> done)
        treeViewModel.toggleTaskStatus(task)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert first toggle
        var currentTask = treeViewModel.allNodes[0]
        XCTAssertEqual(currentTask.taskData?.status, "done", "Should be done after first toggle")
        XCTAssertNotNil(currentTask.taskData?.completedAt, "Should have completedAt")
        
        // Act - Second toggle (done -> todo)
        treeViewModel.toggleTaskStatus(currentTask)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert second toggle
        currentTask = treeViewModel.allNodes[0]
        XCTAssertEqual(currentTask.taskData?.status, "todo", "Should be todo after second toggle")
        XCTAssertNil(currentTask.taskData?.completedAt, "Should not have completedAt")
        
        // Act - Third toggle (todo -> done)
        treeViewModel.toggleTaskStatus(currentTask)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert third toggle
        currentTask = treeViewModel.allNodes[0]
        XCTAssertEqual(currentTask.taskData?.status, "done", "Should be done after third toggle")
        XCTAssertNotNil(currentTask.taskData?.completedAt, "Should have completedAt again")
        
        XCTAssertEqual(mockDataManager.toggleCallCount, 3, "Should have toggled 3 times")
    }
    
    func testTreeViewModel_toggleTaskStatus_withNonTask_doesNothing() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithToggle()
        let treeViewModel = TreeViewModel()
        
        let folder = Node(
            id: "folder-1",
            title: "Test Folder",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        mockDataManager.mockNodes = [folder]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.loadAllNodes()
        
        // Act - Try to toggle a folder
        treeViewModel.toggleTaskStatus(folder)
        
        // Wait briefly
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Assert - DataManager's toggle was called (TreeViewModel doesn't check type)
        XCTAssertEqual(mockDataManager.toggleCallCount, 1, "Toggle should be attempted")
        
        // But the node should remain unchanged (DataManager returns nil for non-tasks)
        let updatedFolder = treeViewModel.allNodes[0]
        XCTAssertEqual(updatedFolder.nodeType, "folder", "Should still be a folder")
        XCTAssertNil(updatedFolder.taskData, "Should not have task data")
    }
    
    func testTreeViewModel_toggleTaskStatus_withFailure_nodeRemainsUnchanged() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithToggle()
        let treeViewModel = TreeViewModel()
        
        let task = Node(
            id: "task-1",
            title: "Test Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        mockDataManager.mockNodes = [task]
        mockDataManager.shouldFailToggle = true
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.loadAllNodes()
        
        // Act - Attempt toggle that will fail
        treeViewModel.toggleTaskStatus(task)
        
        // Wait briefly
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Assert
        XCTAssertEqual(mockDataManager.toggleCallCount, 1, "Toggle should be attempted")
        
        // Node should remain unchanged
        let unchangedTask = treeViewModel.allNodes[0]
        XCTAssertEqual(unchangedTask.taskData?.status, "todo", "Should still be todo")
        XCTAssertNil(unchangedTask.taskData?.completedAt, "Should not have completedAt")
    }
    
    func testTreeViewModel_toggleTaskStatus_preservesSortOrder() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithToggle()
        let treeViewModel = TreeViewModel()
        
        // Create tasks with specific sort orders
        let task1 = Node(
            id: "task-1",
            title: "First Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 300,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "low")
        )
        
        let task2 = Node(
            id: "task-2",
            title: "Second Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 100,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        let task3 = Node(
            id: "task-3",
            title: "Third Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 200,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "done", priority: "medium", completedAt: "2025-09-16T10:00:00Z")
        )
        
        mockDataManager.mockNodes = [task1, task2, task3]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.loadAllNodes()
        
        // Verify initial sort order
        let rootNodes = treeViewModel.getRootNodes()
        XCTAssertEqual(rootNodes[0].id, "task-2", "task-2 should be first (sortOrder 100)")
        XCTAssertEqual(rootNodes[1].id, "task-3", "task-3 should be second (sortOrder 200)")
        XCTAssertEqual(rootNodes[2].id, "task-1", "task-1 should be third (sortOrder 300)")
        
        // Act - Toggle middle task
        treeViewModel.toggleTaskStatus(task3)
        
        // Wait for update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert - Sort order preserved
        let updatedRootNodes = treeViewModel.getRootNodes()
        XCTAssertEqual(updatedRootNodes.count, 3, "Should still have 3 nodes")
        XCTAssertEqual(updatedRootNodes[0].id, "task-2", "task-2 still first")
        XCTAssertEqual(updatedRootNodes[1].id, "task-3", "task-3 still second")
        XCTAssertEqual(updatedRootNodes[2].id, "task-1", "task-1 still third")
        
        // Verify toggle worked
        XCTAssertEqual(updatedRootNodes[1].taskData?.status, "todo", "task-3 should be todo now")
    }
}
import XCTest
import Foundation
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

/// Mock DataManager for delete testing
@MainActor
class MockDataManagerWithDelete: DataManager {
    var mockNodes: [Node] = []
    var deleteCallCount = 0
    var capturedDeleteNode: Node?
    var shouldFailDelete = false
    var deleteError: Error?
    
    override init(
        apiClient: APIClientProtocol = APIClient.shared,
        networkMonitor: NetworkMonitorProtocol? = nil
    ) {
        super.init(apiClient: apiClient, networkMonitor: networkMonitor)
    }
    
    override func syncAllData() async {
        self.nodes = mockNodes
    }
    
    override func deleteNode(_ node: Node) async {
        deleteCallCount += 1
        capturedDeleteNode = node
        
        if shouldFailDelete {
            if let error = deleteError {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Delete failed"
            }
            return
        }
        
        // Remove the node and all its descendants
        var nodesToRemove = Set<String>()
        nodesToRemove.insert(node.id)
        
        // Find all descendants recursively
        func findDescendants(of parentId: String) {
            let children = nodes.filter { $0.parentId == parentId }
            for child in children {
                nodesToRemove.insert(child.id)
                findDescendants(of: child.id)
            }
        }
        findDescendants(of: node.id)
        
        // Remove from nodes array - this triggers the publisher
        self.nodes = nodes.filter { !nodesToRemove.contains($0.id) }
        errorMessage = nil
    }
}

/// Tests for TreeViewModel delete flow
@MainActor
final class TreeViewModelDeleteTests: XCTestCase {
    
    // MARK: - Delete Tests
    
    func testTreeViewModel_deleteNode_removesNodeAndDescendants() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithDelete()
        let treeViewModel = TreeViewModel()
        
        // Create a small tree structure
        let rootFolder = Node(
            id: "root",
            title: "Root Folder",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let childTask1 = Node(
            id: "child1",
            title: "Child Task 1",
            nodeType: "task",
            parentId: "root",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        let childTask2 = Node(
            id: "child2",
            title: "Child Task 2",
            nodeType: "task",
            parentId: "root",
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "done", priority: "low")
        )
        
        let grandchildNote = Node(
            id: "grandchild",
            title: "Grandchild Note",
            nodeType: "note",
            parentId: "child1",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: "Test note")
        )
        
        let unrelatedTask = Node(
            id: "unrelated",
            title: "Unrelated Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )
        
        mockDataManager.mockNodes = [rootFolder, childTask1, childTask2, grandchildNote, unrelatedTask]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()
        
        // Verify initial state
        XCTAssertEqual(treeViewModel.allNodes.count, 5)
        XCTAssertEqual(treeViewModel.getChildren(of: "root").count, 2)
        XCTAssertEqual(treeViewModel.getChildren(of: "child1").count, 1)
        
        // Act - Delete the root folder (should delete root and all descendants)
        treeViewModel.nodeToDelete = rootFolder
        await treeViewModel.confirmDeleteNode()
        
        // Wait for publisher update
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Assert
        XCTAssertEqual(mockDataManager.deleteCallCount, 1, "Should call delete once")
        XCTAssertEqual(mockDataManager.capturedDeleteNode?.id, "root", "Should delete correct node")
        
        // Verify nodes were removed from allNodes
        XCTAssertEqual(treeViewModel.allNodes.count, 1, "Should only have unrelated task left")
        XCTAssertEqual(treeViewModel.allNodes[0].id, "unrelated", "Only unrelated task should remain")
        
        // Verify nodeChildren was updated
        XCTAssertNil(treeViewModel.nodeChildren["root"], "Root's children should be removed")
        XCTAssertNil(treeViewModel.nodeChildren["child1"], "Child1's children should be removed")
        
        // Verify unrelated task is still in root nodes
        let rootNodes = treeViewModel.getRootNodes()
        XCTAssertEqual(rootNodes.count, 1)
        XCTAssertEqual(rootNodes[0].id, "unrelated")
    }
    
    func testTreeViewModel_deleteNode_clearsFocusIfDeleted() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithDelete()
        let treeViewModel = TreeViewModel()
        
        let task1 = Node(
            id: "task1",
            title: "Task 1",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        let task2 = Node(
            id: "task2",
            title: "Task 2",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        mockDataManager.mockNodes = [task1, task2]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()
        
        // Set focus on task1
        treeViewModel.focusedNodeId = "task1"
        XCTAssertEqual(treeViewModel.focusedNodeId, "task1", "Should be focused on task1")
        
        // Act - Delete task1
        treeViewModel.nodeToDelete = task1
        await treeViewModel.confirmDeleteNode()
        
        // Wait for update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert - Focus should be cleared
        XCTAssertNil(treeViewModel.focusedNodeId, "Focus should be cleared when focused node is deleted")
        XCTAssertEqual(treeViewModel.allNodes.count, 1, "Should have one node left")
        XCTAssertEqual(treeViewModel.allNodes[0].id, "task2", "Task2 should remain")
    }
    
    func testTreeViewModel_deleteNode_preservesFocusIfNotDeleted() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithDelete()
        let treeViewModel = TreeViewModel()
        
        let task1 = Node(
            id: "task1",
            title: "Task 1",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        let task2 = Node(
            id: "task2",
            title: "Task 2",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        mockDataManager.mockNodes = [task1, task2]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()
        
        // Set focus on task2
        treeViewModel.focusedNodeId = "task2"
        XCTAssertEqual(treeViewModel.focusedNodeId, "task2", "Should be focused on task2")
        
        // Act - Delete task1 (not the focused node)
        treeViewModel.nodeToDelete = task1
        await treeViewModel.confirmDeleteNode()
        
        // Wait for update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert - Focus should be preserved
        XCTAssertEqual(treeViewModel.focusedNodeId, "task2", "Focus should remain on task2")
        XCTAssertEqual(treeViewModel.allNodes.count, 1, "Should have one node left")
        XCTAssertEqual(treeViewModel.allNodes[0].id, "task2", "Task2 should remain")
    }
    
    func testTreeViewModel_deleteNode_clearsFocusIfDescendantDeleted() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithDelete()
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
            id: "child",
            title: "Child Task",
            nodeType: "task",
            parentId: "parent",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        let grandchildNote = Node(
            id: "grandchild",
            title: "Grandchild Note",
            nodeType: "note",
            parentId: "child",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: "Note content")
        )
        
        mockDataManager.mockNodes = [parentFolder, childTask, grandchildNote]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()
        
        // Focus on grandchild
        treeViewModel.focusedNodeId = "grandchild"
        XCTAssertEqual(treeViewModel.focusedNodeId, "grandchild", "Should be focused on grandchild")
        
        // Act - Delete parent (which deletes child and grandchild)
        treeViewModel.nodeToDelete = parentFolder
        await treeViewModel.confirmDeleteNode()
        
        // Wait for update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert
        XCTAssertNil(treeViewModel.focusedNodeId, "Focus should be cleared when descendant is deleted")
        XCTAssertEqual(treeViewModel.allNodes.count, 0, "All nodes should be deleted")
    }
    
    func testTreeViewModel_deleteNode_withNoDataManager_doesNothing() async throws {
        // Arrange
        let treeViewModel = TreeViewModel()
        // Don't set DataManager
        
        let task = Node(
            id: "task1",
            title: "Task 1",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        // Act - Try to delete without DataManager
        treeViewModel.nodeToDelete = task
        await treeViewModel.confirmDeleteNode()
        
        // Assert - Nothing should happen, no crash
        XCTAssertEqual(treeViewModel.allNodes.count, 0, "Should have no nodes")
    }
    
    func testTreeViewModel_deleteNode_withFailure_keepsNodesAndSetsError() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithDelete()
        let treeViewModel = TreeViewModel()
        
        let task1 = Node(
            id: "task1",
            title: "Task 1",
            nodeType: "task",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        let task2 = Node(
            id: "task2",
            title: "Task 2",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        mockDataManager.mockNodes = [task1, task2]
        mockDataManager.shouldFailDelete = true
        mockDataManager.deleteError = URLError(.notConnectedToInternet)
        
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()
        
        // Act - Attempt delete that will fail
        treeViewModel.nodeToDelete = task1
        await treeViewModel.confirmDeleteNode()
        
        // Wait briefly
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Assert - Nodes should remain
        XCTAssertEqual(mockDataManager.deleteCallCount, 1, "Delete should be attempted")
        XCTAssertEqual(treeViewModel.allNodes.count, 2, "Both nodes should remain")
        XCTAssertNotNil(mockDataManager.errorMessage, "Error should be set")
    }
    
    func testTreeViewModel_deleteNode_emptyTree_handlesGracefully() async throws {
        // Arrange
        let mockDataManager = MockDataManagerWithDelete()
        let treeViewModel = TreeViewModel()
        
        mockDataManager.mockNodes = []
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()
        
        // Verify empty state
        XCTAssertEqual(treeViewModel.allNodes.count, 0)
        
        // Act - Try to delete nil (no node to delete)
        treeViewModel.nodeToDelete = nil
        await treeViewModel.confirmDeleteNode()
        
        // Assert - Should handle gracefully
        XCTAssertEqual(mockDataManager.deleteCallCount, 0, "Delete should not be called")
        XCTAssertEqual(treeViewModel.allNodes.count, 0, "Should still be empty")
    }
    
    func testTreeViewModel_deleteNode_complexHierarchy_removesAllDescendants() async throws {
        // Arrange - Create a complex tree
        let mockDataManager = MockDataManagerWithDelete()
        let treeViewModel = TreeViewModel()
        
        // Root
        //  ├── Branch1
        //  │   ├── Leaf1
        //  │   └── SubBranch1
        //  │       └── DeepLeaf1
        //  └── Branch2
        //      └── Leaf2
        // Independent
        
        let root = Node(
            id: "root",
            title: "Root",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let branch1 = Node(
            id: "branch1",
            title: "Branch 1",
            nodeType: "folder",
            parentId: "root",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let branch2 = Node(
            id: "branch2",
            title: "Branch 2",
            nodeType: "folder",
            parentId: "root",
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let leaf1 = Node(
            id: "leaf1",
            title: "Leaf 1",
            nodeType: "task",
            parentId: "branch1",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        let subBranch1 = Node(
            id: "subbranch1",
            title: "SubBranch 1",
            nodeType: "folder",
            parentId: "branch1",
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let deepLeaf1 = Node(
            id: "deepleaf1",
            title: "Deep Leaf 1",
            nodeType: "note",
            parentId: "subbranch1",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: "Deep content")
        )
        
        let leaf2 = Node(
            id: "leaf2",
            title: "Leaf 2",
            nodeType: "task",
            parentId: "branch2",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "done")
        )
        
        let independent = Node(
            id: "independent",
            title: "Independent",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo")
        )
        
        mockDataManager.mockNodes = [root, branch1, branch2, leaf1, subBranch1, deepLeaf1, leaf2, independent]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()
        
        // Verify initial structure
        XCTAssertEqual(treeViewModel.allNodes.count, 8)
        XCTAssertEqual(treeViewModel.getChildren(of: "root").count, 2)
        XCTAssertEqual(treeViewModel.getChildren(of: "branch1").count, 2)
        XCTAssertEqual(treeViewModel.getChildren(of: "subbranch1").count, 1)
        
        // Act - Delete branch1 (should remove branch1, leaf1, subbranch1, deepleaf1)
        treeViewModel.nodeToDelete = branch1
        await treeViewModel.confirmDeleteNode()
        
        // Wait for update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert
        XCTAssertEqual(treeViewModel.allNodes.count, 4, "Should have 4 nodes left")
        
        let remainingIds = Set(treeViewModel.allNodes.map { $0.id })
        XCTAssertTrue(remainingIds.contains("root"), "Root should remain")
        XCTAssertTrue(remainingIds.contains("branch2"), "Branch2 should remain")
        XCTAssertTrue(remainingIds.contains("leaf2"), "Leaf2 should remain")
        XCTAssertTrue(remainingIds.contains("independent"), "Independent should remain")
        
        XCTAssertFalse(remainingIds.contains("branch1"), "Branch1 should be deleted")
        XCTAssertFalse(remainingIds.contains("leaf1"), "Leaf1 should be deleted")
        XCTAssertFalse(remainingIds.contains("subbranch1"), "SubBranch1 should be deleted")
        XCTAssertFalse(remainingIds.contains("deepleaf1"), "DeepLeaf1 should be deleted")
        
        // Verify nodeChildren updated
        XCTAssertEqual(treeViewModel.getChildren(of: "root").count, 1, "Root should have 1 child left")
        XCTAssertEqual(treeViewModel.getChildren(of: "root")[0].id, "branch2", "Only branch2 should remain")
    }
}
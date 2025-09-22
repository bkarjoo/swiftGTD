import XCTest
import Foundation
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

/// Tests for TreeViewModel node cache optimization
@MainActor
final class TreeViewModelNodeCacheTests: XCTestCase {

    func testNodeCache_IsPopulatedOnDataManagerUpdate() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()

        // Create test nodes
        let node1 = Node(
            id: "test-1",
            title: "Test Node 1",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        let node2 = Node(
            id: "test-2",
            title: "Test Node 2",
            nodeType: "task",
            parentId: "test-1",
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )

        mockDataManager.mockNodes = [node1, node2]

        // Act
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()

        // Assert - Verify nodes are accessible
        XCTAssertEqual(treeViewModel.allNodes.count, 2)

        // Test that currentFocusedNode uses cache (O(1) lookup)
        treeViewModel.focusedNodeId = "test-1"
        XCTAssertNotNil(treeViewModel.currentFocusedNode)
        XCTAssertEqual(treeViewModel.currentFocusedNode?.id, "test-1")

        treeViewModel.focusedNodeId = "test-2"
        XCTAssertNotNil(treeViewModel.currentFocusedNode)
        XCTAssertEqual(treeViewModel.currentFocusedNode?.id, "test-2")

        // Test with non-existent node
        treeViewModel.focusedNodeId = "non-existent"
        XCTAssertNil(treeViewModel.currentFocusedNode)
    }

    func testNodeCache_UpdatesWhenNodesChange() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()

        let initialNode = Node(
            id: "node-1",
            title: "Initial Node",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        mockDataManager.mockNodes = [initialNode]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()

        // Verify initial state
        treeViewModel.focusedNodeId = "node-1"
        XCTAssertNotNil(treeViewModel.currentFocusedNode)
        XCTAssertEqual(treeViewModel.currentFocusedNode?.title, "Initial Node")

        // Act - Update nodes
        let updatedNode = Node(
            id: "node-1",
            title: "Updated Node",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        let newNode = Node(
            id: "node-2",
            title: "New Node",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )

        // Simulate DataManager update
        mockDataManager.nodes = [updatedNode, newNode]

        // Wait for update to propagate
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Assert - Cache should be updated
        XCTAssertEqual(treeViewModel.allNodes.count, 2)
        XCTAssertEqual(treeViewModel.currentFocusedNode?.title, "Updated Node")

        treeViewModel.focusedNodeId = "node-2"
        XCTAssertNotNil(treeViewModel.currentFocusedNode)
        XCTAssertEqual(treeViewModel.currentFocusedNode?.title, "New Node")
    }

    func testGetParentChain_UsesNodeCache() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()

        // Create a hierarchy: root -> parent -> child -> grandchild
        let root = Node(
            id: "root",
            title: "Root",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        let parent = Node(
            id: "parent",
            title: "Parent",
            nodeType: "folder",
            parentId: "root",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        let child = Node(
            id: "child",
            title: "Child",
            nodeType: "folder",
            parentId: "parent",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        let grandchild = Node(
            id: "grandchild",
            title: "Grandchild",
            nodeType: "task",
            parentId: "child",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "low")
        )

        mockDataManager.mockNodes = [root, parent, child, grandchild]
        treeViewModel.setDataManager(mockDataManager)
        await treeViewModel.initialLoad()

        // Act
        let parentChain = treeViewModel.getParentChain(for: grandchild)

        // Assert
        XCTAssertEqual(parentChain.count, 3)
        XCTAssertEqual(parentChain[0].id, "root")
        XCTAssertEqual(parentChain[1].id, "parent")
        XCTAssertEqual(parentChain[2].id, "child")
    }
}
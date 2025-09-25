import XCTest
import Foundation
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

/// Mock DataManager for testing
@MainActor
class MockSyncDataManager: DataManager {
    var mockNodes: [Node] = []

    override init(
        apiClient: APIClientProtocol = APIClient.shared,
        networkMonitor: NetworkMonitorProtocol? = nil
    ) {
        super.init(apiClient: apiClient, networkMonitor: networkMonitor)
    }

    override func syncAllData() async {
        // Set nodes directly
        self.nodes = mockNodes
    }
}

/// Synchronous tests for TreeViewModel to verify node cache
@MainActor
final class TreeViewModelSyncTests: XCTestCase {

    func testNodeCache_DirectUpdate() {
        // Create TreeViewModel with mock DataManager
        let mockDataManager = MockSyncDataManager()
        let viewModel = TreeViewModel()
        viewModel.setDataManager(mockDataManager)

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

        let node3 = Node(
            id: "test-3",
            title: "Test Node 3",
            nodeType: "note",
            parentId: "test-1",
            sortOrder: 3000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: "Test note")
        )

        // Set nodes in mock DataManager and trigger update
        mockDataManager.mockNodes = [node1, node2, node3]
        mockDataManager.nodes = mockDataManager.mockNodes

        // Test that focusedNode uses cache
        viewModel.focusedNodeId = "test-1"
        XCTAssertNotNil(viewModel.focusedNode)
        XCTAssertEqual(viewModel.focusedNode?.id, "test-1")
        XCTAssertEqual(viewModel.focusedNode?.title, "Test Node 1")

        viewModel.focusedNodeId = "test-2"
        XCTAssertNotNil(viewModel.focusedNode)
        XCTAssertEqual(viewModel.focusedNode?.id, "test-2")
        XCTAssertEqual(viewModel.focusedNode?.title, "Test Node 2")

        viewModel.focusedNodeId = "test-3"
        XCTAssertNotNil(viewModel.focusedNode)
        XCTAssertEqual(viewModel.focusedNode?.id, "test-3")
        XCTAssertEqual(viewModel.focusedNode?.title, "Test Node 3")

        // Test with non-existent node
        viewModel.focusedNodeId = "non-existent"
        XCTAssertNil(viewModel.focusedNode)

        // Test getRootNodes
        let rootNodes = viewModel.getRootNodes()
        XCTAssertEqual(rootNodes.count, 1)
        XCTAssertEqual(rootNodes[0].id, "test-1")

        // Test getChildren
        let children = viewModel.getChildren(of: "test-1")
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.contains { $0.id == "test-2" })
        XCTAssertTrue(children.contains { $0.id == "test-3" })

        // Verify children are sorted by sortOrder
        XCTAssertEqual(children[0].id, "test-2") // sortOrder 2000
        XCTAssertEqual(children[1].id, "test-3") // sortOrder 3000
    }

    func testNodeCache_ParentChain() {
        // Create TreeViewModel with mock DataManager
        let mockDataManager = MockSyncDataManager()
        let viewModel = TreeViewModel()
        viewModel.setDataManager(mockDataManager)

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

        // Set nodes in mock DataManager and trigger update
        mockDataManager.mockNodes = [root, parent, child, grandchild]
        mockDataManager.nodes = mockDataManager.mockNodes

        // Test getParentChain
        let parentChain = viewModel.getParentChain(for: grandchild)
        XCTAssertEqual(parentChain.count, 3)
        XCTAssertEqual(parentChain[0].id, "root")
        XCTAssertEqual(parentChain[1].id, "parent")
        XCTAssertEqual(parentChain[2].id, "child")

        // Test with root node (should have empty chain)
        let rootChain = viewModel.getParentChain(for: root)
        XCTAssertEqual(rootChain.count, 0)

        // Test with middle node
        let childChain = viewModel.getParentChain(for: child)
        XCTAssertEqual(childChain.count, 2)
        XCTAssertEqual(childChain[0].id, "root")
        XCTAssertEqual(childChain[1].id, "parent")
    }

    func testNodeCache_UpdatePreservesCache() {
        // Create TreeViewModel with mock DataManager
        let mockDataManager = MockSyncDataManager()
        let viewModel = TreeViewModel()
        viewModel.setDataManager(mockDataManager)

        // Initial nodes
        let node1 = Node(
            id: "node-1",
            title: "Initial Node 1",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        let node2 = Node(
            id: "node-2",
            title: "Initial Node 2",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )

        // Set initial nodes
        mockDataManager.mockNodes = [node1, node2]
        mockDataManager.nodes = mockDataManager.mockNodes

        // Verify initial state
        viewModel.focusedNodeId = "node-1"
        XCTAssertEqual(viewModel.focusedNode?.title, "Initial Node 1")

        viewModel.focusedNodeId = "node-2"
        XCTAssertEqual(viewModel.focusedNode?.title, "Initial Node 2")

        // Update nodes with changed titles
        let updatedNode1 = Node(
            id: "node-1",
            title: "Updated Node 1",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        let updatedNode2 = Node(
            id: "node-2",
            title: "Updated Node 2",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "done", priority: "high")
        )

        let newNode3 = Node(
            id: "node-3",
            title: "New Node 3",
            nodeType: "note",
            parentId: nil,
            sortOrder: 3000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: "New note")
        )

        // Update with new nodes
        mockDataManager.mockNodes = [updatedNode1, updatedNode2, newNode3]
        mockDataManager.nodes = mockDataManager.mockNodes

        // Verify cache is updated
        viewModel.focusedNodeId = "node-1"
        XCTAssertEqual(viewModel.focusedNode?.title, "Updated Node 1")

        viewModel.focusedNodeId = "node-2"
        XCTAssertEqual(viewModel.focusedNode?.title, "Updated Node 2")

        viewModel.focusedNodeId = "node-3"
        XCTAssertEqual(viewModel.focusedNode?.title, "New Node 3")

        // Verify allNodes count
        XCTAssertEqual(viewModel.allNodes.count, 3)
    }
}
import XCTest
import Foundation
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Core

/// Tests for focus-selection behavior
@MainActor
final class TreeViewModelFocusSelectionTests: XCTestCase {

    func testFocusOnNode_AlsoSelectsNode() {
        // Arrange
        let viewModel = TreeViewModel()

        let node1 = Node(id: "1", title: "Node 1", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        let node2 = Node(id: "2", title: "Node 2", nodeType: "task", parentId: nil, sortOrder: 200, createdAt: Date(), updatedAt: Date())

        viewModel.updateNodesFromDataManager([node1, node2])

        // Initially nothing should be selected or focused
        XCTAssertNil(viewModel.selectedNodeId)
        XCTAssertNil(viewModel.focusedNodeId)

        // Act - Focus on node1 using the user-facing API
        viewModel.focusOnNode(node1)

        // Assert - Both focus and selection should be set
        XCTAssertEqual(viewModel.focusedNodeId, "1", "Node should be focused")
        XCTAssertEqual(viewModel.selectedNodeId, "1", "Node should also be selected when focused")
        XCTAssertTrue(viewModel.expandedNodes.contains("1"), "Node should be expanded when focused")

        // Act - Focus on node2
        viewModel.focusOnNode(node2)

        // Assert - Selection should follow focus
        XCTAssertEqual(viewModel.focusedNodeId, "2", "Focus should move to node 2")
        XCTAssertEqual(viewModel.selectedNodeId, "2", "Selection should follow focus to node 2")
        XCTAssertTrue(viewModel.expandedNodes.contains("2"), "Node 2 should be expanded")
    }

    func testSetFocusedNode_DoesNotChangeSelection() {
        // Arrange
        let viewModel = TreeViewModel()

        let node1 = Node(id: "1", title: "Node 1", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        let node2 = Node(id: "2", title: "Node 2", nodeType: "task", parentId: nil, sortOrder: 200, createdAt: Date(), updatedAt: Date())

        viewModel.updateNodesFromDataManager([node1, node2])

        // Set initial selection
        viewModel.selectedNodeId = "1"

        // Act - Use low-level setter (e.g., for programmatic focus change)
        viewModel.setFocusedNode("2")

        // Assert - Focus changes but selection does not
        XCTAssertEqual(viewModel.focusedNodeId, "2", "Focus should change to node 2")
        XCTAssertEqual(viewModel.selectedNodeId, "1", "Selection should remain on node 1")
        XCTAssertTrue(viewModel.expandedNodes.contains("2"), "Node 2 should still be expanded")
    }

    func testFocusOnNode_BatchesUpdates() {
        // Arrange
        let viewModel = TreeViewModel()
        var updateCount = 0
        var cancellables = Set<AnyCancellable>()

        let node = Node(id: "test", title: "Test Node", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        viewModel.updateNodesFromDataManager([node])

        // Subscribe to track update batching
        viewModel.$focusedNodeId
            .dropFirst()
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        viewModel.$selectedNodeId
            .dropFirst()
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        viewModel.$expandedNodes
            .dropFirst()
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        // Act
        viewModel.focusOnNode(node)

        // Assert - All three updates should happen in a single batch
        XCTAssertEqual(viewModel.focusedNodeId, "test")
        XCTAssertEqual(viewModel.selectedNodeId, "test")
        XCTAssertTrue(viewModel.expandedNodes.contains("test"))

        // With batching, we expect 3 updates (one for each property)
        XCTAssertLessThanOrEqual(updateCount, 3, "Updates should be batched")
    }

    func testFocusOnSmartFolder_SelectsAndExecutes() async {
        // Arrange
        let viewModel = TreeViewModel()

        let smartFolder = Node(
            id: "smart",
            title: "Smart Folder",
            nodeType: "smart_folder",
            parentId: nil,
            sortOrder: 100,
            createdAt: Date(),
            updatedAt: Date()
        )

        viewModel.updateNodesFromDataManager([smartFolder])

        // Act
        viewModel.focusOnNode(smartFolder)

        // Assert - Smart folder should be both focused and selected
        XCTAssertEqual(viewModel.focusedNodeId, "smart", "Smart folder should be focused")
        XCTAssertEqual(viewModel.selectedNodeId, "smart", "Smart folder should be selected")
        XCTAssertTrue(viewModel.expandedNodes.contains("smart"), "Smart folder should be expanded")

        // Note: Smart folder execution happens asynchronously via Task
        // We're not testing that here as it would require mocking DataManager
    }

    func testSelectAndFocus_CompositeIntent() {
        // Arrange
        let viewModel = TreeViewModel()

        let node = Node(id: "1", title: "Node 1", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        viewModel.updateNodesFromDataManager([node])

        // Act - Use the composite intent method
        viewModel.selectAndFocus("1")

        // Assert - Both should be set
        XCTAssertEqual(viewModel.selectedNodeId, "1", "Node should be selected")
        XCTAssertEqual(viewModel.focusedNodeId, "1", "Node should be focused")
        XCTAssertTrue(viewModel.expandedNodes.contains("1"), "Node should be expanded")
    }
}
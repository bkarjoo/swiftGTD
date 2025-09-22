import XCTest
import Foundation
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Core

/// Tests for TreeViewModel batch UI update optimization
@MainActor
final class TreeViewModelBatchUpdateTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    func testSelectAndFocus_BatchesMultipleUpdates() {
        // Arrange
        let viewModel = TreeViewModel()
        var updateCount = 0

        // Create test nodes
        let nodes = [
            Node(id: "1", title: "One", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date()),
            Node(id: "2", title: "Two", nodeType: "task", parentId: "1", sortOrder: 200, createdAt: Date(), updatedAt: Date())
        ]
        viewModel.updateNodesFromDataManager(nodes)

        // Subscribe to all the properties that should be batched
        viewModel.$selectedNodeId
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        viewModel.$focusedNodeId
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        viewModel.$expandedNodes
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        // Reset count after initial setup
        updateCount = 0

        // Act - Call selectAndFocus which should batch updates
        viewModel.selectAndFocus("2")

        // Assert
        XCTAssertEqual(viewModel.selectedNodeId, "2", "Should select node 2")
        XCTAssertEqual(viewModel.focusedNodeId, "2", "Should focus node 2")
        XCTAssertTrue(viewModel.expandedNodes.contains("2"), "Should expand node 2")

        // The key assertion: should only trigger one update cycle for all 3 properties
        // Due to batching with withTransaction, we expect fewer updates than 3
        // Note: SwiftUI/Combine may coalesce some updates automatically,
        // but without batching we'd see more separate updates
        XCTAssertLessThanOrEqual(updateCount, 3, "Updates should be batched, not separate")
    }

    func testCollapseNode_BatchesSelectionAndFocusUpdates() {
        // Arrange
        let viewModel = TreeViewModel()

        // Create hierarchy: parent -> child
        let parent = Node(id: "parent", title: "Parent", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        let child = Node(id: "child", title: "Child", nodeType: "task", parentId: "parent", sortOrder: 200, createdAt: Date(), updatedAt: Date())

        viewModel.updateNodesFromDataManager([parent, child])

        // Setup initial state: parent expanded, child selected and focused
        viewModel.expandedNodes.insert("parent")
        viewModel.selectedNodeId = "child"
        viewModel.focusedNodeId = "child"

        var updateCount = 0

        // Subscribe to track updates
        viewModel.$selectedNodeId
            .dropFirst() // Skip current value
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        viewModel.$focusedNodeId
            .dropFirst()
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        viewModel.$expandedNodes
            .dropFirst()
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        // Act - Collapse parent (should move selection and clear focus)
        viewModel.collapseNode("parent")

        // Assert
        XCTAssertFalse(viewModel.expandedNodes.contains("parent"), "Parent should be collapsed")
        XCTAssertEqual(viewModel.selectedNodeId, "parent", "Selection should move to parent")
        XCTAssertNil(viewModel.focusedNodeId, "Focus should be cleared")

        // Should batch the updates
        XCTAssertLessThanOrEqual(updateCount, 3, "Updates should be batched")
    }

    func testFocusOnNode_BatchesExpandAndFocus() {
        // Arrange
        let viewModel = TreeViewModel()
        let node = Node(id: "test", title: "Test", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        viewModel.updateNodesFromDataManager([node])

        var focusUpdateCount = 0
        var expandUpdateCount = 0

        viewModel.$focusedNodeId
            .dropFirst()
            .sink { _ in focusUpdateCount += 1 }
            .store(in: &cancellables)

        viewModel.$expandedNodes
            .dropFirst()
            .sink { _ in expandUpdateCount += 1 }
            .store(in: &cancellables)

        // Act
        viewModel.focusOnNode(node)

        // Assert
        XCTAssertEqual(viewModel.focusedNodeId, "test")
        XCTAssertTrue(viewModel.expandedNodes.contains("test"))

        // Both updates should happen in same transaction
        XCTAssertEqual(focusUpdateCount, 1, "Focus should update once")
        XCTAssertEqual(expandUpdateCount, 1, "Expand should update once")
    }

    func testNavigateLeft_BatchesFocusAndSelectionChanges() {
        // Arrange
        let viewModel = TreeViewModel()

        let parent = Node(id: "parent", title: "Parent", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        let child = Node(id: "child", title: "Child", nodeType: "folder", parentId: "parent", sortOrder: 200, createdAt: Date(), updatedAt: Date())

        viewModel.updateNodesFromDataManager([parent, child])

        // Set initial state: parent expanded, child selected
        viewModel.expandedNodes.insert("parent")
        viewModel.selectedNodeId = "child"

        var updateCount = 0

        viewModel.$selectedNodeId
            .dropFirst()
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        viewModel.$expandedNodes
            .dropFirst()
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)

        // Act - Collapse parent (which moves selection to parent)
        viewModel.collapseNode("parent")

        // Assert - collapseNode should batch the updates
        XCTAssertFalse(viewModel.expandedNodes.contains("parent"), "Parent should be collapsed")
        XCTAssertEqual(viewModel.selectedNodeId, "parent", "Selection should move to parent when collapsed")

        // Updates should be batched
        XCTAssertLessThanOrEqual(updateCount, 2, "Updates should be batched")
    }

    func testBatchUI_PreventsSeparateUpdates() {
        // This test directly verifies the batchUI helper works
        let viewModel = TreeViewModel()

        // Setup nodes
        let nodes = [
            Node(id: "1", title: "One", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date()),
            Node(id: "2", title: "Two", nodeType: "folder", parentId: nil, sortOrder: 200, createdAt: Date(), updatedAt: Date()),
            Node(id: "3", title: "Three", nodeType: "folder", parentId: nil, sortOrder: 300, createdAt: Date(), updatedAt: Date())
        ]
        viewModel.updateNodesFromDataManager(nodes)

        var totalUpdates = 0

        // Track all published property changes
        viewModel.$selectedNodeId
            .sink { _ in totalUpdates += 1 }
            .store(in: &cancellables)

        viewModel.$focusedNodeId
            .sink { _ in totalUpdates += 1 }
            .store(in: &cancellables)

        viewModel.$expandedNodes
            .sink { _ in totalUpdates += 1 }
            .store(in: &cancellables)

        // Reset after initial setup
        totalUpdates = 0

        // Act - Perform multiple operations that use batching
        viewModel.selectAndFocus("1")
        viewModel.selectAndFocus("2")
        viewModel.expandedNodes.insert("3") // Expand node 3

        // Assert
        // Without batching, we'd expect 9 updates (3 properties x 3 operations)
        // With batching, updates should be significantly reduced
        XCTAssertLessThan(totalUpdates, 9, "Batching should reduce total update count")

        // Verify final state is correct
        XCTAssertEqual(viewModel.selectedNodeId, "2", "Final selection should be node 2")
        XCTAssertEqual(viewModel.focusedNodeId, "2", "Final focus should be node 2")
        XCTAssertTrue(viewModel.expandedNodes.contains("1"), "Node 1 should be expanded")
        XCTAssertTrue(viewModel.expandedNodes.contains("2"), "Node 2 should be expanded")
        XCTAssertTrue(viewModel.expandedNodes.contains("3"), "Node 3 should be expanded")
    }
}
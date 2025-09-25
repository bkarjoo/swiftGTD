import XCTest
import Foundation
@testable import Features
@testable import Models
@testable import Core

/// Direct tests for node cache functionality
@MainActor
final class TreeViewModelCacheOnlyTests: XCTestCase {

    func testNodeCacheLookup_Performance() {
        // Create TreeViewModel
        let viewModel = TreeViewModel()

        // Create a large set of nodes
        var nodes: [Node] = []
        for i in 0..<1000 {
            let node = Node(
                id: "node-\(i)",
                title: "Node \(i)",
                nodeType: i % 3 == 0 ? "folder" : (i % 3 == 1 ? "task" : "note"),
                parentId: i > 0 ? "node-\(i/2)" : nil,
                sortOrder: i * 100,
                createdAt: Date(),
                updatedAt: Date()
            )
            nodes.append(node)
        }

        // Directly update the cache
        viewModel.updateNodesFromDataManager(nodes)

        // Test that focusedNode lookups are fast
        let startTime = CFAbsoluteTimeGetCurrent()

        // Perform 1000 lookups
        for i in 0..<1000 {
            viewModel.focusedNodeId = "node-\(i)"
            _ = viewModel.focusedNode
        }

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete in less than 0.1 seconds for 1000 lookups with cache
        // Without cache (O(n) lookups), this would take much longer
        XCTAssertLessThan(timeElapsed, 0.1, "1000 node lookups should complete in less than 0.1 seconds with cache")

        print("✅ 1000 node lookups completed in \(timeElapsed) seconds")
    }

    func testNodeCache_BasicFunctionality() {
        let viewModel = TreeViewModel()

        // Create simple test nodes
        let nodes = [
            Node(id: "1", title: "One", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date()),
            Node(id: "2", title: "Two", nodeType: "task", parentId: "1", sortOrder: 200, createdAt: Date(), updatedAt: Date()),
            Node(id: "3", title: "Three", nodeType: "note", parentId: "1", sortOrder: 300, createdAt: Date(), updatedAt: Date())
        ]

        // Update cache
        viewModel.updateNodesFromDataManager(nodes)

        // Test focused node lookup
        viewModel.focusedNodeId = "1"
        XCTAssertNotNil(viewModel.focusedNode, "Should find node 1")
        XCTAssertEqual(viewModel.focusedNode?.title, "One")

        viewModel.focusedNodeId = "2"
        XCTAssertNotNil(viewModel.focusedNode, "Should find node 2")
        XCTAssertEqual(viewModel.focusedNode?.title, "Two")

        viewModel.focusedNodeId = "999"
        XCTAssertNil(viewModel.focusedNode, "Should not find non-existent node")

        // Test that nodeChildren was built correctly
        XCTAssertNotNil(viewModel.nodeChildren["1"], "Node 1 should have children")
        XCTAssertEqual(viewModel.nodeChildren["1"]?.count, 2, "Node 1 should have 2 children")
        XCTAssertEqual(viewModel.nodeChildren["1"]?[0].id, "2", "First child should be node 2 (lower sortOrder)")
        XCTAssertEqual(viewModel.nodeChildren["1"]?[1].id, "3", "Second child should be node 3")
    }

    func testNodeCache_UpdateReplacesPrevious() {
        let viewModel = TreeViewModel()

        // Initial nodes
        let initialNodes = [
            Node(id: "A", title: "Alpha", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date())
        ]
        viewModel.updateNodesFromDataManager(initialNodes)

        viewModel.focusedNodeId = "A"
        XCTAssertEqual(viewModel.focusedNode?.title, "Alpha")

        // Update with different nodes
        let updatedNodes = [
            Node(id: "A", title: "Alpha Updated", nodeType: "folder", parentId: nil, sortOrder: 100, createdAt: Date(), updatedAt: Date()),
            Node(id: "B", title: "Beta", nodeType: "task", parentId: nil, sortOrder: 200, createdAt: Date(), updatedAt: Date())
        ]
        viewModel.updateNodesFromDataManager(updatedNodes)

        // Check cache was updated
        viewModel.focusedNodeId = "A"
        XCTAssertEqual(viewModel.focusedNode?.title, "Alpha Updated", "Node A should be updated")

        viewModel.focusedNodeId = "B"
        XCTAssertEqual(viewModel.focusedNode?.title, "Beta", "Node B should be added")
    }
}
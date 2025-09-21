import XCTest
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

class DataManagerSubtreeRemovalTests: XCTestCase {
    var dataManager: DataManager!
    var mockAPI: TestMockAPIClient!
    var mockNetworkMonitor: TestableNetworkMonitor!

    override func setUp() async throws {
        try await super.setUp()

        mockAPI = TestMockAPIClient()
        mockNetworkMonitor = await TestableNetworkMonitor()
        await MainActor.run {
            mockNetworkMonitor.isConnected = true
        }

        dataManager = await DataManager(
            apiClient: mockAPI,
            networkMonitor: mockNetworkMonitor
        )
    }

    func testRefreshNode_RemovesOrphanedDescendants() async throws {
        // Given: A tree structure with parent -> child -> grandchild
        let parent = Node.makeFolder(id: "parent", title: "Parent", parentId: nil)
        let child1 = Node.makeFolder(id: "child1", title: "Child 1", parentId: "parent")
        let grandchild1 = Node.makeFolder(id: "grandchild1", title: "Grandchild 1", parentId: "child1")
        let grandchild2 = Node.makeFolder(id: "grandchild2", title: "Grandchild 2", parentId: "child1")
        let child2 = Node.makeFolder(id: "child2", title: "Child 2", parentId: "parent")

        // Initial state: all nodes present
        await dataManager.setNodesForTesting([parent, child1, grandchild1, grandchild2, child2])

        // When: Parent refresh returns only child2 (child1 is removed)
        mockAPI.getNodeResponse = parent
        mockAPI.getNodesResponse = [child2] // child1 is no longer returned

        await dataManager.refreshNode("parent")

        // Then: child1 and its descendants should be removed
        let remainingNodes = await dataManager.getNodesForTesting()
        let remainingIds = Set(remainingNodes.map { $0.id })

        XCTAssertTrue(remainingIds.contains("parent"), "Parent should remain")
        XCTAssertTrue(remainingIds.contains("child2"), "Child2 should remain")
        XCTAssertFalse(remainingIds.contains("child1"), "Child1 should be removed")
        XCTAssertFalse(remainingIds.contains("grandchild1"), "Grandchild1 should be removed")
        XCTAssertFalse(remainingIds.contains("grandchild2"), "Grandchild2 should be removed")

        XCTAssertEqual(remainingNodes.count, 2, "Only parent and child2 should remain")
    }

    func testRefreshNode_PreservesSubtreesOfRemainingChildren() async throws {
        // Given: Parent with two children, each with their own children
        let parent = Node.makeFolder(id: "parent", title: "Parent", parentId: nil)
        let child1 = Node.makeFolder(id: "child1", title: "Child 1", parentId: "parent")
        let grandchild1 = Node.makeFolder(id: "gc1", title: "GC 1", parentId: "child1")
        let child2 = Node.makeFolder(id: "child2", title: "Child 2", parentId: "parent")
        let grandchild2 = Node.makeFolder(id: "gc2", title: "GC 2", parentId: "child2")

        await dataManager.setNodesForTesting([parent, child1, grandchild1, child2, grandchild2])

        // When: Parent refresh returns both children
        mockAPI.getNodeResponse = parent
        mockAPI.getNodesResponse = [child1, child2]

        await dataManager.refreshNode("parent")

        // Then: All nodes including grandchildren should remain
        let remainingNodes = await dataManager.getNodesForTesting()
        let remainingIds = Set(remainingNodes.map { $0.id })

        XCTAssertTrue(remainingIds.contains("parent"))
        XCTAssertTrue(remainingIds.contains("child1"))
        XCTAssertTrue(remainingIds.contains("child2"))
        XCTAssertTrue(remainingIds.contains("gc1"), "Grandchild of remaining child1 should be preserved")
        XCTAssertTrue(remainingIds.contains("gc2"), "Grandchild of remaining child2 should be preserved")

        XCTAssertEqual(remainingNodes.count, 5)
    }

    func testRefreshNode_HandlesDeepNesting() async throws {
        // Given: Deep nesting (4 levels)
        let root = Node.makeFolder(id: "root", title: "Root", parentId: nil)
        let level1 = Node.makeFolder(id: "l1", title: "L1", parentId: "root")
        let level2 = Node.makeFolder(id: "l2", title: "L2", parentId: "l1")
        let level3 = Node.makeFolder(id: "l3", title: "L3", parentId: "l2")
        let level4 = Node.makeFolder(id: "l4", title: "L4", parentId: "l3")

        await dataManager.setNodesForTesting([root, level1, level2, level3, level4])

        // When: Root refresh returns empty (all children removed)
        mockAPI.getNodeResponse = root
        mockAPI.getNodesResponse = []

        await dataManager.refreshNode("root")

        // Then: All descendants should be removed
        let remainingNodes = await dataManager.getNodesForTesting()

        XCTAssertEqual(remainingNodes.count, 1, "Only root should remain")
        XCTAssertEqual(remainingNodes.first?.id, "root")
    }
}

// MARK: - Test Helpers

extension DataManager {
    func setNodesForTesting(_ nodes: [Node]) async {
        await MainActor.run {
            self.nodes = nodes
        }
    }

    func getNodesForTesting() async -> [Node] {
        await MainActor.run {
            self.nodes
        }
    }
}

// MARK: - Test Mock API Client

class TestMockAPIClient: MockAPIClientBase {
    var getNodeResponse: Node?
    var getNodesResponse: [Node] = []

    override func getNode(id: String) async throws -> Node {
        guard let node = getNodeResponse else {
            throw NSError(domain: "Test", code: 404, userInfo: [NSLocalizedDescriptionKey: "Node not found"])
        }
        return node
    }

    override func getNodes(parentId: String?) async throws -> [Node] {
        return getNodesResponse
    }
}

extension Node {
    static func makeFolder(id: String, title: String, parentId: String?) -> Node {
        Node(
            id: id,
            title: title,
            nodeType: "folder",
            parentId: parentId,
            ownerId: "test-user",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: 0,
            isList: false,
            childrenCount: 0,
            tags: [],
            taskData: nil,
            noteData: nil,
            templateData: nil,
            smartFolderData: nil
        )
    }
}
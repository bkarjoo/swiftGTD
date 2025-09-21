import XCTest
@testable import Features
@testable import Models
@testable import Services
@testable import Core

@MainActor
class TreeViewNavigationTests: XCTestCase {
    var viewModel: TreeViewModel!
    var mockDataManager: MockDataManager!

    override func setUp() async throws {
        try await super.setUp()
        mockDataManager = MockDataManager()
        viewModel = TreeViewModel()
        viewModel.setDataManager(mockDataManager)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockDataManager = nil
        try await super.tearDown()
    }

    // MARK: - getRootNodes Tests

    func testGetRootNodes_ReturnsNodesWithoutParent() async {
        // Given
        let rootNode1 = createMockNode(id: "1", title: "Root 1", parentId: nil, sortOrder: 1)
        let rootNode2 = createMockNode(id: "2", title: "Root 2", parentId: nil, sortOrder: 0)
        let childNode = createMockNode(id: "3", title: "Child", parentId: "1", sortOrder: 0)

        mockDataManager.mockNodes = [rootNode1, rootNode2, childNode]
        await viewModel.initialLoad()

        // When
        let roots = viewModel.getRootNodes()

        // Then
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(roots[0].id, "2") // Lower sort order comes first
        XCTAssertEqual(roots[1].id, "1")
    }

    func testGetRootNodes_SortsBySortOrder() async {
        // Given
        let node1 = createMockNode(id: "1", title: "A", parentId: nil, sortOrder: 10)
        let node2 = createMockNode(id: "2", title: "B", parentId: nil, sortOrder: 5)
        let node3 = createMockNode(id: "3", title: "C", parentId: nil, sortOrder: 15)

        mockDataManager.mockNodes = [node1, node2, node3]
        await viewModel.initialLoad()

        // When
        let roots = viewModel.getRootNodes()

        // Then
        XCTAssertEqual(roots[0].sortOrder, 5)
        XCTAssertEqual(roots[1].sortOrder, 10)
        XCTAssertEqual(roots[2].sortOrder, 15)
    }

    // MARK: - getChildren Tests

    func testGetChildren_ReturnsDirectChildren() async {
        // Given
        let parent = createMockNode(id: "1", title: "Parent", parentId: nil)
        let child1 = createMockNode(id: "2", title: "Child 1", parentId: "1", sortOrder: 1)
        let child2 = createMockNode(id: "3", title: "Child 2", parentId: "1", sortOrder: 0)
        let grandchild = createMockNode(id: "4", title: "Grandchild", parentId: "2")

        mockDataManager.mockNodes = [parent, child1, child2, grandchild]
        await viewModel.initialLoad()

        // When
        let children = viewModel.getChildren(of: "1")

        // Then
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.contains { $0.id == "2" })
        XCTAssertTrue(children.contains { $0.id == "3" })
        XCTAssertFalse(children.contains { $0.id == "4" }) // Grandchild not included
    }

    func testGetChildren_ReturnsSortedChildren() async {
        // Given
        let parent = createMockNode(id: "1", title: "Parent", parentId: nil)
        let child1 = createMockNode(id: "2", title: "B", parentId: "1", sortOrder: 20)
        let child2 = createMockNode(id: "3", title: "A", parentId: "1", sortOrder: 10)
        let child3 = createMockNode(id: "4", title: "C", parentId: "1", sortOrder: 30)

        mockDataManager.mockNodes = [parent, child1, child2, child3]
        await viewModel.initialLoad()

        // When
        let children = viewModel.getChildren(of: "1")

        // Then
        XCTAssertEqual(children.count, 3)
        XCTAssertEqual(children[0].id, "3") // sortOrder 10
        XCTAssertEqual(children[1].id, "2") // sortOrder 20
        XCTAssertEqual(children[2].id, "4") // sortOrder 30
    }

    func testGetChildren_ReturnsEmptyForNodeWithoutChildren() async {
        // Given
        let node = createMockNode(id: "1", title: "Lonely", parentId: nil)
        mockDataManager.mockNodes = [node]
        await viewModel.initialLoad()

        // When
        let children = viewModel.getChildren(of: "1")

        // Then
        XCTAssertEqual(children.count, 0)
    }

    // MARK: - getParentChain Tests

    func testGetParentChain_ReturnsFullChain() async {
        // Given
        let root = createMockNode(id: "1", title: "Root", parentId: nil)
        let parent = createMockNode(id: "2", title: "Parent", parentId: "1")
        let child = createMockNode(id: "3", title: "Child", parentId: "2")
        let grandchild = createMockNode(id: "4", title: "Grandchild", parentId: "3")

        mockDataManager.mockNodes = [root, parent, child, grandchild]
        await viewModel.initialLoad()

        // When
        let chain = viewModel.getParentChain(for: grandchild)

        // Then
        XCTAssertEqual(chain.count, 3)
        XCTAssertEqual(chain[0].id, "1") // Root
        XCTAssertEqual(chain[1].id, "2") // Parent
        XCTAssertEqual(chain[2].id, "3") // Child
    }

    func testGetParentChain_ReturnsEmptyForRootNode() async {
        // Given
        let root = createMockNode(id: "1", title: "Root", parentId: nil)
        mockDataManager.mockNodes = [root]
        await viewModel.initialLoad()

        // When
        let chain = viewModel.getParentChain(for: root)

        // Then
        XCTAssertEqual(chain.count, 0)
    }

    // MARK: - Selection State Tests

    func testSelectedNodeId_PersistsAfterUpdate() async {
        // Given
        let node1 = createMockNode(id: "1", title: "Node 1", parentId: nil)
        let node2 = createMockNode(id: "2", title: "Node 2", parentId: nil)
        mockDataManager.mockNodes = [node1, node2]
        await viewModel.initialLoad()

        // When
        viewModel.selectedNodeId = "1"
        mockDataManager.mockNodes = [node1, node2] // Simulate refresh
        await viewModel.initialLoad()

        // Then
        XCTAssertEqual(viewModel.selectedNodeId, "1")
    }

    // MARK: - Expanded State Tests

    func testExpandedNodes_PersistsAfterUpdate() async {
        // Given
        let parent = createMockNode(id: "1", title: "Parent", parentId: nil)
        let child = createMockNode(id: "2", title: "Child", parentId: "1")
        mockDataManager.mockNodes = [parent, child]
        await viewModel.initialLoad()

        // When
        viewModel.expandedNodes.insert("1")
        mockDataManager.mockNodes = [parent, child] // Simulate refresh
        await viewModel.initialLoad()

        // Then
        XCTAssertTrue(viewModel.expandedNodes.contains("1"))
    }

    // MARK: - Focus Mode Tests

    func testFocusedNodeId_RestrictsVisibility() async {
        // Given
        let root = createMockNode(id: "1", title: "Root", parentId: nil)
        let focused = createMockNode(id: "2", title: "Focused", parentId: "1")
        let child = createMockNode(id: "3", title: "Child", parentId: "2")
        let sibling = createMockNode(id: "4", title: "Sibling", parentId: "1")

        mockDataManager.mockNodes = [root, focused, child, sibling]
        await viewModel.initialLoad()

        // When
        viewModel.focusedNodeId = "2"

        // Then
        // This tests that focus mode is set, actual visibility would be in view tests
        XCTAssertEqual(viewModel.focusedNodeId, "2")
        XCTAssertNotNil(viewModel.currentFocusedNode)
        XCTAssertEqual(viewModel.currentFocusedNode?.id, "2")
    }

    // MARK: - Helper Methods

    private func createMockNode(
        id: String,
        title: String,
        parentId: String? = nil,
        sortOrder: Int = 0,
        nodeType: String = "folder"
    ) -> Node {
        return Node(
            id: id,
            title: title,
            nodeType: nodeType,
            parentId: parentId,
            ownerId: "test-user",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: sortOrder,
            isList: false,
            childrenCount: 0,
            tags: []
        )
    }
}
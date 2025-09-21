import XCTest
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

class TreeViewModelTemplateRetryTests: XCTestCase {
    var viewModel: TreeViewModel!
    var mockDataManager: MockDataManagerWithRetry!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        await MainActor.run {
            viewModel = TreeViewModel()
            mockDataManager = MockDataManagerWithRetry()
            cancellables = Set<AnyCancellable>()

            // Set up the mock data manager
            viewModel.setDataManager(mockDataManager)
        }
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    func testTemplateInstantiation_WithEventualConsistency_RetriesUntilNodeAppears() async throws {
        // Given: A template and target parent node
        let parentNode = Node.makeFolder(id: "parent", title: "Parent Folder")
        let templateNode = Node.makeTemplate(id: "template1", title: "My Template", targetNodeId: "parent")
        let newNode = Node.makeFolder(id: "new-node", title: "Created from Template", parentId: "parent")

        await MainActor.run {
            mockDataManager.nodes = [parentNode, templateNode]
        }

        // Setup mock to return the new node from instantiation
        mockDataManager.instantiateTemplateResult = newNode

        // Setup refresh to simulate eventual consistency:
        // First refresh: parent has no children yet
        // Second refresh: parent now has the new child
        var refreshCallCount = 0
        mockDataManager.onRefreshNode = { nodeId in
            XCTAssertEqual(nodeId, "parent", "Should refresh the parent node")
            refreshCallCount += 1

            if refreshCallCount == 1 {
                // First refresh: node not yet visible (eventual consistency delay)
                // Don't add the new node yet
            } else if refreshCallCount == 2 {
                // Second refresh: node now appears
                await MainActor.run {
                    self.mockDataManager.nodes.append(newNode)
                }
            }
        }

        // Create expectation for node to be added
        let nodeAddedExpectation = expectation(description: "New node should be added to allNodes")

        // Monitor for the new node to appear
        await MainActor.run {
            viewModel.$allNodes
                .dropFirst() // Skip initial value
                .sink { nodes in
                    if nodes.contains(where: { $0.id == "new-node" }) {
                        nodeAddedExpectation.fulfill()
                    }
                }
                .store(in: &cancellables)
        }

        // When: Instantiate the template
        await viewModel.instantiateTemplate(templateNode)

        // Then: Wait for the retry logic to succeed
        await fulfillment(of: [nodeAddedExpectation], timeout: 3.0)

        // Verify the retry logic was exercised
        XCTAssertEqual(refreshCallCount, 2, "Should have refreshed twice due to retry")

        // Verify the final state
        await MainActor.run {
            XCTAssertTrue(viewModel.allNodes.contains(where: { $0.id == "new-node" }),
                         "New node should be in allNodes")
            XCTAssertTrue(viewModel.expandedNodes.contains("parent"),
                         "Parent should be expanded to show new node")
            XCTAssertEqual(viewModel.selectedNodeId, "new-node",
                          "New node should be selected")
            XCTAssertEqual(viewModel.focusedNodeId, "new-node",
                          "New node should be focused")
        }
    }

    func testTemplateInstantiation_ImmediateSuccess_NoRetryNeeded() async throws {
        // Given: Template instantiation succeeds immediately
        let parentNode = Node.makeFolder(id: "parent", title: "Parent")
        let templateNode = Node.makeTemplate(id: "template1", title: "Template", targetNodeId: "parent")
        let newNode = Node.makeFolder(id: "new-node", title: "Created", parentId: "parent")

        await MainActor.run {
            mockDataManager.nodes = [parentNode, templateNode]
        }

        mockDataManager.instantiateTemplateResult = newNode

        // Setup: Node appears immediately (no eventual consistency delay)
        await MainActor.run {
            // Add the new node immediately to simulate instant consistency
            mockDataManager.nodes.append(newNode)
        }

        var refreshCallCount = 0
        mockDataManager.onRefreshNode = { _ in
            refreshCallCount += 1
        }

        // When: Instantiate the template
        await viewModel.instantiateTemplate(templateNode)

        // Then: No retries should be needed
        XCTAssertEqual(refreshCallCount, 0, "Should not need to refresh when node appears immediately")

        await MainActor.run {
            XCTAssertTrue(viewModel.allNodes.contains(where: { $0.id == "new-node" }))
            XCTAssertEqual(viewModel.selectedNodeId, "new-node")
            XCTAssertEqual(viewModel.focusedNodeId, "new-node")
        }
    }

    func testTemplateInstantiation_MaxRetriesExceeded_StillSetsUIState() async throws {
        // Given: Template instantiation succeeds but node never appears (worst case)
        let parentNode = Node.makeFolder(id: "parent", title: "Parent")
        let templateNode = Node.makeTemplate(id: "template1", title: "Template", targetNodeId: "parent")
        let newNode = Node.makeFolder(id: "new-node", title: "Created", parentId: "parent")

        await MainActor.run {
            mockDataManager.nodes = [parentNode, templateNode]
        }

        mockDataManager.instantiateTemplateResult = newNode

        var refreshCallCount = 0
        mockDataManager.onRefreshNode = { _ in
            refreshCallCount += 1
            // Never add the node - simulate persistent consistency issue
        }

        // When: Instantiate the template
        await viewModel.instantiateTemplate(templateNode)

        // Allow retry loop to complete (3 retries * 0.5s = 1.5s + buffer)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Then: Should have tried maximum retries
        XCTAssertEqual(refreshCallCount, 3, "Should have tried maximum 3 retries")

        // Even though node isn't in allNodes, UI state should be updated optimistically
        await MainActor.run {
            XCTAssertFalse(viewModel.allNodes.contains(where: { $0.id == "new-node" }),
                          "Node won't be in allNodes if retries fail")
            XCTAssertTrue(viewModel.expandedNodes.contains("parent"),
                         "Parent should still be expanded")
            // Selection/focus might not be set if node never appears
        }
    }
}

// MARK: - Mock DataManager with Retry Support

class MockDataManagerWithRetry: DataManager {
    var instantiateTemplateResult: Node?
    var onRefreshNode: ((String) async -> Void)?

    init() {
        // Use a mock API client and network monitor
        let mockAPI = MockAPIClient()
        let mockNetworkMonitor = TestableNetworkMonitor()
        mockNetworkMonitor.isConnected = true

        super.init(apiClient: mockAPI, networkMonitor: mockNetworkMonitor)
    }

    override func instantiateTemplate(templateId: String, parentId: String? = nil) async -> Node? {
        return instantiateTemplateResult
    }

    override func refreshNode(_ nodeId: String) async {
        await onRefreshNode?(nodeId)
    }
}

// MARK: - Node Factory Helpers

extension Node {
    static func makeFolder(id: String, title: String, parentId: String? = nil) -> Node {
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

    static func makeTemplate(id: String, title: String, targetNodeId: String? = nil) -> Node {
        Node(
            id: id,
            title: title,
            nodeType: "template",
            parentId: nil,
            ownerId: "test-user",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: 0,
            isList: false,
            childrenCount: 0,
            tags: [],
            taskData: nil,
            noteData: nil,
            templateData: TemplateData(
                templateBody: "Template content",
                targetNodeId: targetNodeId
            ),
            smartFolderData: nil
        )
    }
}
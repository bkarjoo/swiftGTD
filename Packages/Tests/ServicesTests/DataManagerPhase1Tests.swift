import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Core
@testable import Networking

/// Tests for Phase 1 refactoring - DataManager API centralization
@MainActor
final class DataManagerPhase1Tests: XCTestCase {

    private var dataManager: DataManager!
    private var mockAPI: MockPhase1APIClient!
    private var mockNetworkMonitor: TestableNetworkMonitor!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        mockNetworkMonitor = TestableNetworkMonitor()
        mockNetworkMonitor.simulateConnectionChange(isConnected: true)
        mockAPI = MockPhase1APIClient()
        cancellables = []

        dataManager = DataManager(
            apiClient: mockAPI,
            networkMonitor: mockNetworkMonitor
        )
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        dataManager = nil
        mockAPI = nil
        mockNetworkMonitor = nil
        try await super.tearDown()
    }

    // MARK: - Default Folder Tests

    func testGetDefaultFolder_ReturnsStoredValue() async {
        // Arrange
        mockAPI.defaultNodeId = "folder-123"

        // Act
        let defaultFolder = await dataManager.getDefaultFolder()

        // Assert
        XCTAssertEqual(defaultFolder, "folder-123")
        XCTAssertTrue(mockAPI.getDefaultNodeCalled)
    }

    func testGetDefaultFolder_ReturnsNilWhenNotSet() async {
        // Arrange
        mockAPI.defaultNodeId = nil

        // Act
        let defaultFolder = await dataManager.getDefaultFolder()

        // Assert
        XCTAssertNil(defaultFolder)
        XCTAssertTrue(mockAPI.getDefaultNodeCalled)
    }

    func testSetDefaultFolder_UpdatesValue() async {
        // Arrange
        let newFolderId = "folder-456"

        // Act
        let success = await dataManager.setDefaultFolder(nodeId: newFolderId)

        // Assert
        XCTAssertTrue(success)
        XCTAssertEqual(mockAPI.defaultNodeId, newFolderId)
        XCTAssertTrue(mockAPI.setDefaultNodeCalled)
    }

    func testSetDefaultFolder_HandlesNil() async {
        // Arrange
        mockAPI.defaultNodeId = "existing-folder"

        // Act
        let success = await dataManager.setDefaultFolder(nodeId: nil)

        // Assert
        XCTAssertTrue(success)
        XCTAssertNil(mockAPI.defaultNodeId)
        XCTAssertTrue(mockAPI.setDefaultNodeCalled)
    }

    // MARK: - Template Instantiation Tests

    func testInstantiateTemplate_CreatesNewNode() async {
        // Arrange
        let templateId = "template-123"
        let expectedNode = Node(
            id: "new-node-456",
            title: "Template Instance",
            nodeType: "folder",
            parentId: nil,
            ownerId: "user-1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: 0
        )
        mockAPI.instantiatedNode = expectedNode

        // Act
        let newNode = await dataManager.instantiateTemplate(
            templateId: templateId,
            parentId: nil
        )

        // Assert
        XCTAssertNotNil(newNode)
        XCTAssertEqual(newNode?.id, expectedNode.id)
        XCTAssertEqual(newNode?.title, expectedNode.title)
        XCTAssertTrue(mockAPI.instantiateTemplateCalled)
        XCTAssertEqual(mockAPI.lastInstantiatedTemplateId, templateId)
    }

    func testInstantiateTemplate_WithParentId() async {
        // Arrange
        let templateId = "template-789"
        let parentId = "parent-folder-123"
        let expectedNode = Node(
            id: "new-node-789",
            title: "Child Template",
            nodeType: "task",
            parentId: parentId,
            ownerId: "user-1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: 0
        )
        mockAPI.instantiatedNode = expectedNode

        // Act
        let newNode = await dataManager.instantiateTemplate(
            templateId: templateId,
            parentId: parentId
        )

        // Assert
        XCTAssertNotNil(newNode)
        XCTAssertEqual(newNode?.parentId, parentId)
        XCTAssertTrue(mockAPI.instantiateTemplateCalled)
        XCTAssertEqual(mockAPI.lastInstantiatedParentId, parentId)
    }

    func testInstantiateTemplate_RefreshesData() async {
        // Arrange
        let templateId = "template-refresh"
        mockAPI.instantiatedNode = Node(
            id: "new-1",
            title: "New Node",
            nodeType: "folder",
            parentId: nil,
            ownerId: "user-1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sortOrder: 0
        )

        // Act
        let result = await dataManager.instantiateTemplate(templateId: templateId)

        // Assert - Per CLAUDE.md, instantiateTemplate does not sync, caller handles refresh
        XCTAssertNotNil(result, "Should return the new node")
        XCTAssertTrue(mockAPI.instantiateTemplateCalled, "Should call API to instantiate template")
        XCTAssertFalse(mockAPI.getAllNodesCalled, "Should NOT trigger data sync after instantiation (per architecture)")
    }

    // MARK: - Smart Folder Execution Tests

    func testExecuteSmartFolder_ReturnsResults() async {
        // Arrange
        let smartFolderId = "smart-123"
        let expectedResults = [
            Node(
                id: "result-1",
                title: "Overdue Task 1",
                nodeType: "task",
                parentId: nil,
                ownerId: "user-1",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                sortOrder: 0
            ),
            Node(
                id: "result-2",
                title: "Overdue Task 2",
                nodeType: "task",
                parentId: nil,
                ownerId: "user-1",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                sortOrder: 1
            )
        ]
        mockAPI.smartFolderResults = expectedResults

        // Act
        let results = await dataManager.executeSmartFolder(nodeId: smartFolderId)

        // Assert
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "result-1")
        XCTAssertEqual(results[1].id, "result-2")
        XCTAssertTrue(mockAPI.executeSmartFolderCalled)
        XCTAssertEqual(mockAPI.lastExecutedSmartFolderId, smartFolderId)
    }

    func testExecuteSmartFolder_HandlesEmptyResults() async {
        // Arrange
        let smartFolderId = "smart-empty"
        mockAPI.smartFolderResults = []

        // Act
        let results = await dataManager.executeSmartFolder(nodeId: smartFolderId)

        // Assert
        XCTAssertEqual(results.count, 0)
        XCTAssertTrue(mockAPI.executeSmartFolderCalled)
    }

    func testExecuteSmartFolder_HandlesError() async {
        // Arrange
        let smartFolderId = "smart-error"
        mockAPI.shouldThrowError = true

        // Act
        let results = await dataManager.executeSmartFolder(nodeId: smartFolderId)

        // Assert
        XCTAssertEqual(results.count, 0, "Should return empty array on error")
        XCTAssertNotNil(dataManager.errorMessage, "Should set error message")
        XCTAssertTrue(mockAPI.executeSmartFolderCalled)
    }
}

// MARK: - Mock API Client for Phase 1 Tests

class MockPhase1APIClient: MockAPIClientBase {
    // Default folder tracking
    var defaultNodeId: String?
    var getDefaultNodeCalled = false
    var setDefaultNodeCalled = false

    // Template tracking
    var instantiatedNode: Node?
    var instantiateTemplateCalled = false
    var lastInstantiatedTemplateId: String?
    var lastInstantiatedParentId: String?

    // Smart folder tracking
    var smartFolderResults: [Node] = []
    var executeSmartFolderCalled = false
    var lastExecutedSmartFolderId: String?

    // General tracking
    var getAllNodesCalled = false
    var shouldThrowError = false

    override func getDefaultNode() async throws -> String? {
        getDefaultNodeCalled = true
        if shouldThrowError {
            throw Networking.APIError.networkError(NSError(domain: "Test", code: -1))
        }
        return defaultNodeId
    }

    override func setDefaultNode(nodeId: String?) async throws {
        setDefaultNodeCalled = true
        if shouldThrowError {
            throw Networking.APIError.networkError(NSError(domain: "Test", code: -1))
        }
        defaultNodeId = nodeId
    }

    override func instantiateTemplate(templateId: String, parentId: String?) async throws -> Node {
        instantiateTemplateCalled = true
        lastInstantiatedTemplateId = templateId
        lastInstantiatedParentId = parentId

        if shouldThrowError {
            throw Networking.APIError.networkError(NSError(domain: "Test", code: -1))
        }

        guard let node = instantiatedNode else {
            throw Networking.APIError.invalidResponse
        }
        return node
    }

    override func instantiateTemplate(templateId: String, name: String, parentId: String?) async throws -> Node {
        return try await instantiateTemplate(templateId: templateId, parentId: parentId)
    }

    override func executeSmartFolderRule(smartFolderId: String) async throws -> [Node] {
        executeSmartFolderCalled = true
        lastExecutedSmartFolderId = smartFolderId

        if shouldThrowError {
            throw Networking.APIError.networkError(NSError(domain: "Test", code: -1))
        }

        return smartFolderResults
    }

    override func getAllNodes() async throws -> [Node] {
        getAllNodesCalled = true
        return []
    }

    override func getNodes(parentId: String?) async throws -> [Node] {
        return []
    }
}
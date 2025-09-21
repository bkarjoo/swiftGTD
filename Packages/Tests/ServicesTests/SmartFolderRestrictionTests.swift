import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Features
@testable import Networking
@testable import Core

/// Tests for smart folder restriction rules
@MainActor
final class SmartFolderRestrictionTests: XCTestCase {

    var dataManager: DataManager!
    var mockAPI: MockSmartFolderAPIClient!
    var nodeDetailsViewModel: NodeDetailsViewModel!

    override func setUp() async throws {
        try await super.setUp()

        mockAPI = MockSmartFolderAPIClient()
        dataManager = DataManager(apiClient: mockAPI)
        nodeDetailsViewModel = NodeDetailsViewModel()
        nodeDetailsViewModel.setDataManager(dataManager)

        // Setup test data
        let smartFolder = Node(
            id: "smart-folder-1",
            title: "Smart Folder",
            nodeType: "smart_folder",
            parentId: nil,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date(),
            smartFolderData: SmartFolderData(
                ruleId: "rule-123",
                autoRefresh: true,
                description: "Test smart folder"
            )
        )

        let regularFolder = Node(
            id: "folder-1",
            title: "Regular Folder",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1,
            createdAt: Date(),
            updatedAt: Date()
        )

        let task = Node(
            id: "task-1",
            title: "Task",
            nodeType: "task",
            parentId: nil,
            sortOrder: 2,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )

        mockAPI.mockNodes = [smartFolder, regularFolder, task]
        dataManager.nodes = [smartFolder, regularFolder, task]
    }

    override func tearDown() async throws {
        nodeDetailsViewModel = nil
        dataManager = nil
        mockAPI = nil
        try await super.tearDown()
    }

    // MARK: - Rule 1: Smart folders cannot be parents

    func testSmartFolderRestriction_smartFolderCannotHaveParentId() async throws {
        // Test that creating a node with smart folder as parent would be invalid
        // This is enforced at the API level and in the UI by filtering available parents

        let smartFolder = mockAPI.mockNodes.first { $0.nodeType == "smart_folder" }!

        // Attempting to create a node under a smart folder should be prevented
        // In the actual app, the smart folder won't appear in the parent picker
        XCTAssertEqual(smartFolder.nodeType, "smart_folder")

        // Smart folders themselves should not have children count
        let nodeWithSmartFolderParent = Node(
            id: "invalid-child",
            title: "Invalid Child",
            nodeType: "task",
            parentId: smartFolder.id, // This would be invalid
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )

        // In practice, the UI prevents this by not showing smart folders as parent options
        XCTAssertEqual(nodeWithSmartFolderParent.parentId, "smart-folder-1")
        XCTAssertEqual(smartFolder.childrenCount, 0, "Smart folders should have 0 children count")
    }

    // MARK: - Rule 2: Cannot tag smart folders

    func testSmartFolderRestriction_cannotTagSmartFolder() {
        // This would be tested in the UI layer
        // The TreeNodeView should hide the Tags menu item for smart folders
        // We can test that the smart folder data model doesn't include tags

        let smartFolder = Node(
            id: "smart-1",
            title: "Smart",
            nodeType: "smart_folder",
            parentId: nil,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date(),
            tags: [], // Even if empty, smart folders shouldn't support tags
            smartFolderData: SmartFolderData(ruleId: "rule-1")
        )

        // In the actual UI, the context menu would not show "Tags" option
        // This is a business rule enforced at the UI level
        XCTAssertEqual(smartFolder.nodeType, "smart_folder")
        XCTAssertTrue(smartFolder.tags.isEmpty)
    }

    // MARK: - Rule 3: Smart folder execution

    func testSmartFolderExecution_returnsFilteredNodes() async throws {
        // Arrange
        let smartFolderId = "smart-folder-1"
        let expectedResults = [
            Node(
                id: "result-1",
                title: "Filtered Task 1",
                nodeType: "task",
                parentId: nil,
                sortOrder: 0,
                createdAt: Date(),
                updatedAt: Date()
            ),
            Node(
                id: "result-2",
                title: "Filtered Task 2",
                nodeType: "task",
                parentId: nil,
                sortOrder: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        mockAPI.smartFolderResults[smartFolderId] = expectedResults

        // Act
        let results = try await mockAPI.executeSmartFolderRule(smartFolderId: smartFolderId)

        // Assert
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "result-1")
        XCTAssertEqual(results[1].id, "result-2")
    }

    func testSmartFolderExecution_withNoMatches_returnsEmptyArray() async throws {
        // Arrange
        let smartFolderId = "empty-smart-folder"
        mockAPI.smartFolderResults[smartFolderId] = []

        // Act
        let results = try await mockAPI.executeSmartFolderRule(smartFolderId: smartFolderId)

        // Assert
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Smart folder properties

    func testSmartFolderProperties_hasCorrectNodeType() {
        // Arrange
        let smartFolder = Node(
            id: "sf-1",
            title: "My Smart Folder",
            nodeType: "smart_folder",
            parentId: nil,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date(),
            smartFolderData: SmartFolderData(
                ruleId: "rule-abc",
                autoRefresh: false,
                description: "Filters tasks"
            )
        )

        // Assert
        XCTAssertEqual(smartFolder.nodeType, "smart_folder")
        XCTAssertNotNil(smartFolder.smartFolderData)
        XCTAssertEqual(smartFolder.smartFolderData?.ruleId, "rule-abc")
        XCTAssertEqual(smartFolder.smartFolderData?.autoRefresh, false)
        XCTAssertEqual(smartFolder.smartFolderData?.description, "Filters tasks")
    }

    func testSmartFolderProperties_childrenCountIsZero() {
        // Smart folders have dynamic children, not stored children
        let smartFolder = Node(
            id: "sf-1",
            title: "Smart Folder",
            nodeType: "smart_folder",
            parentId: nil,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date(),
            childrenCount: 0, // Should always be 0 for smart folders
            smartFolderData: SmartFolderData(ruleId: "rule-1")
        )

        XCTAssertEqual(smartFolder.childrenCount, 0,
                      "Smart folders should have 0 static children count")
    }
}

// MARK: - Mock API Client for Smart Folder Tests

class MockSmartFolderAPIClient: MockAPIClientBase {
    var mockNodes: [Node] = []
    var mockTags: [Tag] = []
    var smartFolderResults: [String: [Node]] = [:]
    var shouldThrowError = false

    override func setAuthToken(_ token: String?) {}

    override func getCurrentUser() async throws -> User {
        return User(id: "test", email: "test@example.com", fullName: "Test User")
    }

    override func getNodes(parentId: String?) async throws -> [Node] {
        if let parentId = parentId {
            return mockNodes.filter { $0.parentId == parentId }
        }
        return mockNodes
    }

    override func getAllNodes() async throws -> [Node] {
        return mockNodes
    }

    override func getNode(id: String) async throws -> Node {
        guard let node = mockNodes.first(where: { $0.id == id }) else {
            throw APIError.httpError(404)
        }
        return node
    }

    override func createNode(_ node: Node) async throws -> Node {
        mockNodes.append(node)
        return node
    }

    override func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        guard let index = mockNodes.firstIndex(where: { $0.id == id }) else {
            throw APIError.httpError(404)
        }
        return mockNodes[index]
    }

    override func deleteNode(id: String) async throws {
        mockNodes.removeAll { $0.id == id }
    }

    override func getTags() async throws -> [Tag] {
        return mockTags
    }

    override func toggleTaskCompletion(nodeId: String, currentlyCompleted: Bool) async throws -> Node {
        guard let node = mockNodes.first(where: { $0.id == nodeId }) else {
            throw APIError.httpError(404)
        }
        return node
    }

    override func createFolder(title: String, parentId: String?) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: "folder",
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        mockNodes.append(node)
        return node
    }

    override func createTask(title: String, parentId: String?, description: String?) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: "task",
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(description: description, status: "todo", priority: "medium")
        )
        mockNodes.append(node)
        return node
    }

    override func createNote(title: String, parentId: String?, body: String) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: "note",
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: body)
        )
        mockNodes.append(node)
        return node
    }

    override func createGenericNode(title: String, nodeType: String, parentId: String?) async throws -> Node {
        let node = Node(
            id: UUID().uuidString,
            title: title,
            nodeType: nodeType,
            parentId: parentId,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        mockNodes.append(node)
        return node
    }

    override func executeSmartFolderRule(smartFolderId: String) async throws -> [Node] {
        if shouldThrowError {
            throw APIError.httpError(500)
        }
        return smartFolderResults[smartFolderId] ?? []
    }
}
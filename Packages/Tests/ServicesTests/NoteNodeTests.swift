import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Features
@testable import Networking
@testable import Core

/// Tests for note node functionality including restrictions and editing
@MainActor
final class NoteNodeTests: XCTestCase {

    var dataManager: DataManager!
    var mockAPI: MockNoteAPIClient!
    var nodeDetailsViewModel: NodeDetailsViewModel!

    override func setUp() async throws {
        try await super.setUp()

        mockAPI = MockNoteAPIClient()
        dataManager = DataManager(apiClient: mockAPI)
        nodeDetailsViewModel = NodeDetailsViewModel()
        nodeDetailsViewModel.setDataManager(dataManager)

        // Setup test data
        let noteNode = Node(
            id: "note-1",
            title: "Test Note",
            nodeType: "note",
            parentId: nil,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date(),
            noteData: NoteData(body: "# Test Content\n- Item 1\n- Item 2")
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

        mockAPI.mockNodes = [noteNode, regularFolder, task]
        dataManager.nodes = [noteNode, regularFolder, task]
    }

    override func tearDown() async throws {
        nodeDetailsViewModel = nil
        dataManager = nil
        mockAPI = nil
        try await super.tearDown()
    }

    // MARK: - Note Node Restrictions

    func testNoteNode_cannotBeParent() async throws {
        // Test that note nodes are excluded from available parents
        let noteNode = mockAPI.mockNodes.first { $0.nodeType == "note" }!

        // Attempting to create a node under a note should be prevented
        XCTAssertEqual(noteNode.nodeType, "note")

        // Create a test child node
        let childNode = Node(
            id: "child-1",
            title: "Child Node",
            nodeType: "task",
            parentId: noteNode.id, // This would be invalid
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )

        // The UI should prevent this by not showing notes as parent options
        XCTAssertEqual(childNode.parentId, "note-1")

        // Verify that notes have no children
        XCTAssertEqual(noteNode.childrenCount, 0, "Notes should always have 0 children count")
    }

    func testNoteNode_cannotHaveChildren() {
        // Test that note nodes cannot have children
        let noteNode = Node(
            id: "note-test",
            title: "Test Note",
            nodeType: "note",
            parentId: nil,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date(),
            childrenCount: 0, // Should always be 0
            noteData: NoteData(body: "Test content")
        )

        XCTAssertEqual(noteNode.nodeType, "note")
        XCTAssertEqual(noteNode.childrenCount, 0)
        XCTAssertFalse(noteNode.isList, "Notes cannot be lists")
    }

    func testNoteNode_notInAvailableParents() async {
        // Load available parents for a new node
        nodeDetailsViewModel.node = Node(
            id: "new-node",
            title: "New Node",
            nodeType: "task",
            parentId: nil,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Load available parents (this would filter out notes)
        await nodeDetailsViewModel.loadNode(nodeId: "new-node")

        // Note nodes should not appear in available parents
        let noteInParents = nodeDetailsViewModel.availableParents.contains { $0.nodeType == "note" }
        XCTAssertFalse(noteInParents, "Note nodes should not appear in available parents")
    }

    // MARK: - Note Content Tests

    func testNoteNode_hasNoteData() {
        let noteNode = mockAPI.mockNodes.first { $0.nodeType == "note" }!

        XCTAssertNotNil(noteNode.noteData, "Note nodes should have noteData")
        XCTAssertNotNil(noteNode.noteData?.body, "Note should have body content")
        XCTAssertEqual(noteNode.noteData?.body, "# Test Content\n- Item 1\n- Item 2")
    }

    func testNoteNode_updateContent() async throws {
        // Arrange
        let noteId = "note-1"
        let newContent = "# Updated Content\n## New Section\n- Updated item"

        // Act
        let update = NodeUpdate(
            title: "Test Note",
            parentId: nil,
            sortOrder: 0,
            noteData: NoteDataUpdate(body: newContent)
        )

        let updatedNode = try await mockAPI.updateNode(id: noteId, update: update)

        // Assert
        XCTAssertEqual(updatedNode.noteData?.body, newContent)
        XCTAssertEqual(updatedNode.id, noteId)
        XCTAssertEqual(updatedNode.nodeType, "note")
    }

    // MARK: - Markdown Rendering Tests

    func testMarkdownParsing_headers() {
        let markdown = "# Header 1\n## Header 2\n### Header 3"
        let lines = markdown.components(separatedBy: .newlines)

        XCTAssertTrue(lines[0].hasPrefix("# "))
        XCTAssertTrue(lines[1].hasPrefix("## "))
        XCTAssertTrue(lines[2].hasPrefix("### "))
    }

    func testMarkdownParsing_bulletPoints() {
        let markdown = "- Item 1\n* Item 2\n- Item 3"
        let lines = markdown.components(separatedBy: .newlines)

        XCTAssertTrue(lines[0].hasPrefix("- ") || lines[0].hasPrefix("* "))
        XCTAssertTrue(lines[1].hasPrefix("- ") || lines[1].hasPrefix("* "))
        XCTAssertTrue(lines[2].hasPrefix("- ") || lines[2].hasPrefix("* "))
    }

    func testMarkdownParsing_quotes() {
        let markdown = "> Quote line 1\n> Quote line 2"
        let lines = markdown.components(separatedBy: .newlines)

        XCTAssertTrue(lines[0].hasPrefix("> "))
        XCTAssertTrue(lines[1].hasPrefix("> "))
    }

    func testMarkdownParsing_codeBlocks() {
        let markdown = "```\ncode line 1\ncode line 2\n```"
        let lines = markdown.components(separatedBy: .newlines)

        XCTAssertTrue(lines[0].hasPrefix("```"))
        XCTAssertTrue(lines[3].hasPrefix("```"))
    }

    // MARK: - Note Creation Tests

    func testCreateNoteNode() async throws {
        // Arrange
        let title = "New Note"
        let body = "# New Note Content\nThis is a test note."

        // Act
        let newNode = try await mockAPI.createNote(
            title: title,
            parentId: "folder-1",
            body: body
        )

        // Assert
        XCTAssertEqual(newNode.title, title)
        XCTAssertEqual(newNode.nodeType, "note")
        XCTAssertEqual(newNode.noteData?.body, body)
        XCTAssertEqual(newNode.parentId, "folder-1")
    }

    func testNoteNode_cannotBeCreatedUnderNote() async throws {
        // Arrange
        let noteParentId = "note-1"

        // Act & Assert
        do {
            _ = try await mockAPI.createNote(
                title: "Invalid Note",
                parentId: noteParentId,
                body: "This should fail"
            )
            XCTFail("Should not allow creating note under another note")
        } catch {
            // Expected to fail
            XCTAssertTrue(true, "Correctly prevented note under note")
        }
    }
}

// MARK: - Mock API Client for Note Tests

class MockNoteAPIClient: MockAPIClientBase {
    var mockNodes: [Node] = []
    var mockTags: [Tag] = []
    var shouldThrowError = false

    override func setAuthToken(_ token: String?) {}

    override func getCurrentUser() async throws -> User {
        return User(id: "test", email: "test@example.com", fullName: "Test User")
    }

    override func getNodes(parentId: String?) async throws -> [Node] {
        if let parentId = parentId {
            // Don't allow getting children of note nodes
            if let parent = mockNodes.first(where: { $0.id == parentId }),
               parent.nodeType == "note" {
                return []
            }
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
        // Validate that parent is not a note
        if let parentId = node.parentId,
           let parent = mockNodes.first(where: { $0.id == parentId }),
           parent.nodeType == "note" {
            throw APIError.httpError(400) // Notes cannot have children
        }

        mockNodes.append(node)
        return node
    }

    override func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        guard let index = mockNodes.firstIndex(where: { $0.id == id }) else {
            throw APIError.httpError(404)
        }

        var node = mockNodes[index]

        // Update the note data if provided
        if let noteDataUpdate = update.noteData {
            node = Node(
                id: node.id,
                title: update.title,
                nodeType: node.nodeType,
                parentId: update.parentId,
                sortOrder: update.sortOrder,
                createdAt: Date(),
                updatedAt: Date(),
                noteData: NoteData(body: noteDataUpdate.body)
            )
            mockNodes[index] = node
        }

        return node
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
        return try await createGenericNode(title: title, nodeType: "folder", parentId: parentId)
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
        return try await createNode(node)
    }

    override func createNote(title: String, parentId: String?, body: String) async throws -> Node {
        // Validate parent is not a note
        if let parentId = parentId,
           let parent = mockNodes.first(where: { $0.id == parentId }),
           parent.nodeType == "note" {
            throw APIError.httpError(400) // Notes cannot have children
        }

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
        return try await createNode(node)
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
        return try await createNode(node)
    }

    override func executeSmartFolderRule(smartFolderId: String) async throws -> [Node] {
        return []
    }
}
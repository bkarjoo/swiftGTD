import XCTest
@testable import Models

final class NodeRoundTripTests: XCTestCase {
    
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!
    
    override func setUp() {
        super.setUp()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Task Node Round-Trip Tests
    
    func testRoundTrip_taskNode_shouldMaintainAllFields() throws {
        // Arrange - Load original
        let original = try FixtureLoader.loadFixture(named: "task_node.json", as: Node.self)
        
        // Act - Encode and decode
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert - Key fields match
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.nodeType, original.nodeType)
        XCTAssertEqual(decoded.parentId, original.parentId)
        XCTAssertEqual(decoded.sortOrder, original.sortOrder)
        XCTAssertEqual(decoded.taskData?.status, original.taskData?.status)
        XCTAssertEqual(decoded.taskData?.priority, original.taskData?.priority)
        XCTAssertEqual(decoded.taskData?.description, original.taskData?.description)
        XCTAssertEqual(decoded.taskData?.dueAt, original.taskData?.dueAt)
        XCTAssertEqual(decoded.taskData?.completedAt, original.taskData?.completedAt)
    }
    
    func testRoundTrip_completedTaskNode_shouldPreserveCompletionDate() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "task_node_completed.json", as: Node.self)
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert - Completed state preserved
        XCTAssertEqual(decoded.taskData?.status, "done")
        XCTAssertNotNil(decoded.taskData?.completedAt)
        XCTAssertEqual(decoded.taskData?.completedAt, original.taskData?.completedAt)
    }
    
    // MARK: - Folder Node Round-Trip Tests
    
    func testRoundTrip_folderNode_shouldMaintainHierarchy() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "folder_node.json", as: Node.self)
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.nodeType, "folder")
        XCTAssertNil(decoded.parentId) // Root folder
        XCTAssertEqual(decoded.childrenCount, original.childrenCount)
        XCTAssertNil(decoded.taskData)
        XCTAssertNil(decoded.noteData)
    }
    
    // MARK: - Note Node Round-Trip Tests
    
    func testRoundTrip_noteNode_shouldPreserveMarkdownBody() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "note_node.json", as: Node.self)
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert - Note body preserved
        XCTAssertEqual(decoded.noteData?.body, original.noteData?.body)
        XCTAssertTrue(decoded.noteData?.body?.contains("# Project Kickoff Meeting") ?? false)
        XCTAssertTrue(decoded.noteData?.body?.contains("## Attendees") ?? false)
    }
    
    // MARK: - Project Node Round-Trip Tests
    
    func testRoundTrip_projectNode_shouldPreserveTags() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "project_node.json", as: Node.self)
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert - Tags preserved
        XCTAssertEqual(decoded.tags.count, original.tags.count)
        XCTAssertEqual(decoded.tags.first?.name, original.tags.first?.name)
        XCTAssertEqual(decoded.tags.first?.color, original.tags.first?.color)
        XCTAssertEqual(decoded.isList, true)
    }
    
    // MARK: - Template Node Round-Trip Tests
    
    func testRoundTrip_templateNode_shouldPreserveMetadata() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "template_node.json", as: Node.self)
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert - Template data preserved
        XCTAssertEqual(decoded.templateData?.category, original.templateData?.category)
        XCTAssertEqual(decoded.templateData?.usageCount, original.templateData?.usageCount)
        XCTAssertEqual(decoded.templateData?.createContainer, original.templateData?.createContainer)
        XCTAssertNil(decoded.templateData?.targetNodeId)
    }
    
    // MARK: - Smart Folder Round-Trip Tests
    
    func testRoundTrip_smartFolderNode_shouldPreserveRules() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "smart_folder_node.json", as: Node.self)
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert - Smart folder data preserved
        XCTAssertEqual(decoded.smartFolderData?.ruleId, original.smartFolderData?.ruleId)
        XCTAssertEqual(decoded.smartFolderData?.autoRefresh, original.smartFolderData?.autoRefresh)
        XCTAssertEqual(decoded.smartFolderData?.description, original.smartFolderData?.description)
    }
    
    // MARK: - Array Round-Trip Tests
    
    func testRoundTrip_nodesArray_shouldPreserveAllNodes() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "nodes_array.json", as: [Node].self)
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode([Node].self, from: encoded)
        
        // Assert - All nodes preserved
        XCTAssertEqual(decoded.count, original.count)
        
        for (index, node) in decoded.enumerated() {
            XCTAssertEqual(node.id, original[index].id)
            XCTAssertEqual(node.title, original[index].title)
            XCTAssertEqual(node.nodeType, original[index].nodeType)
            XCTAssertEqual(node.parentId, original[index].parentId)
        }
    }
    
    // MARK: - Schema Stability Tests
    
    func testSchemaStability_encodeDecodeMultipleTimes_shouldRemainStable() throws {
        // Arrange
        let original = try FixtureLoader.loadFixture(named: "task_node.json", as: Node.self)
        
        // Act - Multiple round trips
        let encoded1 = try encoder.encode(original)
        let decoded1 = try decoder.decode(Node.self, from: encoded1)
        
        let encoded2 = try encoder.encode(decoded1)
        let decoded2 = try decoder.decode(Node.self, from: encoded2)
        
        let encoded3 = try encoder.encode(decoded2)
        let decoded3 = try decoder.decode(Node.self, from: encoded3)
        
        // Assert - Should be identical after multiple round trips
        XCTAssertEqual(decoded3.id, original.id)
        XCTAssertEqual(decoded3.title, original.title)
        XCTAssertEqual(decoded3.taskData?.status, original.taskData?.status)
        
        // Compare JSON strings for exact stability
        let _ = String(data: encoded1, encoding: .utf8)!
        let json2 = String(data: encoded2, encoding: .utf8)!
        let json3 = String(data: encoded3, encoding: .utf8)!
        
        // After first round trip, subsequent encodings should be identical
        XCTAssertEqual(json2, json3, "Schema should be stable after round trip")
    }
    
    // MARK: - Golden File Tests
    
    func testGoldenFile_taskNode_shouldMatchExpectedJSON() throws {
        // This test verifies the JSON structure matches our expected format
        let node = try FixtureLoader.loadFixture(named: "task_node.json", as: Node.self)
        
        let encoded = try encoder.encode(node)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        
        // Verify expected top-level keys exist
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["title"])
        XCTAssertNotNil(json["node_type"])
        XCTAssertNotNil(json["sort_order"])
        XCTAssertNotNil(json["task_data"])
        
        // Verify task_data structure
        if let taskData = json["task_data"] as? [String: Any] {
            XCTAssertNotNil(taskData["status"])
            XCTAssertNotNil(taskData["priority"])
        }
    }
    
    // MARK: - Edge Cases
    
    func testRoundTrip_nodeWithEmptyCollections_shouldPreserveEmptyState() throws {
        // Create a node with empty tags array
        let node = Node(
            id: "test-123",
            title: "Test Node",
            nodeType: "folder",
            parentId: nil,
            ownerId: "owner-123",
            createdAt: "2025-09-16T10:00:00Z",
            updatedAt: "2025-09-16T10:00:00Z",
            sortOrder: 1000,
            isList: false,
            childrenCount: 0,
            tags: [], // Empty tags
            taskData: nil,
            noteData: nil,
            templateData: nil,
            smartFolderData: nil
        )
        
        // Act
        let encoded = try encoder.encode(node)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.tags.count, 0)
        XCTAssertEqual(decoded.id, node.id)
        XCTAssertEqual(decoded.title, node.title)
    }
    
    func testRoundTrip_nodeWithNilOptionals_shouldPreserveNilState() throws {
        // Create a minimal node
        let node = Node(
            id: "minimal-123",
            title: "Minimal Node",
            nodeType: "folder",
            parentId: nil, // nil parent
            ownerId: "owner-123",
            createdAt: "2025-09-16T10:00:00Z",
            updatedAt: "2025-09-16T10:00:00Z",
            sortOrder: 0,
            isList: false,
            childrenCount: 0,
            tags: [],
            taskData: nil, // All special data nil
            noteData: nil,
            templateData: nil,
            smartFolderData: nil
        )
        
        // Act
        let encoded = try encoder.encode(node)
        let decoded = try decoder.decode(Node.self, from: encoded)
        
        // Assert - Nils remain nil
        XCTAssertNil(decoded.parentId)
        XCTAssertNil(decoded.taskData)
        XCTAssertNil(decoded.noteData)
        XCTAssertNil(decoded.templateData)
        XCTAssertNil(decoded.smartFolderData)
    }
}
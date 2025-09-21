import XCTest
@testable import Models

final class NodeDecodingTests: XCTestCase {
    
    // MARK: - Task Node Tests
    
    func testDecodeTaskNode_whenTodoStatus_shouldDecodeAllFields() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "task_node.json", as: Node.self)
        
        // Assert - Basic properties
        XCTAssertEqual(node.id, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(node.title, "Review quarterly report")
        XCTAssertEqual(node.nodeType, "task")
        XCTAssertEqual(node.parentId, "456e7890-e89b-12d3-a456-426614174000")
        XCTAssertEqual(node.ownerId, "0e212ca2-278d-4926-a24f-6f3b691eaf36")
        XCTAssertEqual(node.sortOrder, 1000)
        XCTAssertEqual(node.isList, false)
        XCTAssertEqual(node.childrenCount, 0)
        
        // Assert - Task data
        XCTAssertNotNil(node.taskData)
        XCTAssertEqual(node.taskData?.description, "Review and provide feedback on Q3 quarterly report")
        XCTAssertEqual(node.taskData?.status, "todo")
        XCTAssertEqual(node.taskData?.priority, "high")
        XCTAssertNotNil(node.taskData?.dueAt)
        XCTAssertNil(node.taskData?.earliestStartAt)
        XCTAssertNil(node.taskData?.completedAt)
        XCTAssertEqual(node.taskData?.archived, false)
        
        // Assert - Other data should be nil
        XCTAssertNil(node.noteData)
        XCTAssertNil(node.templateData)
        XCTAssertNil(node.smartFolderData)
    }
    
    func testDecodeTaskNode_whenCompletedStatus_shouldHaveCompletedAt() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "task_node_completed.json", as: Node.self)
        
        // Assert
        XCTAssertEqual(node.nodeType, "task")
        XCTAssertEqual(node.taskData?.status, "done")
        XCTAssertNotNil(node.taskData?.completedAt, "Completed task should have completedAt date")
        XCTAssertEqual(node.taskData?.priority, "medium")
    }
    
    // MARK: - Folder Node Tests
    
    func testDecodeFolderNode_shouldHaveCorrectTypeAndNoSpecialData() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "folder_node.json", as: Node.self)
        
        // Assert - Basic properties
        XCTAssertEqual(node.id, "456e7890-e89b-12d3-a456-426614174000")
        XCTAssertEqual(node.title, "Work Projects")
        XCTAssertEqual(node.nodeType, "folder")
        XCTAssertNil(node.parentId)
        XCTAssertEqual(node.childrenCount, 5)
        XCTAssertEqual(node.sortOrder, 1000)
        
        // Assert - All special data should be nil
        XCTAssertNil(node.taskData)
        XCTAssertNil(node.noteData)
        XCTAssertNil(node.templateData)
        XCTAssertNil(node.smartFolderData)
    }
    
    // MARK: - Note Node Tests
    
    func testDecodeNoteNode_shouldHaveNoteData() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "note_node.json", as: Node.self)
        
        // Assert - Basic properties
        XCTAssertEqual(node.nodeType, "note")
        XCTAssertEqual(node.title, "Meeting Notes - Project Kickoff")
        
        // Assert - Note data
        XCTAssertNotNil(node.noteData)
        XCTAssertTrue(node.noteData?.body?.contains("Project Kickoff Meeting") ?? false)
        XCTAssertTrue(node.noteData?.body?.contains("## Attendees") ?? false)
        XCTAssertTrue(node.noteData?.body?.contains("MVP scope defined") ?? false)
        
        // Assert - Other data should be nil
        XCTAssertNil(node.taskData)
        XCTAssertNil(node.templateData)
        XCTAssertNil(node.smartFolderData)
    }
    
    // MARK: - Project Node Tests
    
    func testDecodeProjectNode_shouldHaveCorrectTypeAndIsList() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "project_node.json", as: Node.self)
        
        // Assert - Basic properties
        XCTAssertEqual(node.nodeType, "project")
        XCTAssertEqual(node.title, "Q4 Product Launch")
        XCTAssertEqual(node.isList, true, "Projects are typically lists")
        XCTAssertEqual(node.childrenCount, 12)
        
        // Assert - Tags
        XCTAssertEqual(node.tags.count, 2)
        XCTAssertTrue(node.tags.contains { $0.name == "urgent" })
        XCTAssertTrue(node.tags.contains { $0.name == "q4-goals" })
        
        // Assert - All special data should be nil
        XCTAssertNil(node.taskData)
        XCTAssertNil(node.noteData)
        XCTAssertNil(node.templateData)
        XCTAssertNil(node.smartFolderData)
    }
    
    // MARK: - Area Node Tests
    
    func testDecodeAreaNode_shouldHaveCorrectType() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "area_node.json", as: Node.self)
        
        // Assert - Basic properties
        XCTAssertEqual(node.nodeType, "area")
        XCTAssertEqual(node.title, "Personal Development")
        XCTAssertNil(node.parentId, "Areas are typically top-level")
        XCTAssertEqual(node.childrenCount, 8)
        
        // Assert - Tags
        XCTAssertEqual(node.tags.count, 2)
        XCTAssertTrue(node.tags.contains { $0.name == "personal" })
        XCTAssertTrue(node.tags.contains { $0.name == "growth" })
        
        // Assert - All special data should be nil
        XCTAssertNil(node.taskData)
        XCTAssertNil(node.noteData)
        XCTAssertNil(node.templateData)
        XCTAssertNil(node.smartFolderData)
    }
    
    // MARK: - Template Node Tests
    
    func testDecodeTemplateNode_shouldHaveTemplateData() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "template_node.json", as: Node.self)
        
        // Assert - Basic properties
        XCTAssertEqual(node.nodeType, "template")
        XCTAssertEqual(node.title, "Weekly Review Template")
        
        // Assert - Template data
        XCTAssertNotNil(node.templateData)
        XCTAssertEqual(node.templateData?.category, "review")
        XCTAssertEqual(node.templateData?.usageCount, 5)
        XCTAssertNil(node.templateData?.targetNodeId)
        XCTAssertEqual(node.templateData?.createContainer, true)
        
        // Assert - Other data should be nil
        XCTAssertNil(node.taskData)
        XCTAssertNil(node.noteData)
        XCTAssertNil(node.smartFolderData)
    }
    
    // MARK: - Smart Folder Node Tests
    
    func testDecodeSmartFolderNode_shouldHaveSmartFolderData() throws {
        // Arrange & Act
        let node = try FixtureLoader.loadFixture(named: "smart_folder_node.json", as: Node.self)
        
        // Assert - Basic properties
        XCTAssertEqual(node.nodeType, "smart_folder")
        XCTAssertEqual(node.title, "Overdue Tasks")
        XCTAssertEqual(node.childrenCount, 0, "Smart folders don't have real children")
        
        // Assert - Smart folder data
        XCTAssertNotNil(node.smartFolderData)
        XCTAssertEqual(node.smartFolderData?.ruleId, "overdue-tasks-rule")
        XCTAssertEqual(node.smartFolderData?.autoRefresh, true)
        XCTAssertEqual(node.smartFolderData?.description, "Shows all tasks that are overdue")
        
        // Assert - Other data should be nil
        XCTAssertNil(node.taskData)
        XCTAssertNil(node.noteData)
        XCTAssertNil(node.templateData)
    }
    
    // MARK: - Coding Keys Tests
    
    func testNodeCodingKeys_shouldMapCorrectly() throws {
        // This test verifies that snake_case JSON keys map to camelCase properties
        let node = try FixtureLoader.loadFixture(named: "task_node.json", as: Node.self)
        
        // These would fail if coding keys weren't mapped correctly
        XCTAssertNotNil(node.parentId) // parent_id in JSON
        XCTAssertNotNil(node.ownerId) // owner_id in JSON
        XCTAssertNotNil(node.createdAt) // created_at in JSON
        XCTAssertNotNil(node.updatedAt) // updated_at in JSON
        XCTAssertEqual(node.sortOrder, 1000) // sort_order in JSON
        XCTAssertEqual(node.childrenCount, 0) // children_count in JSON
        XCTAssertNotNil(node.taskData) // task_data in JSON
    }
    
    // MARK: - Optional Fields Tests
    
    func testNodeOptionalFields_whenMissing_shouldBeNil() throws {
        // Test that optional fields decode as nil when not present
        let folder = try FixtureLoader.loadFixture(named: "folder_node.json", as: Node.self)
        
        // Optional fields that should be nil for a folder
        XCTAssertNil(folder.taskData)
        XCTAssertNil(folder.noteData)
        XCTAssertNil(folder.templateData)
        XCTAssertNil(folder.smartFolderData)
        
        // Parent ID is optional and nil for root nodes
        XCTAssertNil(folder.parentId)
    }
    
    // MARK: - Array Decoding Tests
    
    func testDecodeNodesArray_shouldDecodeAllTypes() throws {
        // Arrange & Act
        let nodes = try FixtureLoader.loadFixture(named: "nodes_array.json", as: [Node].self)
        
        // Assert
        XCTAssertEqual(nodes.count, 4)
        
        // Verify different types in the array
        XCTAssertEqual(nodes[0].nodeType, "folder")
        XCTAssertEqual(nodes[1].nodeType, "task")
        XCTAssertEqual(nodes[2].nodeType, "task")
        XCTAssertEqual(nodes[3].nodeType, "note")
        
        // Verify parent-child relationships
        XCTAssertNil(nodes[0].parentId) // Folder is root
        XCTAssertEqual(nodes[1].parentId, nodes[0].id) // Task's parent is the folder
        XCTAssertEqual(nodes[2].parentId, nodes[0].id) // Second task's parent is the folder
        XCTAssertEqual(nodes[3].parentId, nodes[0].id) // Note's parent is the folder
    }
}
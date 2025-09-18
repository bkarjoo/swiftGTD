import XCTest
@testable import Models

final class FixtureLoaderTests: XCTestCase {
    
    func testLoadFixture_whenValidFile_shouldReturnData() throws {
        // Act
        let data = try FixtureLoader.loadFixture(named: "task_node.json")
        
        // Assert
        XCTAssertNotNil(data)
        XCTAssertTrue(data.count > 0, "Fixture data should not be empty")
    }
    
    func testLoadFixture_whenDecodingTaskNode_shouldDecodeCorrectly() throws {
        // Act
        let node = try FixtureLoader.loadFixture(named: "task_node.json", as: Node.self)
        
        // Assert
        XCTAssertEqual(node.id, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(node.title, "Review quarterly report")
        XCTAssertEqual(node.nodeType, "task")
        XCTAssertNotNil(node.taskData)
        XCTAssertEqual(node.taskData?.status, "todo")
        XCTAssertEqual(node.taskData?.priority, "high")
        XCTAssertNil(node.taskData?.completedAt)
    }
    
    func testLoadFixture_whenDecodingCompletedTask_shouldHaveCompletedAt() throws {
        // Act
        let node = try FixtureLoader.loadFixture(named: "task_node_completed.json", as: Node.self)
        
        // Assert
        XCTAssertEqual(node.title, "Submit expense report")
        XCTAssertEqual(node.taskData?.status, "done")
        XCTAssertNotNil(node.taskData?.completedAt)
    }
    
    func testLoadFixture_whenDecodingFolder_shouldHaveNoTaskData() throws {
        // Act
        let node = try FixtureLoader.loadFixture(named: "folder_node.json", as: Node.self)
        
        // Assert
        XCTAssertEqual(node.nodeType, "folder")
        XCTAssertNil(node.taskData)
        XCTAssertNil(node.noteData)
        XCTAssertEqual(node.childrenCount, 5)
    }
    
    func testLoadFixture_whenDecodingNote_shouldHaveNoteData() throws {
        // Act
        let node = try FixtureLoader.loadFixture(named: "note_node.json", as: Node.self)
        
        // Assert
        XCTAssertEqual(node.nodeType, "note")
        XCTAssertNotNil(node.noteData)
        XCTAssertTrue(node.noteData?.body?.contains("Project Kickoff Meeting") ?? false)
        XCTAssertNil(node.taskData)
    }
    
    func testLoadFixture_whenDecodingNodesArray_shouldDecodeAll() throws {
        // Act
        let nodes = try FixtureLoader.loadFixture(named: "nodes_array.json", as: [Node].self)
        
        // Assert
        XCTAssertEqual(nodes.count, 4)
        XCTAssertEqual(nodes[0].nodeType, "folder")
        XCTAssertEqual(nodes[1].nodeType, "task")
        XCTAssertEqual(nodes[2].nodeType, "task")
        XCTAssertEqual(nodes[3].nodeType, "note")
    }
}
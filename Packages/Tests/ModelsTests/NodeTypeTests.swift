import XCTest
import Models

final class NodeTypeTests: XCTestCase {
    func testDisplayNameMappings() {
        XCTAssertEqual(NodeType.task.displayName, "Task")
        XCTAssertEqual(NodeType.project.displayName, "Project")
        XCTAssertEqual(NodeType.area.displayName, "Area")
        XCTAssertEqual(NodeType.note.displayName, "Note")
        XCTAssertEqual(NodeType.folder.displayName, "Folder")
    }

    func testSystemImageMappings() {
        XCTAssertEqual(NodeType.task.systemImage, "checkmark.circle")
        XCTAssertEqual(NodeType.project.systemImage, "folder")
        XCTAssertEqual(NodeType.area.systemImage, "tray.full")
        XCTAssertEqual(NodeType.note.systemImage, "note.text")
        XCTAssertEqual(NodeType.folder.systemImage, "folder")
    }
}


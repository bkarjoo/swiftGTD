import XCTest
import Models

final class NodeCodableTests: XCTestCase {
    func testDecodeTaskNodeWithNilCompletedAt() throws {
        let json = """
        {
          "id": "n1",
          "title": "Test Task",
          "node_type": "task",
          "parent_id": null,
          "owner_id": "u1",
          "created_at": "2024-01-01T00:00:00Z",
          "updated_at": "2024-01-01T00:00:00Z",
          "sort_order": 0,
          "is_list": false,
          "children_count": 0,
          "tags": [],
          "task_data": {
            "description": "desc",
            "status": "todo",
            "priority": null,
            "due_at": null,
            "earliest_start_at": null,
            "completed_at": null,
            "archived": false
          },
          "note_data": null
        }
        """.data(using: .utf8)!

        let node = try JSONDecoder().decode(Node.self, from: json)
        XCTAssertEqual(node.id, "n1")
        XCTAssertEqual(node.nodeType, "task")
        XCTAssertEqual(node.childrenCount, 0)
        XCTAssertNotNil(node.taskData)
        XCTAssertNil(node.taskData?.completedAt)
    }

    func testDecodeTaskNodeWithCompletedAt() throws {
        let json = """
        {
          "id": "n2",
          "title": "Done Task",
          "node_type": "task",
          "parent_id": "p1",
          "owner_id": "u1",
          "created_at": "2024-01-02T00:00:00Z",
          "updated_at": "2024-01-02T00:00:00Z",
          "sort_order": 1,
          "is_list": false,
          "children_count": 0,
          "tags": [],
          "task_data": {
            "description": null,
            "status": "done",
            "priority": null,
            "due_at": null,
            "earliest_start_at": null,
            "completed_at": "2024-01-02T03:04:05Z",
            "archived": false
          },
          "note_data": null
        }
        """.data(using: .utf8)!

        let node = try JSONDecoder().decode(Node.self, from: json)
        XCTAssertEqual(node.id, "n2")
        XCTAssertEqual(node.parentId, "p1")
        XCTAssertEqual(node.taskData?.status, "done")
        XCTAssertEqual(node.taskData?.completedAt, "2024-01-02T03:04:05Z")
    }
}


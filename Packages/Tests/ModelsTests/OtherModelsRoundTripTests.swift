import XCTest
@testable import Models

final class OtherModelsRoundTripTests: XCTestCase {
    
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
    
    // MARK: - Tag Round-Trip Tests
    
    func testRoundTrip_tag_shouldMaintainAllFields() throws {
        // Arrange
        let original = Tag(
            id: "tag-123",
            name: "important",
            color: "#FF5733",
            description: "Important items that need attention",
            createdAt: "2025-09-01T10:00:00.000000+00:00"
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Tag.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.color, original.color)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
    }
    
    func testRoundTrip_tag_withNilOptionals_shouldPreserveNils() throws {
        // Arrange - Tag with nil optionals
        let original = Tag(
            id: "tag-456",
            name: "simple",
            color: nil,
            description: nil,
            createdAt: nil
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Tag.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertNil(decoded.color)
        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.createdAt)
    }
    
    // MARK: - User Round-Trip Tests
    
    func testRoundTrip_user_shouldMaintainAllFields() throws {
        // Arrange
        let original = User(
            id: "user-123",
            email: "test@example.com",
            fullName: "Test User"
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(User.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.email, original.email)
        XCTAssertEqual(decoded.fullName, original.fullName)
    }
    
    func testRoundTrip_user_withNilFullName_shouldPreserveNil() throws {
        // Arrange
        let original = User(
            id: "user-456",
            email: "minimal@example.com",
            fullName: nil
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(User.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.email, original.email)
        XCTAssertNil(decoded.fullName)
    }
    
    // MARK: - LoginRequest Round-Trip Tests
    
    func testRoundTrip_loginRequest_shouldMaintainCredentials() throws {
        // Arrange
        let original = LoginRequest(
            email: "user@example.com",
            password: "securePassword123"
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(LoginRequest.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.email, original.email)
        XCTAssertEqual(decoded.password, original.password)
    }
    
    // MARK: - SignupRequest Round-Trip Tests
    
    func testRoundTrip_signupRequest_shouldMaintainAllFields() throws {
        // Arrange
        let original = SignupRequest(
            email: "newuser@example.com",
            password: "newPassword123",
            username: "newuser"
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(SignupRequest.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.email, original.email)
        XCTAssertEqual(decoded.password, original.password)
        XCTAssertEqual(decoded.username, original.username)
    }
    
    // MARK: - AuthResponse Round-Trip Tests
    
    func testRoundTrip_authResponse_shouldMaintainTokens() throws {
        // Arrange
        let original = AuthResponse(
            accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.example.token",
            tokenType: "Bearer"
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AuthResponse.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.accessToken, original.accessToken)
        XCTAssertEqual(decoded.tokenType, original.tokenType)
    }
    
    // MARK: - NodeUpdate Round-Trip Tests
    
    func testRoundTrip_nodeUpdate_shouldMaintainUpdateFields() throws {
        // Arrange
        let taskUpdate = TaskDataUpdate(
            status: "done",
            priority: "high",
            description: "Updated description",
            dueAt: "2025-09-20T17:00:00Z",
            earliestStartAt: nil,
            completedAt: "2025-09-15T10:00:00Z",
            archived: false
        )
        
        let original = NodeUpdate(
            title: "Updated Title",
            parentId: "parent-456",
            sortOrder: 2000,
            taskData: taskUpdate,
            noteData: nil
        )
        
        // Act - NodeUpdate is Encodable only, verify JSON structure
        let encoded = try encoder.encode(original)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        
        // Assert - verify JSON structure
        XCTAssertEqual(json["title"] as? String, original.title)
        XCTAssertEqual(json["parent_id"] as? String, original.parentId)
        XCTAssertEqual(json["sort_order"] as? Int, original.sortOrder)
        
        if let taskData = json["task_data"] as? [String: Any] {
            XCTAssertEqual(taskData["status"] as? String, original.taskData?.status)
            XCTAssertEqual(taskData["priority"] as? String, original.taskData?.priority)
            XCTAssertEqual(taskData["completed_at"] as? String, original.taskData?.completedAt)
        }
    }
    
    // MARK: - Rule Round-Trip Tests
    
    func testRoundTrip_rule_shouldMaintainAllFields() throws {
        // Arrange
        let original = Rule(
            id: "rule-123",
            name: "Overdue Tasks",
            description: "Find all overdue tasks",
            isPublic: false,
            isSystem: false,
            ownerId: "owner-123",
            createdAt: "2025-08-01T10:00:00Z",
            updatedAt: "2025-09-15T12:00:00Z"
        )
        
        // Act
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Rule.self, from: encoded)
        
        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.isPublic, original.isPublic)
        XCTAssertEqual(decoded.isSystem, original.isSystem)
        XCTAssertEqual(decoded.ownerId, original.ownerId)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.updatedAt, original.updatedAt)
    }
    
    // MARK: - Schema Stability for All Models
    
    func testSchemaStability_allModels_shouldRemainStableAfterMultipleRoundTrips() throws {
        // Test Tag stability
        let tag = Tag(id: "stable-tag", name: "test", color: "#000000", description: "Test", createdAt: nil)
        let tagData1 = try encoder.encode(tag)
        let tagDecoded1 = try decoder.decode(Tag.self, from: tagData1)
        let tagData2 = try encoder.encode(tagDecoded1)
        XCTAssertEqual(tagData1, tagData2, "Tag should be stable after round trip")
        
        // Test User stability
        let user = User(id: "stable-user", email: "test@test.com", fullName: "Test User")
        let userData1 = try encoder.encode(user)
        let userDecoded1 = try decoder.decode(User.self, from: userData1)
        let userData2 = try encoder.encode(userDecoded1)
        XCTAssertEqual(userData1, userData2, "User should be stable after round trip")
        
        // Test LoginRequest stability
        let login = LoginRequest(email: "test@test.com", password: "password")
        let loginData1 = try encoder.encode(login)
        let loginDecoded1 = try decoder.decode(LoginRequest.self, from: loginData1)
        let loginData2 = try encoder.encode(loginDecoded1)
        XCTAssertEqual(loginData1, loginData2, "LoginRequest should be stable after round trip")
    }
}
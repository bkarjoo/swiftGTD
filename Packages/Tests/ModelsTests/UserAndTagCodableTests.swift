import XCTest
import Models

final class UserAndTagCodableTests: XCTestCase {
    func testAuthResponseDecoding() throws {
        let json = """
        { "access_token": "abc123", "token_type": "bearer" }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(resp.accessToken, "abc123")
        XCTAssertEqual(resp.tokenType, "bearer")
    }

    func testLoginRequestEncoding() throws {
        let req = LoginRequest(email: "a@b.com", password: "pw")
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["email"] as? String, "a@b.com")
        XCTAssertEqual(obj?["password"] as? String, "pw")
    }

    func testTagDecodingCodingKeys() throws {
        let json = """
        {
          "id": "t1",
          "name": "urgent",
          "color": "#FF0000",
          "description": "",
          "created_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let tag = try JSONDecoder().decode(Tag.self, from: json)
        XCTAssertEqual(tag.id, "t1")
        XCTAssertEqual(tag.name, "urgent")
        XCTAssertEqual(tag.color, "#FF0000")
        XCTAssertEqual(tag.createdAt, "2024-01-01T00:00:00Z")
    }
}


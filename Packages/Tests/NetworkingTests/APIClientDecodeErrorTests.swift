import XCTest
import Foundation
@testable import Networking
@testable import Models
@testable import Core  // For KeychainManager

/// Tests for APIClient decode error handling with malformed JSON
final class APIClientDecodeErrorTests: XCTestCase {
    
    // MARK: - Mock URLProtocol for Malformed Responses
    
    class MalformedResponseURLProtocol: URLProtocol {
        static var mockResponseData: Data?
        static var mockStatusCode: Int = 200
        
        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }
        
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }
        
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: MalformedResponseURLProtocol.mockStatusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            
            if let data = MalformedResponseURLProtocol.mockResponseData {
                client?.urlProtocol(self, didLoad: data)
            }
            
            client?.urlProtocolDidFinishLoading(self)
        }
        
        override func stopLoading() {}
    }
    
    // MARK: - Test Helpers
    
    override func setUp() {
        super.setUp()
        MalformedResponseURLProtocol.mockResponseData = nil
        MalformedResponseURLProtocol.mockStatusCode = 200
        _ = KeychainManager.shared.deleteToken()  // Clear any existing token
    }
    
    // MARK: - Malformed JSON Tests
    
    func testAPIClient_with200AndMalformedJSON_throwsDecodingError() async throws {
        // Arrange - Completely invalid JSON
        MalformedResponseURLProtocol.mockResponseData = """
            {this is not valid json at all}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNodes()
            XCTFail("Should throw DecodingError for malformed JSON")
        } catch is DecodingError {
            // Expected - malformed JSON should throw DecodingError
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    func testAPIClient_with200AndIncompleteJSON_throwsDecodingError() async throws {
        // Arrange - Incomplete JSON (missing closing brace)
        MalformedResponseURLProtocol.mockResponseData = """
            {"id": "test-123", "title": "Test Node"
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNode(id: "test-123")
            XCTFail("Should throw DecodingError for incomplete JSON")
        } catch is DecodingError {
            // Expected
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    func testAPIClient_with200AndWrongTypeJSON_throwsDecodingError() async throws {
        // Arrange - Valid JSON but wrong type (string instead of array)
        MalformedResponseURLProtocol.mockResponseData = """
            "This is a string, not an array of nodes"
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNodes()
            XCTFail("Should throw DecodingError for wrong type")
        } catch is DecodingError {
            // Expected
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    func testAPIClient_with200AndMissingRequiredFields_throwsDecodingError() async throws {
        // Arrange - Valid JSON but missing required fields for User
        MalformedResponseURLProtocol.mockResponseData = """
            {"id": "user-123"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getCurrentUser()
            XCTFail("Should throw DecodingError for missing required fields")
        } catch is DecodingError {
            // Expected - User requires email and fullName
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    func testAPIClient_with200AndWrongFieldTypes_throwsDecodingError() async throws {
        // Arrange - Node with wrong field types (string for sort_order instead of int)
        MalformedResponseURLProtocol.mockResponseData = """
            {
                "id": "node-123",
                "title": "Test Node",
                "node_type": "folder",
                "parent_id": null,
                "owner_id": "user-123",
                "sort_order": "not-a-number",
                "created_at": "2025-09-16T10:00:00Z",
                "updated_at": "2025-09-16T10:00:00Z",
                "is_list": false,
                "children_count": 0,
                "tags": []
            }
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNode(id: "node-123")
            XCTFail("Should throw DecodingError for wrong field types")
        } catch is DecodingError {
            // Expected - sort_order must be an integer
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    func testAPIClient_with200AndNullInsteadOfArray_throwsDecodingError() async throws {
        // Arrange - null instead of array
        MalformedResponseURLProtocol.mockResponseData = """
            null
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNodes()
            XCTFail("Should throw DecodingError for null instead of array")
        } catch is DecodingError {
            // Expected
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    func testAPIClient_with200AndEmptyResponse_throwsDecodingError() async throws {
        // Arrange - Completely empty response
        MalformedResponseURLProtocol.mockResponseData = Data()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNodes()
            XCTFail("Should throw DecodingError for empty response")
        } catch is DecodingError {
            // Expected - empty data is not valid JSON
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    func testAPIClient_with200AndHTMLResponse_throwsDecodingError() async throws {
        // Arrange - HTML instead of JSON (common error page scenario)
        MalformedResponseURLProtocol.mockResponseData = """
            <!DOCTYPE html>
            <html>
            <head><title>Error</title></head>
            <body><h1>500 Internal Server Error</h1></body>
            </html>
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNodes()
            XCTFail("Should throw DecodingError for HTML response")
        } catch is DecodingError {
            // Expected - HTML is not JSON
            XCTAssertTrue(true, "Correctly threw DecodingError")
        } catch {
            XCTFail("Should throw DecodingError, but got: \(error)")
        }
    }
    
    // MARK: - Valid Response Tests (Should NOT throw)
    
    func testAPIClient_with200AndValidEmptyArray_doesNotThrow() async throws {
        // Arrange - Valid empty array
        MalformedResponseURLProtocol.mockResponseData = "[]".data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert - Should not throw
        let nodes = try await apiClient.getNodes()
        XCTAssertEqual(nodes.count, 0, "Should successfully decode empty array")
    }
    
    func testAPIClient_with200AndValidUser_doesNotThrow() async throws {
        // Arrange - Valid User JSON
        MalformedResponseURLProtocol.mockResponseData = """
            {
                "id": "user-123",
                "email": "test@example.com",
                "full_name": "Test User"
            }
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert - Should not throw
        let user = try await apiClient.getCurrentUser()
        XCTAssertEqual(user.id, "user-123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.fullName, "Test User")
    }
    
    // MARK: - Error Recovery Tests
    
    func testAPIClient_afterDecodingError_canMakeSuccessfulRequest() async throws {
        // Arrange - First request with malformed JSON
        MalformedResponseURLProtocol.mockResponseData = "{invalid json}".data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act - First request should fail
        do {
            _ = try await apiClient.getNodes()
            XCTFail("First request should throw DecodingError")
        } catch is DecodingError {
            // Expected
        }
        
        // Arrange - Second request with valid JSON
        MalformedResponseURLProtocol.mockResponseData = "[]".data(using: .utf8)
        
        // Act & Assert - Second request should succeed
        let nodes = try await apiClient.getNodes()
        XCTAssertEqual(nodes.count, 0, "Should recover and successfully decode after error")
    }
    
    // MARK: - Edge Cases
    
    func testAPIClient_with200AndUnicodeJSON_decodesCorrectly() async throws {
        // Arrange - Valid JSON with Unicode characters
        MalformedResponseURLProtocol.mockResponseData = """
            {
                "id": "user-123",
                "email": "test@example.com",
                "full_name": "Test User 🚀 测试用户"
            }
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert - Should handle Unicode correctly
        let user = try await apiClient.getCurrentUser()
        XCTAssertEqual(user.fullName, "Test User 🚀 测试用户")
    }
}
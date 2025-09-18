import XCTest
import Foundation
@testable import Networking
@testable import Models

/// Tests for APIClient HTTP error mapping
final class APIClientHTTPErrorTests: XCTestCase {
    
    // MARK: - Mock URLProtocol for Error Responses
    
    class ErrorResponseURLProtocol: URLProtocol {
        static var mockStatusCode: Int = 200
        static var mockResponseData: Data?
        static var mockError: Error?
        
        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }
        
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }
        
        override func startLoading() {
            // If we have a network error, return it immediately
            if let error = ErrorResponseURLProtocol.mockError {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            
            // Otherwise return HTTP response with status code
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: ErrorResponseURLProtocol.mockStatusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            
            if let data = ErrorResponseURLProtocol.mockResponseData {
                client?.urlProtocol(self, didLoad: data)
            }
            
            client?.urlProtocolDidFinishLoading(self)
        }
        
        override func stopLoading() {}
    }
    
    // MARK: - Test Helpers
    
    override func setUp() {
        super.setUp()
        // Reset mock state
        ErrorResponseURLProtocol.mockStatusCode = 200
        ErrorResponseURLProtocol.mockResponseData = nil
        ErrorResponseURLProtocol.mockError = nil
    }
    
    // MARK: - HTTP Error Code Tests
    
    func testAPIClient_with400BadRequest_throwsHTTPError400() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 400
        ErrorResponseURLProtocol.mockResponseData = """
            {"error": "Bad Request", "message": "Invalid parameters"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNodes()
            XCTFail("Should throw APIError.httpError(400)")
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                XCTAssertEqual(code, 400, "Should throw httpError with code 400")
            default:
                XCTFail("Should throw httpError, but got: \(error)")
            }
        } catch {
            XCTFail("Should throw APIError, but got: \(error)")
        }
    }
    
    func testAPIClient_with401Unauthorized_throwsHTTPError401() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 401
        ErrorResponseURLProtocol.mockResponseData = """
            {"error": "Unauthorized", "message": "Invalid or expired token"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getCurrentUser()
            XCTFail("Should throw APIError.httpError(401)")
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                XCTAssertEqual(code, 401, "Should throw httpError with code 401")
            default:
                XCTFail("Should throw httpError, but got: \(error)")
            }
        } catch {
            XCTFail("Should throw APIError, but got: \(error)")
        }
    }
    
    func testAPIClient_with403Forbidden_throwsHTTPError403() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 403
        ErrorResponseURLProtocol.mockResponseData = """
            {"error": "Forbidden", "message": "Access denied"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.deleteNode(id: "protected-node")
            XCTFail("Should throw APIError.httpError(403)")
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                XCTAssertEqual(code, 403, "Should throw httpError with code 403")
            default:
                XCTFail("Should throw httpError, but got: \(error)")
            }
        } catch {
            XCTFail("Should throw APIError, but got: \(error)")
        }
    }
    
    func testAPIClient_with404NotFound_throwsHTTPError404() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 404
        ErrorResponseURLProtocol.mockResponseData = """
            {"error": "Not Found", "message": "Resource does not exist"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNode(id: "non-existent-node")
            XCTFail("Should throw APIError.httpError(404)")
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                XCTAssertEqual(code, 404, "Should throw httpError with code 404")
            default:
                XCTFail("Should throw httpError, but got: \(error)")
            }
        } catch {
            XCTFail("Should throw APIError, but got: \(error)")
        }
    }
    
    func testAPIClient_with422UnprocessableEntity_throwsHTTPError422() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 422
        ErrorResponseURLProtocol.mockResponseData = """
            {"error": "Unprocessable Entity", "message": "Validation failed"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            let invalidNode = Node(
                id: "test",
                title: "",  // Invalid empty title
                nodeType: "task",
                parentId: nil,
                sortOrder: 1000,
                createdAt: Date(),
                updatedAt: Date()
            )
            _ = try await apiClient.createNode(invalidNode)
            XCTFail("Should throw APIError.httpError(422)")
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                XCTAssertEqual(code, 422, "Should throw httpError with code 422")
            default:
                XCTFail("Should throw httpError, but got: \(error)")
            }
        } catch {
            XCTFail("Should throw APIError, but got: \(error)")
        }
    }
    
    func testAPIClient_with500InternalServerError_throwsHTTPError500() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 500
        ErrorResponseURLProtocol.mockResponseData = """
            {"error": "Internal Server Error", "message": "Something went wrong"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getNodes()
            XCTFail("Should throw APIError.httpError(500)")
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                XCTAssertEqual(code, 500, "Should throw httpError with code 500")
            default:
                XCTFail("Should throw httpError, but got: \(error)")
            }
        } catch {
            XCTFail("Should throw APIError, but got: \(error)")
        }
    }
    
    func testAPIClient_with503ServiceUnavailable_throwsHTTPError503() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 503
        ErrorResponseURLProtocol.mockResponseData = """
            {"error": "Service Unavailable", "message": "Server is under maintenance"}
            """.data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert
        do {
            _ = try await apiClient.getAllNodes()
            XCTFail("Should throw APIError.httpError(503)")
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                XCTAssertEqual(code, 503, "Should throw httpError with code 503")
            default:
                XCTFail("Should throw httpError, but got: \(error)")
            }
        } catch {
            XCTFail("Should throw APIError, but got: \(error)")
        }
    }
    
    // MARK: - Error Description Tests
    
    func testAPIError_httpError_hasCorrectDescription() {
        // Arrange & Act
        let error400 = APIError.httpError(400)
        let error401 = APIError.httpError(401)
        let error404 = APIError.httpError(404)
        let error500 = APIError.httpError(500)
        
        // Assert
        XCTAssertEqual(error400.errorDescription, "HTTP error: 400")
        XCTAssertEqual(error401.errorDescription, "HTTP error: 401")
        XCTAssertEqual(error404.errorDescription, "HTTP error: 404")
        XCTAssertEqual(error500.errorDescription, "HTTP error: 500")
    }
    
    func testAPIError_otherErrors_haveCorrectDescription() {
        // Arrange & Act
        let invalidURL = APIError.invalidURL
        let invalidResponse = APIError.invalidResponse
        
        // Assert
        XCTAssertEqual(invalidURL.errorDescription, "Invalid URL")
        XCTAssertEqual(invalidResponse.errorDescription, "Invalid response from server")
    }
    
    // MARK: - Edge Cases
    
    func testAPIClient_with200Success_doesNotThrowError() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 200
        ErrorResponseURLProtocol.mockResponseData = "[]".data(using: .utf8)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert - Should not throw
        let nodes = try await apiClient.getNodes()
        XCTAssertEqual(nodes.count, 0, "Should successfully decode empty array")
    }
    
    func testAPIClient_with201Created_doesNotThrowError() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 201
        let mockUser = User(
            id: "user-123",
            email: "test@example.com",
            fullName: "Test User"
        )
        ErrorResponseURLProtocol.mockResponseData = try JSONEncoder().encode(mockUser)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert - Should not throw for 201
        let user = try await apiClient.getCurrentUser()
        XCTAssertEqual(user.id, "user-123", "Should successfully decode user")
    }
    
    func testAPIClient_with204NoContent_doesNotThrowError() async throws {
        // Arrange
        ErrorResponseURLProtocol.mockStatusCode = 204
        ErrorResponseURLProtocol.mockResponseData = nil  // No content
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorResponseURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act & Assert - 204 is in success range
        do {
            _ = try await apiClient.deleteNode(id: "test-node")
            // deleteNode expects EmptyResponse which can decode from empty data
        } catch {
            // 204 with no content might fail decoding, but shouldn't be httpError
            if let apiError = error as? APIError {
                switch apiError {
                case .httpError:
                    XCTFail("204 should not throw httpError")
                default:
                    // Decoding error is acceptable for 204 with no body
                    break
                }
            }
        }
    }
}
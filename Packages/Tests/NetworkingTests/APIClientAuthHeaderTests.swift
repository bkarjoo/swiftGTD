import XCTest
import Foundation
@testable import Networking
@testable import Models
@testable import Core  // For KeychainManager

/// Tests for APIClient Authorization header handling
final class APIClientAuthHeaderTests: XCTestCase {
    
    // MARK: - Mock URLProtocol for Header Capture
    
    class HeaderCapturingURLProtocol: URLProtocol {
        static var capturedHeaders: [String: String]?
        static var mockResponse: (HTTPURLResponse, Data)?
        
        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }
        
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }
        
        override func startLoading() {
            // Capture headers
            HeaderCapturingURLProtocol.capturedHeaders = request.allHTTPHeaderFields
            
            // Return mock response
            if let (response, data) = HeaderCapturingURLProtocol.mockResponse {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            }
        }
        
        override func stopLoading() {}
    }
    
    // MARK: - Test Helpers
    
    override func setUp() {
        super.setUp()
        // Clear any existing token from both UserDefaults and Keychain
        UserDefaults.standard.removeObject(forKey: "auth_token")
        _ = KeychainManager.shared.deleteToken()  // Clear Keychain token
        HeaderCapturingURLProtocol.capturedHeaders = nil
    }
    
    override func tearDown() {
        // Clean up
        UserDefaults.standard.removeObject(forKey: "auth_token")
        _ = KeychainManager.shared.deleteToken()  // Clear Keychain token
        HeaderCapturingURLProtocol.capturedHeaders = nil
        super.tearDown()
    }
    
    // MARK: - Auth Header Tests
    
    func testAPIClient_withAuthToken_includesBearerHeader() async throws {
        // Arrange
        let testToken = "test-token-12345"
        let mockUser = User(
            id: "user-123",
            email: "test@example.com",
            fullName: "Test User"
        )
        
        // Set up mock response
        HeaderCapturingURLProtocol.mockResponse = (
            HTTPURLResponse(
                url: URL(string: "http://test.com/auth/me")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            try JSONEncoder().encode(mockUser)
        )
        
        // Configure session with mock
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeaderCapturingURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // Create APIClient and set token
        let apiClient = APIClient(urlSession: mockSession)
        apiClient.setAuthToken(testToken)
        
        // Act - Make a request
        _ = try await apiClient.getCurrentUser()
        
        // Assert - Check Authorization header
        XCTAssertNotNil(HeaderCapturingURLProtocol.capturedHeaders)
        if let headers = HeaderCapturingURLProtocol.capturedHeaders {
            XCTAssertEqual(headers["Authorization"], "Bearer \(testToken)",
                          "Authorization header should contain Bearer token")
            XCTAssertEqual(headers["Content-Type"], "application/json",
                          "Content-Type should be application/json")
        }
    }
    
    func testAPIClient_withoutAuthToken_omitsAuthorizationHeader() async throws {
        // Arrange - No token set
        let mockNodes: [Node] = []
        
        // Set up mock response
        HeaderCapturingURLProtocol.mockResponse = (
            HTTPURLResponse(
                url: URL(string: "http://test.com/nodes")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            try JSONEncoder().encode(mockNodes)
        )
        
        // Configure session with mock
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeaderCapturingURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // Create APIClient without setting token
        let apiClient = APIClient(urlSession: mockSession)
        
        // Act - Make a request
        _ = try await apiClient.getNodes()
        
        // Assert - No Authorization header
        XCTAssertNotNil(HeaderCapturingURLProtocol.capturedHeaders)
        if let headers = HeaderCapturingURLProtocol.capturedHeaders {
            XCTAssertNil(headers["Authorization"],
                        "Authorization header should not be present without token")
            XCTAssertEqual(headers["Content-Type"], "application/json",
                          "Content-Type should still be present")
        }
    }
    
    func testAPIClient_afterClearingToken_removesAuthorizationHeader() async throws {
        // Arrange - Set then clear token
        let testToken = "temp-token-789"
        let mockNodes: [Node] = []
        
        // Set up mock response
        HeaderCapturingURLProtocol.mockResponse = (
            HTTPURLResponse(
                url: URL(string: "http://test.com/nodes")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            try JSONEncoder().encode(mockNodes)
        )
        
        // Configure session
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeaderCapturingURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        
        // Set token initially
        apiClient.setAuthToken(testToken)
        
        // Act - Clear token and make request
        apiClient.setAuthToken(nil)
        _ = try await apiClient.getNodes()
        
        // Assert - No Authorization header after clearing
        XCTAssertNotNil(HeaderCapturingURLProtocol.capturedHeaders)
        if let headers = HeaderCapturingURLProtocol.capturedHeaders {
            XCTAssertNil(headers["Authorization"],
                        "Authorization header should be removed after clearing token")
        }
    }
    
    func testAPIClient_withDifferentEndpoints_maintainsAuthHeader() async throws {
        // Arrange
        let testToken = "persistent-token-456"
        
        // Create mock node for various endpoints
        let mockNode = Node(
            id: "node-123",
            title: "Test Node",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Set up mock response
        HeaderCapturingURLProtocol.mockResponse = (
            HTTPURLResponse(
                url: URL(string: "http://test.com/nodes/123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            try JSONEncoder().encode(mockNode)
        )
        
        // Configure session
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeaderCapturingURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let apiClient = APIClient(urlSession: mockSession)
        apiClient.setAuthToken(testToken)
        
        // Act - Make request to different endpoint
        _ = try await apiClient.getNode(id: "node-123")
        
        // Assert - Auth header present for all endpoints
        XCTAssertNotNil(HeaderCapturingURLProtocol.capturedHeaders)
        if let headers = HeaderCapturingURLProtocol.capturedHeaders {
            XCTAssertEqual(headers["Authorization"], "Bearer \(testToken)",
                          "Authorization header should be present for all endpoints when token is set")
        }
    }
    
    func testAPIClient_tokenPersistence_survivesAcrossInstances() async throws {
        // Arrange
        let persistentToken = "persistent-token-xyz"
        let mockNodes: [Node] = []
        
        // Set token with first instance
        let firstClient = APIClient(urlSession: URLSession.shared)
        firstClient.setAuthToken(persistentToken)
        
        // Set up mock for second instance
        HeaderCapturingURLProtocol.mockResponse = (
            HTTPURLResponse(
                url: URL(string: "http://test.com/nodes")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            try JSONEncoder().encode(mockNodes)
        )
        
        // Configure session with mock
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeaderCapturingURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // Act - Create new instance and make request
        let secondClient = APIClient(urlSession: mockSession)
        _ = try await secondClient.getNodes()
        
        // Assert - Token persisted via UserDefaults
        XCTAssertNotNil(HeaderCapturingURLProtocol.capturedHeaders)
        if let headers = HeaderCapturingURLProtocol.capturedHeaders {
            XCTAssertEqual(headers["Authorization"], "Bearer \(persistentToken)",
                          "Authorization header should persist across APIClient instances")
        }
    }
}
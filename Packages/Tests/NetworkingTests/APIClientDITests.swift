import XCTest
import Foundation
@testable import Networking
@testable import Models
@testable import Core  // For KeychainManager

final class APIClientDITests: XCTestCase {
    
    // MARK: - Mock URLProtocol
    
    class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        
        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }
        
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }
        
        override func startLoading() {
            guard let handler = MockURLProtocol.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        
        override func stopLoading() {}
    }
    
    // MARK: - Tests
    
    func testAPIClient_withInjectedURLSession_shouldCompile() {
        // Arrange - Create custom URLSession configuration
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // Act - Create APIClient with injected session
        let apiClient = APIClient(urlSession: mockSession)
        
        // Assert - Should compile and create instance
        XCTAssertNotNil(apiClient)
    }
    
    func testAPIClient_withMockURLProtocol_shouldInterceptRequests() async throws {
        // Arrange - Set up mock response
        let expectedData = """
            {
                "id": "test-123",
                "email": "test@example.com",
                "full_name": "Test User"
            }
            """.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            // Verify request properties
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/test") ?? false)
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, expectedData)
        }
        
        // Configure session with mock
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // Act - Create APIClient with mock session
        let apiClient = APIClient(urlSession: mockSession)
        
        // Make a request
        let user = try await apiClient.makeRequest(
            endpoint: "/test",
            method: "GET",
            responseType: User.self
        )
        
        // Assert
        XCTAssertEqual(user.id, "test-123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.fullName, "Test User")
    }
    
    func testAPIClient_defaultSingleton_shouldUseSharedSession() {
        // Arrange & Act
        let apiClient = APIClient.shared
        
        // Assert - Singleton should exist
        XCTAssertNotNil(apiClient)
        // Note: Can't directly test URLSession.shared usage without making urlSession property internal/public
    }
}
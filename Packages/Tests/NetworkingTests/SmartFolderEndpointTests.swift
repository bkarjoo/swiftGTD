import XCTest
import Foundation
@testable import Networking
@testable import Models
@testable import Core

/// Tests for smart folder API endpoints
final class SmartFolderEndpointTests: XCTestCase {

    var mockSession: URLSession!
    var apiClient: APIClient!

    override func setUp() {
        super.setUp()

        // Configure mock URL session
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: configuration)

        // Initialize API client with mock session
        apiClient = APIClient(urlSession: mockSession)
        apiClient.setAuthToken("test-token")
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        mockSession = nil
        apiClient = nil
        super.tearDown()
    }

    // MARK: - Execute Smart Folder Tests

    func testExecuteSmartFolderRule_withValidResponse_returnsNodes() async throws {
        // Arrange
        let smartFolderId = "smart-folder-123"
        let expectedNodes = [
            Node(
                id: "node-1",
                title: "Task 1",
                nodeType: "task",
                parentId: nil,
                sortOrder: 0,
                createdAt: Date(),
                updatedAt: Date(),
                taskData: TaskData(status: "todo", priority: "high")
            ),
            Node(
                id: "node-2",
                title: "Task 2",
                nodeType: "task",
                parentId: nil,
                sortOrder: 1,
                createdAt: Date(),
                updatedAt: Date(),
                taskData: TaskData(status: "done", priority: "medium")
            )
        ]

        MockURLProtocol.requestHandler = { request in
            // Verify request
            XCTAssertEqual(request.url?.path, "/nodes/\(smartFolderId)/contents")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

            // Return mock response
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(expectedNodes)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        // Act
        let nodes = try await apiClient.executeSmartFolderRule(smartFolderId: smartFolderId)

        // Assert
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].id, "node-1")
        XCTAssertEqual(nodes[0].title, "Task 1")
        XCTAssertEqual(nodes[1].id, "node-2")
        XCTAssertEqual(nodes[1].title, "Task 2")
    }

    func testExecuteSmartFolderRule_withEmptyResponse_returnsEmptyArray() async throws {
        // Arrange
        let smartFolderId = "smart-folder-empty"

        MockURLProtocol.requestHandler = { request in
            // Verify endpoint
            XCTAssertEqual(request.url?.path, "/nodes/\(smartFolderId)/contents")

            // Return empty array
            let data = "[]".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        // Act
        let nodes = try await apiClient.executeSmartFolderRule(smartFolderId: smartFolderId)

        // Assert
        XCTAssertEqual(nodes.count, 0)
    }

    func testExecuteSmartFolderRule_with404Error_throwsError() async throws {
        // Arrange
        let smartFolderId = "nonexistent-folder"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // Act & Assert
        do {
            _ = try await apiClient.executeSmartFolderRule(smartFolderId: smartFolderId)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
            XCTAssertTrue(error is APIError)
        }
    }

    func testExecuteSmartFolderRule_withNetworkError_throwsError() async throws {
        // Arrange
        let smartFolderId = "smart-folder-123"

        MockURLProtocol.requestHandler = { request in
            throw URLError(.notConnectedToInternet)
        }

        // Act & Assert
        do {
            _ = try await apiClient.executeSmartFolderRule(smartFolderId: smartFolderId)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
            XCTAssertTrue(error is URLError)
        }
    }

    func testExecuteSmartFolderRule_withMalformedJSON_throwsDecodingError() async throws {
        // Arrange
        let smartFolderId = "smart-folder-bad"

        MockURLProtocol.requestHandler = { request in
            let data = "{ invalid json }".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        // Act & Assert
        do {
            _ = try await apiClient.executeSmartFolderRule(smartFolderId: smartFolderId)
            XCTFail("Should have thrown a decoding error")
        } catch {
            // Expected decoding error
            XCTAssertTrue(error is DecodingError)
        }
    }
}

// MARK: - Mock URL Protocol

private class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
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
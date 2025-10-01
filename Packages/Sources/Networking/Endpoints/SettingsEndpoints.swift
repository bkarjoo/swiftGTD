import Foundation
import Models
import Core

private let logger = Logger.shared

public struct DefaultNodeResponse: Codable {
    public let nodeId: String?

    private enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
    }
}

public struct SetDefaultNodeRequest: Codable {
    public let nodeId: String?

    private enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
    }

    public init(nodeId: String?) {
        self.nodeId = nodeId
    }
}

public extension APIClient {
    // Settings endpoints
    func getDefaultNode() async throws -> String? {
        logger.log("📞 getDefaultNode called", category: "APIClient")

        do {
            let response = try await makeRequest(
                endpoint: "/settings/default-node",
                responseType: DefaultNodeResponse.self
            )

            logger.log("✅ Retrieved default node: \(response.nodeId ?? "nil")", category: "APIClient")
            return response.nodeId
        } catch {
            logger.log("❌ Failed to get default node: \(error)", category: "APIClient", level: .error)
            throw error
        }
    }

    func setDefaultNode(nodeId: String?) async throws {
        logger.log("📞 setDefaultNode called with nodeId: \(nodeId ?? "nil")", category: "APIClient")

        let request = SetDefaultNodeRequest(nodeId: nodeId)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try encoder.encode(request)

        do {
            // For PUT requests that return empty response, we use EmptyResponse type
            _ = try await makeRequest(
                endpoint: "/settings/default-node",
                method: "PUT",
                body: body,
                responseType: EmptyResponse.self
            )

            logger.log("✅ Default node set successfully", category: "APIClient")
        } catch {
            logger.log("❌ Failed to set default node: \(error)", category: "APIClient", level: .error)
            throw error
        }
    }
}
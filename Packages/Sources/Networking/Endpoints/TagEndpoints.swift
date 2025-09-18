import Foundation
import Models
import Core

private let logger = Logger.shared

public extension APIClient {
    // Tag endpoints
    func getTags() async throws -> [Tag] {
        return try await makeRequest(
            endpoint: "/tags",
            responseType: [Tag].self
        )
    }
    
    func createTag(name: String, description: String? = nil, color: String? = nil) async throws -> Tag {
        // Validate input
        try InputValidator.validateTagName(name)
        try InputValidator.validateDescription(description)
        try InputValidator.validateColor(color)

        logger.log("📞 Creating tag: \(name)", category: "TagEndpoints")

        // Create request body instead of query params
        struct CreateTagRequest: Codable {
            let name: String
            let description: String?
            let color: String?
        }

        let requestBody = CreateTagRequest(
            name: name,
            description: description,
            color: color
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        let response = try await makeRequest(
            endpoint: "/tags",
            method: "POST",
            body: bodyData,
            responseType: Tag.self
        )

        logger.log("✅ Tag created/found: \(response.name)", category: "TagEndpoints")
        return response
    }
    
    func searchTags(query: String, limit: Int = 20) async throws -> [Tag] {
        logger.log("📞 Searching tags with query: \(query)", category: "TagEndpoints")
        
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "q", value: query))
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        
        var urlComponents = URLComponents(string: "/tags/search")!
        urlComponents.queryItems = queryItems
        let endpoint = urlComponents.string!
        
        let response = try await makeRequest(
            endpoint: endpoint,
            method: "GET",
            responseType: [Tag].self
        )
        
        logger.log("✅ Found \(response.count) tags", category: "TagEndpoints")
        return response
    }
    
    func attachTagToNode(nodeId: String, tagId: String) async throws {
        logger.log("📞 Attaching tag \(tagId) to node \(nodeId)", category: "TagEndpoints")

        // Server returns a message like {"message": "Tag attached"} not empty
        struct TagResponse: Codable {
            let message: String?
        }

        _ = try await makeRequest(
            endpoint: "/nodes/\(nodeId)/tags/\(tagId)",
            method: "POST",
            responseType: TagResponse.self
        )

        logger.log("✅ Tag attached successfully", category: "TagEndpoints")
    }

    func detachTagFromNode(nodeId: String, tagId: String) async throws {
        logger.log("📞 Detaching tag \(tagId) from node \(nodeId)", category: "TagEndpoints")

        // Server returns 204 No Content (empty response) for DELETE
        _ = try await makeRequest(
            endpoint: "/nodes/\(nodeId)/tags/\(tagId)",
            method: "DELETE",
            responseType: EmptyResponse.self
        )

        logger.log("✅ Tag detached successfully", category: "TagEndpoints")
    }
    
    func getNodeTags(nodeId: String) async throws -> [Tag] {
        logger.log("📞 Getting tags for node \(nodeId)", category: "TagEndpoints")
        
        let response = try await makeRequest(
            endpoint: "/nodes/\(nodeId)/tags",
            method: "GET",
            responseType: [Tag].self
        )
        
        logger.log("✅ Retrieved \(response.count) tags for node", category: "TagEndpoints")
        return response
    }
}

import Foundation
import Models
import Core

private let logger = Logger.shared

extension APIClient {
    /// Fetch all rules accessible to the current user
    /// - Parameters:
    ///   - includePublic: Include public rules from other users
    ///   - includeSystem: Include system-provided rules
    /// - Returns: RuleListResponse containing the rules
    public func getRules(includePublic: Bool = true, includeSystem: Bool = true) async throws -> RuleListResponse {
        logger.log("📞 Fetching rules (includePublic: \(includePublic), includeSystem: \(includeSystem))", category: "RuleEndpoints")
        
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "include_public", value: String(includePublic)))
        queryItems.append(URLQueryItem(name: "include_system", value: String(includeSystem)))
        
        var urlComponents = URLComponents(string: "/rules/")!
        urlComponents.queryItems = queryItems
        let endpoint = urlComponents.string!
        
        let response = try await makeRequest(
            endpoint: endpoint,
            method: "GET",
            responseType: RuleListResponse.self
        )
        
        logger.log("✅ Fetched \(response.rules.count) rules", category: "RuleEndpoints")
        return response
    }
    
    /// Get a specific rule by ID
    /// - Parameter id: The rule ID
    /// - Returns: The Rule
    public func getRule(id: String) async throws -> Rule {
        logger.log("📞 Fetching rule: \(id)", category: "RuleEndpoints")

        let response = try await makeRequest(
            endpoint: "/rules/\(id)",
            method: "GET",
            responseType: Rule.self
        )

        logger.log("✅ Fetched rule: \(response.name)", category: "RuleEndpoints")
        return response
    }

    /// Create a new rule
    /// - Parameter request: The rule creation request
    /// - Returns: The created Rule
    public func createRule(_ request: RuleCreateRequest) async throws -> Rule {
        logger.log("📞 Creating rule: \(request.name)", category: "RuleEndpoints")

        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)

        let response = try await makeRequest(
            endpoint: "/rules/",
            method: "POST",
            body: requestData,
            responseType: Rule.self
        )

        logger.log("✅ Created rule: \(response.name)", category: "RuleEndpoints")
        return response
    }

    /// Update an existing rule
    /// - Parameters:
    ///   - id: The rule ID
    ///   - request: The update request
    /// - Returns: The updated Rule
    public func updateRule(id: String, request: RuleUpdateRequest) async throws -> Rule {
        logger.log("📞 Updating rule: \(id)", category: "RuleEndpoints")

        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)

        let response = try await makeRequest(
            endpoint: "/rules/\(id)",
            method: "PUT",
            body: requestData,
            responseType: Rule.self
        )

        logger.log("✅ Updated rule: \(response.name)", category: "RuleEndpoints")
        return response
    }

    /// Delete a rule
    /// - Parameter id: The rule ID
    public func deleteRule(id: String) async throws {
        logger.log("📞 Deleting rule: \(id)", category: "RuleEndpoints")

        _ = try await makeRequest(
            endpoint: "/rules/\(id)",
            method: "DELETE",
            responseType: EmptyResponse.self
        )

        logger.log("✅ Deleted rule: \(id)", category: "RuleEndpoints")
    }

    /// Duplicate a rule
    /// - Parameters:
    ///   - id: The rule ID to duplicate
    ///   - newName: Optional new name for the duplicate
    /// - Returns: The duplicated Rule
    public func duplicateRule(id: String, newName: String? = nil) async throws -> Rule {
        logger.log("📞 Duplicating rule: \(id)", category: "RuleEndpoints")

        var endpoint = "/rules/\(id)/duplicate"
        if let newName = newName {
            var components = URLComponents(string: endpoint)!
            components.queryItems = [URLQueryItem(name: "new_name", value: newName)]
            endpoint = components.string!
        }

        let response = try await makeRequest(
            endpoint: endpoint,
            method: "POST",
            responseType: Rule.self
        )

        logger.log("✅ Duplicated rule: \(response.name)", category: "RuleEndpoints")
        return response
    }
}
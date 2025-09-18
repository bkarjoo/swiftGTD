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
}
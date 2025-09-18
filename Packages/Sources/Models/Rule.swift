import Foundation

/// Rule model - Represents a standalone, composable filtering rule
public struct Rule: Codable, Identifiable {
    public let id: String  // UUID as string
    public let name: String
    public let description: String?
    public let isPublic: Bool
    public let isSystem: Bool
    public let ownerId: String  // UUID as string
    public let createdAt: String  // ISO 8601 datetime string
    public let updatedAt: String  // ISO 8601 datetime string
    
    public init(
        id: String,
        name: String,
        description: String? = nil,
        isPublic: Bool,
        isSystem: Bool,
        ownerId: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isPublic = isPublic
        self.isSystem = isSystem
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case isPublic = "is_public"
        case isSystem = "is_system"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Response containing a list of rules
public struct RuleListResponse: Codable {
    public let rules: [Rule]
    public let total: Int
}
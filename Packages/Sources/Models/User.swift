import Foundation

public struct User: Codable, Identifiable {
    public let id: String
    public let email: String
    public let fullName: String?
    
    public init(id: String, email: String, fullName: String? = nil) {
        self.id = id
        self.email = email
        self.fullName = fullName
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
    }
}

public struct LoginRequest: Codable {
    public let email: String
    public let password: String
    
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct SignupRequest: Codable {
    public let email: String
    public let password: String
    public let username: String?
    
    public init(email: String, password: String, username: String?) {
        self.email = email
        self.password = password
        self.username = username
    }
}

public struct AuthResponse: Codable {
    public let accessToken: String
    public let tokenType: String
    
    public init(accessToken: String, tokenType: String) {
        self.accessToken = accessToken
        self.tokenType = tokenType
    }
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}
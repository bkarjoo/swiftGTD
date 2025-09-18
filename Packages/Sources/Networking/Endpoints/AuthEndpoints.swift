import Foundation
import Models

public extension APIClient {
    // Auth endpoints
    func login(email: String, password: String) async throws -> AuthResponse {
        let loginRequest = LoginRequest(email: email, password: password)
        let encoder = JSONEncoder()
        let body = try encoder.encode(loginRequest)
        
        return try await makeRequest(
            endpoint: "/auth/login",
            method: "POST",
            body: body,
            responseType: AuthResponse.self
        )
    }
    
    func signup(email: String, password: String, username: String?) async throws -> AuthResponse {
        let signupRequest = SignupRequest(email: email, password: password, username: username)
        let encoder = JSONEncoder()
        let body = try encoder.encode(signupRequest)
        
        return try await makeRequest(
            endpoint: "/auth/signup",
            method: "POST",
            body: body,
            responseType: AuthResponse.self
        )
    }
    
    func getCurrentUser() async throws -> User {
        return try await makeRequest(
            endpoint: "/auth/me",
            responseType: User.self
        )
    }
}
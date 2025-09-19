import Foundation
import SwiftUI
import Models
import Networking
import Core

@MainActor
public class AuthManager: ObservableObject {
    @Published public var isAuthenticated = false
    @Published public var currentUser: User?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    
    private let api = APIClient.shared
    private let logger = Logger.shared
    private let keychain = KeychainManager.shared
    
    public init() {
        loadStoredToken()
    }
    
    private func loadStoredToken() {
        // Load token from Keychain
        if let token = keychain.getToken() {
            logger.log("🔑 Found stored token in Keychain, attempting auto-login", category: "AuthManager")
            api.setAuthToken(token)
            Task {
                await validateToken()
            }
        } else {
            logger.log("🔑 No stored token found in Keychain", category: "AuthManager")
        }
    }
    
    private func validateToken() async {
        do {
            logger.log("🔑 Validating stored token...", category: "AuthManager")
            let user = try await api.getCurrentUser()
            self.currentUser = user
            self.isAuthenticated = true
            logger.log("✅ Token valid, auto-login successful for user: \(user.email)", category: "AuthManager")
        } catch {
            logger.log("❌ Token validation failed: \(error)", category: "AuthManager")
            // Don't clear the token immediately - it might be a network issue
            // Just mark as not authenticated for now
            self.isAuthenticated = false

            // Only clear token if it's definitely invalid (401 unauthorized)
            switch error {
            case APIError.unauthorized:
                logger.log("🔑 Token is unauthorized, clearing stored token", category: "AuthManager")
                logout()
            case APIError.httpError(401, _):
                logger.log("🔑 Got 401 error, clearing stored token", category: "AuthManager")
                logout()
            default:
                // Keep the token for other errors (network issues, etc.)
                logger.log("⚠️ Keeping token despite error (might be network issue)", category: "AuthManager")
                break
            }
        }
    }
    
    public func login(email: String, password: String, rememberMe: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.login(email: email, password: password)

            // Only persist token if Remember Me is checked
            if rememberMe {
                logger.log("🔑 Remember Me checked, saving token to Keychain", category: "AuthManager")
                let saved = keychain.saveToken(response.accessToken)

                if saved {
                    logger.log("✅ Token successfully saved to Keychain", category: "AuthManager")
                } else {
                    logger.log("❌ Failed to save token to Keychain!", category: "AuthManager")
                }
            } else {
                // Clear any existing stored token
                logger.log("🔑 Remember Me not checked, clearing any stored token", category: "AuthManager")
                keychain.deleteToken()
            }

            api.setAuthToken(response.accessToken)
            // After login, get the current user info
            let user = try await api.getCurrentUser()
            currentUser = user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    
    public func signup(email: String, password: String, username: String?) async {
        isLoading = true
        errorMessage = nil

        do {
            // First signup
            _ = try await api.signup(email: email, password: password, username: username)
            // Then login to get token
            let loginResponse = try await api.login(email: email, password: password)
            // Always remember new users (they just signed up, so keep them logged in)
            let saved = keychain.saveToken(loginResponse.accessToken)
            logger.log(saved ? "✅ Signup: Token saved to Keychain" : "❌ Signup: Failed to save token", category: "AuthManager")
            api.setAuthToken(loginResponse.accessToken)
            // Get current user info
            let user = try await api.getCurrentUser()
            currentUser = user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    
    public func logout() {
        keychain.deleteToken()
        api.setAuthToken(nil)
        currentUser = nil
        isAuthenticated = false
    }
}
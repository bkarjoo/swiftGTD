import Foundation
import SwiftUI
import Models
import Networking

@MainActor
public class AuthManager: ObservableObject {
    @Published public var isAuthenticated = false
    @Published public var currentUser: User?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    
    private let api = APIClient.shared
    private let tokenKey = "auth_token"
    
    public init() {
        loadStoredToken()
    }
    
    private func loadStoredToken() {
        if let token = UserDefaults.standard.string(forKey: tokenKey) {
            api.setAuthToken(token)
            Task {
                await validateToken()
            }
        }
    }
    
    private func validateToken() async {
        do {
            let user = try await api.getCurrentUser()
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            // Token is invalid, clear it
            logout()
        }
    }
    
    public func login(email: String, password: String, rememberMe: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.login(email: email, password: password)

            // Only persist token if Remember Me is checked
            if rememberMe {
                UserDefaults.standard.set(response.accessToken, forKey: tokenKey)
            } else {
                // Clear any existing stored token
                UserDefaults.standard.removeObject(forKey: tokenKey)
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
            UserDefaults.standard.set(loginResponse.accessToken, forKey: tokenKey)
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
        UserDefaults.standard.removeObject(forKey: tokenKey)
        api.setAuthToken(nil)
        currentUser = nil
        isAuthenticated = false
    }
}
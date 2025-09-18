import Foundation
import Models
import Core

private let logger = Logger.shared

public class APIClient {
    public static let shared = APIClient()
    private let baseURL = API.baseURL
    private let urlSession: URLSession
    
    private var authToken: String? {
        get {
            return KeychainManager.shared.getToken()
        }
        set {
            if let token = newValue {
                _ = KeychainManager.shared.saveToken(token)
            } else {
                _ = KeychainManager.shared.deleteToken()
            }
        }
    }
    
    // Private init for singleton
    private init() {
        // Configure URLSession with timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0  // 30 seconds timeout
        config.timeoutIntervalForResource = 60.0 // 60 seconds total timeout
        self.urlSession = URLSession(configuration: config)
        logger.log("📞 Initializing APIClient singleton", category: "APIClient")
        logger.log("   - Base URL: \(baseURL)", category: "APIClient")

        // Migrate token from UserDefaults to Keychain if needed
        if let oldToken = UserDefaults.standard.string(forKey: "auth_token") {
            logger.log("🔄 Migrating token from UserDefaults to Keychain", category: "APIClient")
            _ = KeychainManager.shared.saveToken(oldToken)
            UserDefaults.standard.removeObject(forKey: "auth_token")
            logger.log("✅ Token migration complete", category: "APIClient")
        }

        logger.log("   - Auth token present: \(authToken != nil)", category: "APIClient")
    }
    
    // Internal init for testing with injectable URLSession
    internal init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        logger.log("📞 Initializing APIClient with custom URLSession", category: "APIClient")
        logger.log("   - Base URL: \(baseURL)", category: "APIClient")
        logger.log("   - URLSession: \(urlSession == .shared ? "shared" : "custom")", category: "APIClient")
    }
    
    public func setAuthToken(_ token: String?) {
        logger.log("📞 Setting auth token: \(token != nil ? "<token_present>" : "nil")", category: "APIClient")
        authToken = token
        logger.log("✅ Auth token updated", category: "APIClient")
    }
    
    internal func makeRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        responseType: T.Type,
        maxRetries: Int = 3
    ) async throws -> T {
        var lastError: Error?
        var retryCount = 0

        while retryCount <= maxRetries {
            if retryCount > 0 {
                // Exponential backoff: 1s, 2s, 4s
                let delay = UInt64(pow(2.0, Double(retryCount - 1))) * 1_000_000_000
                logger.log("⏳ Retrying request after \(delay / 1_000_000_000)s (attempt \(retryCount + 1)/\(maxRetries + 1))", category: "APIClient")
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                return try await performRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    responseType: responseType
                )
            } catch let error as APIError {
                lastError = error
                if error.isRetryable && retryCount < maxRetries {
                    retryCount += 1
                    logger.log("🔄 Request failed with retryable error, will retry", category: "APIClient")
                    continue
                }
                throw error
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError ?? APIError.networkError(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
    }

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        logger.log("📞 Starting request", category: "APIClient")
        logger.log("   - Endpoint: \(endpoint)", category: "APIClient")
        logger.log("   - Method: \(method)", category: "APIClient")
        logger.log("   - Response type: \(T.self)", category: "APIClient")

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            logger.log("❌ Invalid URL: \(baseURL)\(endpoint)", category: "APIClient")
            throw APIError.invalidURL
        }
        
        logger.log("🔵 Full URL: \(url)", category: "APIClient")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            logger.log("🔐 Token added to request", category: "APIClient")
        } else {
            logger.log("⚠️ No token available for request", category: "APIClient")
        }
        
        request.httpBody = body
        if let body = body {
            // NEVER log sensitive endpoints
            let sensitiveEndpoints = ["/auth/login", "/auth/signup", "/auth/reset-password"]
            if sensitiveEndpoints.contains(endpoint) {
                logger.log("📤 Request body: <redacted for security>", category: "APIClient")
            } else {
                let bodyString = String(data: body, encoding: .utf8) ?? "<binary_data>"
                // Truncate long bodies for readability
                let logString = bodyString.count > 500
                    ? String(bodyString.prefix(500)) + "..."
                    : bodyString
                logger.log("📤 Request body: \(logString)", category: "APIClient")
            }
        }
        
        do {
            logger.log("📞 Sending request to server...", category: "APIClient")
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("❌ Invalid response type", category: "APIClient")
                throw APIError.invalidResponse
            }
            
            logger.log("📥 Response received", category: "APIClient")
            logger.log("   - Status code: \(httpResponse.statusCode)", category: "APIClient")
            logger.log("   - Data size: \(data.count) bytes", category: "APIClient")
            
            let responseString = String(data: data, encoding: .utf8) ?? "<binary_data>"
            logger.log("   - Response preview: \(String(responseString.prefix(200)))...", category: "APIClient")
            
            // Check for specific status codes
            if httpResponse.statusCode == 401 {
                logger.log("🔒 Unauthorized - token may be invalid", category: "APIClient")
                throw APIError.unauthorized
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                // Try to extract error message from response
                var errorMessage: String? = nil
                if !data.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String ?? json["error"] as? String {
                    errorMessage = message
                }
                logger.log("❌ HTTP Error: \(httpResponse.statusCode) - \(errorMessage ?? "No message")", category: "APIClient")
                throw APIError.httpError(httpResponse.statusCode, message: errorMessage)
            }

            // Handle 204 No Content
            if httpResponse.statusCode == 204 {
                logger.log("📭 Received 204 No Content", category: "APIClient")
                if T.self == EmptyResponse.self {
                    // Safe only for explicit EmptyResponse
                    return EmptyResponse() as! T
                } else {
                    // Unexpected no-content for non-empty response types
                    logger.log("❌ 204 with non-empty response type: \(T.self)", category: "APIClient")
                    throw APIError.invalidResponse
                }
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                logger.log("📞 Attempting to decode as \(T.self)", category: "APIClient")
                let result = try decoder.decode(T.self, from: data)
                logger.log("✅ Successfully decoded \(T.self)", category: "APIClient")
                return result
            } catch let decodingError {
                logger.log("❌ Decode error for \(T.self): \(decodingError)", category: "APIClient")
                logger.log("   - Error type: \(type(of: decodingError))", category: "APIClient")
                logger.log("   - Error details: \(decodingError.localizedDescription)", category: "APIClient")
                throw APIError.decodingError(decodingError)
            }
        } catch let error as APIError {
            // Re-throw APIErrors as-is
            throw error
        } catch {
            // Check for timeout errors
            if (error as NSError).code == NSURLErrorTimedOut {
                logger.log("⏱️ Request timed out", category: "APIClient")
                throw APIError.timeout
            }
            logger.log("❌ Network error: \(error)", category: "APIClient")
            logger.log("   - Error type: \(type(of: error))", category: "APIClient")
            logger.log("   - Error details: \(error.localizedDescription)", category: "APIClient")
            throw APIError.networkError(error)
        }
    }
}

public enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, message: String?)
    case decodingError(Error)
    case networkError(Error)
    case timeout
    case unauthorized
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            if let message = message {
                return "HTTP \(code): \(message)"
            }
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .unauthorized:
            return "Unauthorized - please log in again"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .timeout, .networkError:
            return true
        case .httpError(let code, _):
            return code >= 500 || code == 429
        default:
            return false
        }
    }
}

public struct EmptyResponse: Codable {}

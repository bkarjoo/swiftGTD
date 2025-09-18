import Foundation
import Security

public class KeychainManager {
    public static let shared = KeychainManager()
    private let logger = Logger.shared

    private let serviceName = "com.swiftgtd.app"
    private let accountName = "authToken"

    private init() {
        logger.log("🔐 Initializing KeychainManager", category: "Keychain")
    }

    public func saveToken(_ token: String) -> Bool {
        logger.log("🔐 Saving token to Keychain", category: "Keychain")

        // Convert token to data
        guard let data = token.data(using: .utf8) else {
            logger.log("❌ Failed to convert token to data", level: .error, category: "Keychain")
            return false
        }

        // Delete any existing token first
        deleteToken()

        // Create the keychain item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            logger.log("✅ Token saved to Keychain", category: "Keychain")
            return true
        } else {
            logger.log("❌ Failed to save token: \(status)", level: .error, category: "Keychain")
            return false
        }
    }

    public func getToken() -> String? {
        logger.log("🔐 Retrieving token from Keychain", category: "Keychain")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            logger.log("✅ Token retrieved from Keychain", category: "Keychain")
            return token
        } else if status == errSecItemNotFound {
            logger.log("⚠️ No token found in Keychain", category: "Keychain")
            return nil
        } else {
            logger.log("❌ Failed to retrieve token: \(status)", level: .error, category: "Keychain")
            return nil
        }
    }

    public func deleteToken() -> Bool {
        logger.log("🔐 Deleting token from Keychain", category: "Keychain")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            logger.log("✅ Token deleted from Keychain", category: "Keychain")
            return true
        } else {
            logger.log("❌ Failed to delete token: \(status)", level: .error, category: "Keychain")
            return false
        }
    }
}
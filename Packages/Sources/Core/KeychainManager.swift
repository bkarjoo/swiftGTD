import Foundation
import Security

public class KeychainManager {
    public static let shared = KeychainManager()
    private let logger = Logger.shared

    private let serviceName = "com.swiftgtd.app"
    private let accountName = "authToken"
    private let accessGroup: String? = nil

    // Store token in memory for unsigned builds
    private var inMemoryToken: String?
    private let useKeychain: Bool

    private init() {
        // Check if running unsigned build by checking bundle identifier
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        // Enable keychain for all builds - it should work even for unsigned builds
        self.useKeychain = true

        logger.log("🔐 Initializing KeychainManager (useKeychain: \(useKeychain), bundleId: \(bundleId))", category: "Keychain")
    }

    public func saveToken(_ token: String) -> Bool {
        logger.log("🔐 Saving token (useKeychain: \(useKeychain))", category: "Keychain")

        // For unsigned builds, just store in memory
        if !useKeychain {
            inMemoryToken = token
            logger.log("✅ Token saved to memory", category: "Keychain")
            return true
        }

        // Convert token to data
        guard let data = token.data(using: .utf8) else {
            logger.log("❌ Failed to convert token to data", category: "Keychain", level: .error)
            return false
        }

        // Delete any existing token first
        deleteToken()

        // Create the keychain item
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: false
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            logger.log("✅ Token saved to Keychain", category: "Keychain")
            return true
        } else {
            logger.log("❌ Failed to save token: \(status)", category: "Keychain", level: .error)
            return false
        }
    }

    public func getToken() -> String? {
        logger.log("🔐 Retrieving token (useKeychain: \(useKeychain))", category: "Keychain")

        // For unsigned builds, return from memory
        if !useKeychain {
            logger.log("✅ Token retrieved from memory", category: "Keychain")
            return inMemoryToken
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

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
            logger.log("❌ Failed to retrieve token: \(status)", category: "Keychain", level: .error)
            return nil
        }
    }

    public func deleteToken() -> Bool {
        logger.log("🔐 Deleting token (useKeychain: \(useKeychain))", category: "Keychain")

        // For unsigned builds, just clear memory
        if !useKeychain {
            inMemoryToken = nil
            logger.log("✅ Token deleted from memory", category: "Keychain")
            return true
        }

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
            logger.log("❌ Failed to delete token: \(status)", category: "Keychain", level: .error)
            return false
        }
    }
}
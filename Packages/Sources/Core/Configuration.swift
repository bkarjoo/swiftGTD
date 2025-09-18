import Foundation

public enum Configuration {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        guard let object = Bundle.main.object(forInfoDictionaryKey: key) else {
            throw Error.missingKey
        }

        switch object {
        case let value as T:
            return value
        case let string as String:
            guard let value = T(string) else { fallthrough }
            return value
        default:
            throw Error.invalidValue
        }
    }

    static func value(for key: String) -> String {
        // 1) Environment override (useful for CI/dev shells)
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }

        // 2) Info.plist configuration
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            // Handle Xcode's $()/slash workaround for URLs
            return value.replacingOccurrences(of: "$()", with: "")
        }

        // 3) Fallbacks per key
        return defaultValue(for: key)
    }

    private static func defaultValue(for key: String) -> String {
        switch key {
        case "API_BASE_URL":
            #if DEBUG
            // Development fallback only
            return "http://localhost:8003"
            #else
            // Production must have proper configuration
            fatalError("API_BASE_URL not configured. Provide Info.plist entry or environment variable.")
            #endif
        default:
            return ""
        }
    }
}

public enum API {
    public static var baseURL: String {
        return Configuration.value(for: "API_BASE_URL")
    }
}

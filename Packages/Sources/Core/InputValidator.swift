import Foundation

public enum InputValidator {

    // MARK: - Validation Rules

    public static let minTitleLength = 1
    public static let maxTitleLength = 255
    public static let maxDescriptionLength = 10000
    public static let maxTagNameLength = 50
    public static let maxColorLength = 7  // #RRGGBB format

    // MARK: - Validation Methods

    /// Validates a node title
    public static func validateTitle(_ title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw ValidationError.emptyTitle
        }

        guard trimmed.count <= maxTitleLength else {
            throw ValidationError.titleTooLong(maxLength: maxTitleLength)
        }

        // Check for invalid characters
        guard !trimmed.contains(where: { $0.isNewline }) else {
            throw ValidationError.invalidCharacters("Title cannot contain newlines")
        }
    }

    /// Validates a description
    public static func validateDescription(_ description: String?) throws {
        guard let description = description else { return }

        guard description.count <= maxDescriptionLength else {
            throw ValidationError.descriptionTooLong(maxLength: maxDescriptionLength)
        }
    }

    /// Validates a tag name
    public static func validateTagName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw ValidationError.emptyTagName
        }

        guard trimmed.count <= maxTagNameLength else {
            throw ValidationError.tagNameTooLong(maxLength: maxTagNameLength)
        }

        // Tags should not contain special characters that might interfere with search
        let allowedCharacters = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        guard trimmed.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw ValidationError.invalidCharacters("Tag names can only contain letters, numbers, spaces, hyphens, and underscores")
        }
    }

    /// Validates a color hex string
    public static func validateColor(_ color: String?) throws {
        guard let color = color else { return }

        // Color should be in format #RRGGBB
        let colorRegex = "^#[0-9A-Fa-f]{6}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", colorRegex)

        guard predicate.evaluate(with: color) else {
            throw ValidationError.invalidColorFormat
        }
    }

    /// Validates a node ID (should be UUID or temp- prefixed)
    public static func validateNodeId(_ id: String) throws {
        // Check if it's a temp ID
        if id.hasPrefix("temp-") {
            let uuidPart = String(id.dropFirst(5))
            guard UUID(uuidString: uuidPart) != nil else {
                throw ValidationError.invalidNodeId
            }
            return
        }

        // Otherwise it should be a valid UUID
        guard UUID(uuidString: id) != nil else {
            throw ValidationError.invalidNodeId
        }
    }

    /// Validates a sort order value
    public static func validateSortOrder(_ sortOrder: Int) throws {
        guard sortOrder >= 0 else {
            throw ValidationError.invalidSortOrder
        }
    }

    // MARK: - Sanitization Methods

    /// Sanitizes a title by trimming whitespace and removing invalid characters
    public static func sanitizeTitle(_ title: String) -> String {
        return title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\0", with: "")
            .prefix(maxTitleLength)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Sanitizes a tag name
    public static func sanitizeTagName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace invalid characters with underscores
        let sanitized = trimmed.map { char -> Character in
            let scalar = char.unicodeScalars.first!
            let allowedCharacters = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
            return allowedCharacters.contains(scalar) ? char : "_"
        }

        return String(sanitized)
            .prefix(maxTagNameLength)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Validation Errors

public enum ValidationError: LocalizedError {
    case emptyTitle
    case titleTooLong(maxLength: Int)
    case emptyTagName
    case tagNameTooLong(maxLength: Int)
    case descriptionTooLong(maxLength: Int)
    case invalidCharacters(String)
    case invalidColorFormat
    case invalidNodeId
    case invalidSortOrder

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Title cannot be empty"
        case .titleTooLong(let maxLength):
            return "Title cannot exceed \(maxLength) characters"
        case .emptyTagName:
            return "Tag name cannot be empty"
        case .tagNameTooLong(let maxLength):
            return "Tag name cannot exceed \(maxLength) characters"
        case .descriptionTooLong(let maxLength):
            return "Description cannot exceed \(maxLength) characters"
        case .invalidCharacters(let details):
            return details
        case .invalidColorFormat:
            return "Color must be in format #RRGGBB"
        case .invalidNodeId:
            return "Invalid node ID format"
        case .invalidSortOrder:
            return "Sort order must be non-negative"
        }
    }
}
import Foundation
import XCTest

/// Helper class to load JSON fixtures for tests
public class FixtureLoader {
    
    /// Load a fixture file from the Fixtures directory
    /// - Parameter filename: The name of the fixture file (including extension)
    /// - Returns: The Data from the file
    public static func loadFixture(named filename: String) throws -> Data {
        // Use Bundle.module for SPM resource loading (proper SPM pattern)
        guard let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.fileNotFound(filename)
        }
        
        return try Data(contentsOf: url)
    }
    
    /// Load and decode a JSON fixture
    /// - Parameters:
    ///   - filename: The name of the fixture file
    ///   - type: The type to decode into
    /// - Returns: The decoded object
    public static func loadFixture<T: Decodable>(named filename: String, as type: T.Type) throws -> T {
        let data = try loadFixture(named: filename)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public enum FixtureError: LocalizedError {
    case fileNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename):
            return "Fixture file not found: \(filename)"
        }
    }
}
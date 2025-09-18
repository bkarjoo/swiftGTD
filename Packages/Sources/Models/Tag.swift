import Foundation
import SwiftUI
import Core

public struct Tag: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let color: String?
    public let description: String?
    public let createdAt: String?
    
    public init(id: String, name: String, color: String?, description: String?, createdAt: String?) {
        self.id = id
        self.name = name
        self.color = color
        self.description = description
        self.createdAt = createdAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case description
        case createdAt = "created_at"
    }
    
    public var displayColor: Color {
        if let hexColor = color {
            return Color(hex: hexColor)
        }
        return .blue
    }
}
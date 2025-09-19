import Foundation

public struct UIState: Codable, Sendable {
    public static let currentVersion = 1

    public struct TabState: Codable, Equatable, Sendable {
        public let id: UUID
        public var title: String
        public var focusedNodeId: String?

        public init(id: UUID, title: String, focusedNodeId: String? = nil) {
            self.id = id
            self.title = title
            self.focusedNodeId = focusedNodeId
        }
    }

    public var tabs: [TabState]
    public let version: Int

    public init(tabs: [TabState] = [], version: Int = UIState.currentVersion) {
        self.tabs = tabs
        self.version = version
    }
}
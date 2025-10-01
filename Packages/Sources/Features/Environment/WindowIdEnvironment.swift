import SwiftUI

/// Environment key for window ID to support multi-window state management
public struct WindowIdKey: EnvironmentKey {
    public static let defaultValue: UUID = UUID()
}

public extension EnvironmentValues {
    var windowId: UUID {
        get { self[WindowIdKey.self] }
        set { self[WindowIdKey.self] = newValue }
    }
}

import SwiftUI

public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        #if os(iOS)
        SettingsView_iOS()
        #else
        SettingsView_macOS()
        #endif
    }
}
import SwiftUI

public struct TreeView: View {
    public init() {}
    
    public var body: some View {
        #if os(iOS)
        TreeView_iOS()
        #else
        TreeView_macOS()
        #endif
    }
}
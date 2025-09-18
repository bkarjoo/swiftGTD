import SwiftUI

public struct LoadingView: View {
    let message: String
    
    public init(message: String = "Loading...") {
        self.message = message
    }
    
    public var body: some View {
        HStack {
            ProgressView()
            Text(message)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
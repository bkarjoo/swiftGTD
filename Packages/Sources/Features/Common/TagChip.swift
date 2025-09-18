import SwiftUI
import Models

public struct TagChip: View {
    let tag: Tag
    
    public init(tag: Tag) {
        self.tag = tag
    }
    
    public var body: some View {
        Text(tag.name)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tag.displayColor.opacity(0.2))
            .foregroundColor(tag.displayColor)
            .cornerRadius(10)
    }
}
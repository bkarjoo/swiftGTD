import SwiftUI

public struct Theme {
    public struct Colors {
        public static let primary = Color.primary
        public static let secondary = Color.secondary
        
        // Node type colors
        public static let folder = Color.blue
        public static let task = Color.gray
        public static let taskCompleted = Color.blue
        public static let note = Color.orange
        public static let project = Color.purple
        public static let area = Color.indigo
        public static let smartFolder = Color.pink
        public static let template = Color.brown
        
        // Status colors
        public static let success = Color.green
        public static let warning = Color.orange
        public static let error = Color.red
        
        // Background colors
        public static let backgroundLight = Color.gray.opacity(0.1)
        public static let backgroundMedium = Color.gray.opacity(0.2)
        
        // Tag colors
        public static let tagColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .gray]
    }
    
    public struct Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 15
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 30
    }
    
    public struct Sizing {
        public static let iconSmall: CGFloat = 16
        public static let iconMedium: CGFloat = 30
        public static let iconLarge: CGFloat = 40
        public static let minTextAreaHeight: CGFloat = 150
    }
    
    public struct Layout {
        public static let defaultPadding: CGFloat = 8
        public static let sectionSpacing: CGFloat = 20
        public static let gridColumns = 4
    }
}
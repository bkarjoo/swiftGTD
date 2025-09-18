import SwiftUI

public struct Icons {
    public struct System {
        // Node types
        public static let folder = "folder"
        public static let task = "circle"
        public static let taskCompleted = "checkmark.circle.fill"
        public static let note = "note.text"
        public static let project = "star"
        public static let area = "tray.full"
        public static let smartFolder = "sparkles"
        public static let template = "doc.text"
        
        // Navigation
        public static let chevronRight = "chevron.right"
        public static let chevronDown = "chevron.down"
        public static let chevronLeft = "chevron.left"
        public static let arrowRightCircle = "arrow.right.circle"
        
        // Actions
        public static let plus = "plus"
        public static let trash = "trash"
        public static let gear = "gearshape"
        public static let edit = "pencil"
        
        // Status
        public static let checkmark = "checkmark"
        public static let xmark = "xmark"
        
        // UI Elements
        public static let list = "list.bullet"
        public static let grid = "square.grid.2x2"
        public static let tag = "tag"
    }
    
    public static func nodeIcon(for nodeType: String, isCompleted: Bool = false) -> String {
        switch nodeType {
        case "folder": return System.folder
        case "task": return isCompleted ? System.taskCompleted : System.task
        case "note": return System.note
        case "project": return System.project
        case "area": return System.area
        case "smart_folder": return System.smartFolder
        case "template": return System.template
        default: return "doc"
        }
    }
    
    public static func nodeColor(for nodeType: String, isCompleted: Bool = false) -> Color {
        switch nodeType {
        case "folder": return Theme.Colors.folder
        case "task": return isCompleted ? Theme.Colors.taskCompleted : Theme.Colors.task
        case "note": return Theme.Colors.note
        case "project": return Theme.Colors.project
        case "area": return Theme.Colors.area
        case "smart_folder": return Theme.Colors.smartFolder
        case "template": return Theme.Colors.template
        default: return Color.gray
        }
    }
}
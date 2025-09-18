# SwiftGTD Coding Standards

## Module Structure

All code MUST be placed in the appropriate module under `Packages/Sources/`:

### Core Module
**Location**: `Packages/Sources/Core/`
**Purpose**: Shared utilities, extensions, UI components
**Contains**:
- `Theme.swift` - Colors, spacing, sizing constants
- `Icons.swift` - Icon system and node icon mappings
- `Extensions/` - Color+Extensions, etc.
- `Components/` - LoadingView, TagView, FlowLayout
**Dependencies**: None
**Usage**: Import Core for any UI constants or reusable components

### Models Module
**Location**: `Packages/Sources/Models/`
**Purpose**: Data structures and domain entities
**Contains**:
- `Node.swift` - Node with TaskData and NoteData
- `Tag.swift` - Tag with color support
- `User.swift` - User, LoginRequest, SignupRequest, AuthResponse
- NodeType enum with display names
**Dependencies**: Core (for Color extensions)
**Usage**: All model structs are public and Codable

### Networking Module
**Location**: `Packages/Sources/Networking/`
**Purpose**: API communication
**Contains**:
- `APIClient.swift` - Core networking singleton with request handling
- `Endpoints/AuthEndpoints.swift` - Login, signup, getCurrentUser
- `Endpoints/NodeEndpoints.swift` - All node CRUD operations
- `Endpoints/TagEndpoints.swift` - Tag operations
- APIError enum and EmptyResponse struct
**Dependencies**: Models
**Usage**: Extensions on APIClient provide all API methods

### Services Module
**Location**: `Packages/Sources/Services/`
**Purpose**: Business logic and state management
**Contains**:
- `AuthManager.swift` - Authentication state, login/signup/logout
- `DataManager.swift` - Node and tag data management
- ObservableObject classes with @Published properties
- Logging functionality
**Dependencies**: Models, Networking
**Usage**: @StateObject or @EnvironmentObject in Views

### Features Module
**Location**: `Packages/Sources/Features/`
**Purpose**: UI views and feature-specific code
**Contains**:
- `Auth/` - LoginView
- `Nodes/` - TreeView (router), TreeView_iOS, TreeView_macOS, TreeNodeView, TreeViewModel, CreateNodeView, NodeDetailView
- `Settings/` - SettingsView (router), SettingsView_iOS, SettingsView_macOS
- `Common/` - TagChip (shared components)
**Dependencies**: Core, Models, Services, Networking
**Important**: 
- All views must have public access modifiers and public init()
- Complex views should be broken into smaller components
- Business logic should be extracted to ViewModels

## Rules

1. **NO code in main app target** - All code goes in modules
2. **Public access required** - Types used across modules must be `public`
3. **Dependencies flow down** - Features → Services → Networking → Models → Core
4. **No circular dependencies** - If needed, use protocols
5. **One file per type** - Each struct/class in its own file (except small helper views)
6. **Subfolder organization** - Group related files in subfolders
7. **Platform conditionals** - Use `#if os(iOS)` for iOS-only features
8. **Platform-specific views** - Create `ViewName_iOS.swift` and `ViewName_macOS.swift` with a router `ViewName.swift` when platform differences are significant
9. **Form workaround** - Use List with .listStyle instead of Form if compilation issues occur

## Development Logging Requirements

**MANDATORY for all development:**

1. **Use Logger Class** - Use the `Logger.shared` singleton from Core module:
   ```swift
   private let logger = Logger.shared
   logger.log("Message", category: "Component", level: .info)
   ```

2. **Comprehensive Logging** - Every significant action MUST be logged:
   - Button clicks: `logger.log("🔘 Button clicked: \(buttonName)", category: "ClassName")`
   - Function calls: `logger.log("📞 functionName called with: \(parameters)", category: "ClassName")`
   - API calls: `logger.log("🌐 Calling: \(endpoint) with: \(body)", category: "API")`
   - API responses: `logger.log("✅ Response from \(endpoint): \(response)", category: "API")`
   - API errors: `logger.log("❌ Error from \(endpoint): \(error)", category: "API", level: .error)`
   - State changes: `logger.log("🔄 State changed: \(property) from \(oldValue) to \(newValue)", category: "ClassName")`
   - Navigation: `logger.log("🧭 Navigating to: \(destination)", category: "View")`

3. **Log Files** - Logs are written to:
   - iOS: `~/Library/Developer/CoreSimulator/.../Application Support/Logs/swiftgtd.log`
   - macOS: `~/Library/Containers/com.swiftgtd.SwiftGTD-macOS/Data/Library/Application Support/Logs/swiftgtd.log`

4. **No Assumptions** - Logging must provide definitive proof of execution flow:
   - Log BEFORE attempting an action
   - Log the RESULT of the action
   - Log any ERROR conditions with full details

5. **Structured Format**:
   ```swift
   logger.log("[EMOJI] Message: relevant_data", category: "Component", level: .info)
   ```
   Emojis:
   - 🔘 UI interactions
   - 📞 Function calls
   - 🌐 API requests
   - ✅ Success
   - ❌ Errors
   - 🔄 State changes
   - 🧭 Navigation
   - ⚠️ Warnings

6. **Chain of Execution** - Log must show complete flow:
   ```swift
   logger.log("🔘 Task checkbox clicked for node: \(node.id)", category: "TreeNodeView")
   logger.log("📞 onToggleTaskStatus calling with node: \(node.title)", category: "TreeNodeView")
   logger.log("📞 toggleTaskStatus received node: \(node.id)", category: "TreeViewModel")
   logger.log("📞 toggleNodeCompletion processing node: \(node.id)", category: "DataManager")
   logger.log("🌐 PATCH /nodes/\(node.id) with status: \(value)", category: "API")
   ```

7. **NEVER** debug without logs - No guessing, no assumptions

## Adding New Code

### New Feature
1. Create subfolder in `Packages/Sources/Features/YourFeature/`
2. Import required modules
3. Make types `public` if needed by other modules

### New Model
1. Add to `Packages/Sources/Models/`
2. Make `public struct/class`
3. Add `public init` with all properties

### New API Endpoint
1. Add to `Packages/Sources/Networking/Endpoints/`
2. Follow existing pattern
3. Return Models types

### New Service
1. Add to `Packages/Sources/Services/`
2. Import Models and Networking
3. Make `public class` with `public init`

## Example

**WRONG** ❌
```swift
// In SwiftGTD/Views/NewView.swift
struct NewView: View { 
    var body: some View {
        Text("Title")
            .foregroundColor(.blue) // Hardcoded color
            .padding(8) // Magic number
    }
}
```

**CORRECT** ✅
```swift
// In Packages/Sources/Features/NewFeature/NewView.swift
import SwiftUI
import Core
import Models
import Services

public struct NewView: View {
    public init() {}
    public var body: some View {
        Text("Title")
            .foregroundColor(Theme.Colors.primary)
            .padding(Theme.Spacing.sm)
    }
}
```

## Testing Changes
After any change:
1. Run `swift build` in Packages directory
2. Build iOS app in Xcode (see XCODE_SETUP.md for configuration)
3. Verify feature works

## Main App Structure
The main app target (`SwiftGTD/`) should only contain:
- `SwiftGTDApp.swift` - App entry point
- `ContentView.swift` - Root view that switches between auth/main
- `Info.plist` - App configuration
All other code lives in the package modules.

## File Naming
- Views: `SomethingView.swift`
- Models: `Something.swift`
- Services: `SomethingManager.swift` or `SomethingService.swift`
- Extensions: `Type+Extension.swift`
- Tests: `SomethingTests.swift`

## Testing Standards

### Test Organization
1. **Test Targets** - Each module has corresponding test target:
   - `ModelsTests` tests `Models`
   - `CoreTests` tests `Core`
   - `NetworkingTests` tests `Networking`
   - `ServicesTests` tests `Services`
   - `FeaturesTests` tests `Features`

2. **Test Naming**:
   ```swift
   func testMethodName_whenCondition_shouldExpectedBehavior()
   func testToggleTask_whenOffline_shouldQueueOperation()
   ```

3. **Test Structure** - Arrange/Act/Assert:
   ```swift
   func testExample() {
       // Arrange
       let sut = SystemUnderTest()
       let input = TestData()
       
       // Act
       let result = sut.performAction(input)
       
       // Assert
       XCTAssertEqual(result, expected)
   }
   ```

4. **Mocking** - Use protocols for dependency injection:
   ```swift
   protocol APIClientProtocol {
       func makeRequest<T>(...) async throws -> T
   }
   ```

5. **Test Data** - Use fixtures in `Packages/Tests/Fixtures/`

6. **Deterministic Tests**:
   - NO network calls
   - NO timers or delays
   - NO simulator dependencies
   - NO random values without seeds

7. **Coverage Requirements**:
   - Minimum 70% for Models, Services, Networking
   - Test critical paths and edge cases
   - Test error conditions

8. **Test Documentation**:
   - Each test should be self-documenting through naming
   - Complex setup should have comments
   - Test utilities must be documented
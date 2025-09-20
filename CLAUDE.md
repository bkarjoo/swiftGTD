# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

### macOS Development
```bash
# Build and run unsigned macOS app (fastest for development)
./rebuild_unsigned_macOS.sh

# Build and run signed macOS app
./rebuild_macOS.sh
```

### iOS Development
```bash
# Build and run unsigned iOS app on simulator
./rebuild_unsigned_iOS.sh

# Build and run signed iOS app (with custom bundle ID)
./rebuild_iOS.sh [bundle_id] [simulator_id]
```

### Testing
```bash
# Run all tests
xcodebuild test -scheme SwiftGTD-macOS -destination 'platform=macOS'

# Run specific test module
xcodebuild test -scheme SwiftGTDModules -only-testing:CoreTests
xcodebuild test -scheme SwiftGTDModules -only-testing:FeaturesTests
```

## Architecture Overview

### Module-Based Architecture
The codebase uses a modular package structure with strict dependency rules. All code MUST be placed in the appropriate module under `Packages/Sources/`:

**Dependency Flow**: Features → Services → Networking → Models → Core

- **Core**: Foundation utilities, theme, icons, extensions. No dependencies.
- **Models**: Data structures (Node, Tag, User). Depends on Core.
- **Networking**: API client and endpoints. Depends on Models.
- **Services**: Business logic (AuthManager, DataManager, CacheManager). Depends on Networking, Models.
- **Features**: UI views and ViewModels. Depends on all other modules.

### Key Architectural Patterns

**MVVM with ObservableObject**
- ViewModels are `@MainActor` classes with `@Published` properties
- Views use `@StateObject` or `@ObservedObject` for ViewModels
- DataManager is passed as `@EnvironmentObject`

**Data Flow Rules (CRITICAL)**
- **Single Source of Truth**: DataManager.nodes is the ONLY source for node data
- **No Direct API Calls in Views**: ALL API calls must go through DataManager or other Services
- **TreeViewModel subscribes to DataManager**: TreeViewModel.allNodes should reflect DataManager.nodes, never maintain separate state
- **Intent-Based Actions**: Views dispatch intents to ViewModels, ViewModels orchestrate operations

**Platform-Specific Views**
When significant platform differences exist:
- `TreeView.swift` - Router that selects platform
- `TreeView_iOS.swift` - iOS implementation
- `TreeView_macOS.swift` - macOS implementation

**Node Tree Management**
- `DataManager.nodes` is the single source of truth for all node data
- `TreeViewModel` subscribes to DataManager and derives `nodeChildren` dictionary for hierarchy
- `TreeNodeView` recursively renders nodes with expand/collapse state
- Focus mode allows drilling into specific subtrees
- DO NOT maintain separate node state in ViewModels

**Offline-First Architecture**
- `CacheManager` provides persistent local storage
- `OfflineQueueManager` queues operations when offline
- Optimistic updates show changes immediately

### Critical Implementation Details

**Template Instantiation Flow (NEEDS REFACTOR)**
1. User presses Cmd+U on a template node
2. Should call DataManager.instantiateTemplate() - NOT direct API
3. DataManager updates its nodes, TreeViewModel reflects changes
4. Use `refreshNodes()` not `loadAllNodes()` (which has didLoad guard)
5. Target node expanded and new node focused

**Default Folder Feature (NEEDS REFACTOR)**
- Settings API: `GET/PUT /settings/default-node`
- Should be accessed through DataManager, not direct API calls
- Q key creates task in default folder using `createNodeParentId`
- CreateNodeSheet uses `createNodeParentId ?? focusedNodeId`

**Drag & Drop Reordering**
- Nodes conform to `Transferable` protocol
- `performReorder()` updates sort_order for all siblings
- Sort orders use 100-unit increments for future insertions

**Keyboard Navigation**
- `NSEvent.addLocalMonitorForEvents` captures keyboard events
- TabbedTreeView must handle all keycodes to prevent beeps
- Arrow keys navigate, right arrow focuses even without children

## Common Pitfalls to Avoid

1. **Never commit without user permission** - User will explicitly ask "commit"
2. **loadAllNodes() has guard** - Use `refreshNodes()` for forced refresh, rename to `initialLoad()` for clarity
3. **TabbedTreeView intercepts all keys** - Must add handler or return nil to prevent beep
4. **Public access required** - All cross-module types need `public` modifier
5. **Form compilation issues** - Use `List` with `.listStyle` instead of `Form`
6. **No inline API calls** - NEVER call `APIClient.shared` directly from views. ALL API calls must go through Services layer
7. **Two sources of truth** - Don't maintain separate node state. DataManager.nodes is the ONLY source
8. **Direct state mutations** - Don't patch ViewModel state directly. Use DataManager operations

## Logging Requirements

Every significant action MUST be logged using `Logger.shared`:
```swift
private let logger = Logger.shared
logger.log("📞 Function called", category: "ClassName")
logger.log("✅ Success", category: "API")
logger.log("❌ Error: \(error)", category: "API", level: .error)
```

Log files location:
- iOS: `~/Library/Developer/CoreSimulator/.../Logs/swiftgtd.log`
- macOS: `~/Library/Containers/.../Logs/swiftgtd.log`

## API Backend

The app connects to a GTD backend (separate repository) via URL in `Config.xcconfig`.
Key endpoints:
- `/auth/` - Login, signup, user management
- `/nodes/` - CRUD operations for all node types
- `/tags/` - Tag management
- `/rules/` - Smart folder rules
- `/settings/default-node` - Default folder setting
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

**Data Flow Architecture (Post-Refactor)**
- **Single Source of Truth**: `DataManager.nodes` is the authoritative data source
- **No Direct API Calls**: Features module never calls APIClient directly
- **Centralized Updates**: All data mutations go through DataManager
- **Subscription Model**: TreeViewModel subscribes to DataManager.nodes changes via Combine
- **Data Consistency**: Parent-child relationships maintained through invariants
- **Intent-Based Actions**: Views dispatch intents to ViewModels, ViewModels orchestrate operations
- **Targeted Refresh**: `refreshNode()` fetches node + children, removes orphaned descendants
- **Eventual Consistency**: Template instantiation uses retry logic for server sync delays

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

**Template Instantiation Flow**
1. User presses Cmd+U on a template node
2. TreeViewModel calls DataManager.instantiateTemplate()
3. DataManager returns new node immediately (no sync)
4. TreeViewModel implements retry logic with targeted refreshNode(parentId)
5. Target node expanded and new node focused after retry succeeds

**Default Folder Feature**
- Settings API: `GET/PUT /settings/default-node`
- Accessed through DataManager.getDefaultFolder/setDefaultFolder
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

## Recent Architecture Refactoring (Phases 1-6)

### Phase 1: Single Source of Truth ✅
- Removed direct API calls from Features module
- TreeViewModel now subscribes to DataManager.nodes
- All data operations go through DataManager

### Phase 2: Fix Subscriptions ✅
- TreeViewModel properly subscribes to DataManager.$nodes
- Removed duplicate state management
- Fixed Combine subscription chain

### Phase 3: Route All Operations ✅
- Template instantiation through DataManager
- Smart folder execution through DataManager
- Tag operations through DataManager

### Phase 4: Centralize UI Operations ✅
- Keyboard handling centralized in handleKeyPress()
- Navigation logic consolidated in navigateToNode()
- State management through intent methods

### Phase 5: Ensure Data Consistency ✅
- Parent-child invariants maintained
- Subtree removal on parent refresh
- Retry logic for eventual consistency
- Debug validation with validateNodeConsistency()

### Phase 6: Clean Up and Document ✅
- Removed excessive logging
- Updated documentation
- No duplicate refresh implementations

## Key Methods and Their Purpose

**TreeViewModel Methods**
- `initialLoad()` - First-time load with didLoad guard, runs once per view lifecycle
- `refreshNodes()` - Force full refresh from server, bypasses didLoad guard
- `refreshNode(nodeId)` - Targeted refresh of single node via DataManager
- `handleKeyPress()` - Centralized keyboard handling for all shortcuts
- `navigateToNode()` - Unified navigation logic for arrow keys
- `validateNodeConsistency()` - Debug-only validation of parent-child invariants

**DataManager Methods**
- `syncAllData()` - Full sync from server or cache fallback
- `refreshNode(nodeId)` - Fetch node + children, remove orphaned descendants
- `instantiateTemplate()` - Create from template, no sync (caller handles retry)
- `syncPendingOperations()` - Process offline queue when network restored

## Common Pitfalls to Avoid

1. **Never commit without user permission** - User will explicitly ask "commit"
2. **initialLoad() has guard** - Use `refreshNodes()` for forced refresh
3. **TabbedTreeView intercepts all keys** - Must add handler or return nil to prevent beep
4. **Public access required** - All cross-module types need `public` modifier
5. **Form compilation issues** - Use `List` with `.listStyle` instead of `Form`
6. **No inline API calls** - NEVER call `APIClient.shared` directly from views. ALL API calls must go through Services layer
7. **Two sources of truth** - Don't maintain separate node state. DataManager.nodes is the ONLY source
8. **Direct state mutations** - Don't patch ViewModel state directly. Use DataManager operations

## Logging Requirements

Log only essential information using `Logger.shared`:
```swift
private let logger = Logger.shared
// Log errors and warnings
logger.log("❌ Error: \(error)", category: "API", level: .error)
logger.log("⚠️ Warning: cache miss", category: "Cache", level: .warning)
// Log critical state changes
logger.log("🔄 Sync completed", category: "DataManager")
// DO NOT log routine operations, function entries, or trivial state updates
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
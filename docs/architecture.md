# SwiftGTD Architecture

## Module Dependency Flow

```
┌──────────────┐
│   Features   │  UI Views & ViewModels
└──────┬───────┘  - TreeViewModel, NodeDetailsViewModel
       │          - TreeView_iOS, TreeView_macOS
       ▼
┌──────────────┐
│   Services   │  Business Logic & State Management
└──────┬───────┘  - DataManager (single source of truth)
       │          - AuthManager, CacheManager, OfflineQueue
       ▼
┌──────────────┐
│  Networking  │  API Communication
└──────┬───────┘  - APIClient, Endpoints
       │          - Request/Response handling
       ▼
┌──────────────┐
│    Models    │  Data Structures
└──────┬───────┘  - Node, Tag, User, Rule
       │          - Codable definitions
       ▼
┌──────────────┐
│     Core     │  Foundation Utilities
└──────────────┘  - Logger, Theme, Extensions
```

## Data Flow Architecture

### Single Source of Truth
```
DataManager.nodes ─────┬──► TreeViewModel (subscribes)
(Published array)      │
                      └──► Other ViewModels
```

### Node Operations Flow

#### Create/Update/Delete
```
View ──► ViewModel ──► DataManager ──► APIClient ──► Server
                           │
                           └──► Update nodes array
                                      │
                                      ▼
                              TreeViewModel updates
                              (via Combine subscription)
```

#### Targeted Refresh (refreshNode)
```
1. DataManager.refreshNode(nodeId)
   ├─► Fetch node from API
   ├─► Fetch direct children from API
   ├─► Remove orphaned descendants (subtree removal)
   ├─► Upsert node and children
   └─► nodes array updated → triggers subscriptions
```

#### Template Instantiation with Retry
```
1. User presses Cmd+U
2. TreeViewModel.instantiateTemplate()
   ├─► DataManager.instantiateTemplate() - returns immediately
   └─► Retry loop (up to 3x)
       ├─► Check if node appears in allNodes
       ├─► If not found: wait 500ms
       └─► refreshNode(parentId) - fetch updated children
```

## Key Architectural Patterns

### 1. Subscription Model
- TreeViewModel subscribes to `DataManager.$nodes`
- Automatic UI updates when data changes
- No manual state synchronization needed

### 2. Data Consistency
- Parent-child invariants maintained
- `validateNodeConsistency()` in DEBUG builds
- Subtree removal prevents orphaned nodes

### 3. Offline-First
- CacheManager for persistent storage
- OfflineQueue for pending operations
- Optimistic updates with eventual consistency

### 4. Centralized Operations
- All keyboard handling in `handleKeyPress()`
- All navigation in `navigateToNode()`
- All data mutations through DataManager

## Critical Invariants

1. **Single Source**: DataManager.nodes is the ONLY source for node data
2. **No Direct API**: Features never call APIClient directly
3. **Parent-Child Consistency**: Every child's parentId must exist in nodes
4. **Subtree Integrity**: Deleting a node removes all descendants
5. **Targeted Refresh**: refreshNode fetches node + children, not entire tree
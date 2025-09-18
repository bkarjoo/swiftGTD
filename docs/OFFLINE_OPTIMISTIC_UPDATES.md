# Offline Optimistic Updates Implementation

## Overview
The offline queuing system now provides optimistic local updates when operations are performed offline. This ensures immediate UI feedback even when the network is unavailable.

## Current Implementation

### DataManager.updateNode()
When offline, the method:
1. Queues the update operation via `OfflineQueueManager`
2. Creates an optimistic local update by reconstructing the Node (due to immutability)
3. Updates the local cache
4. Returns the updated Node for immediate UI feedback

### Fields Currently Supported
The optimistic update currently applies:
- **title**: Updated from `NodeUpdate.title`
- **noteData.body**: Updated from `NodeUpdate.noteData.body` if present
- **updatedAt**: Set to current timestamp
- **parentId**: Updated from `NodeUpdate.parentId` if provided
- **sortOrder**: Updated from `NodeUpdate.sortOrder`

### Node Reconstruction
Due to Node's immutable properties (all fields are `let`), we must reconstruct the entire Node object:

```swift
let updatedNode = Node(
    id: oldNode.id,
    title: update.title,  // Applied
    nodeType: oldNode.nodeType,
    parentId: update.parentId ?? oldNode.parentId,  // Applied
    ownerId: oldNode.ownerId,
    createdAt: oldNode.createdAt,
    updatedAt: ISO8601DateFormatter().string(from: Date()),  // Applied
    sortOrder: update.sortOrder,  // Applied
    isList: oldNode.isList,
    childrenCount: oldNode.childrenCount,
    tags: oldNode.tags,
    taskData: oldNode.taskData,  // TODO: Apply task updates
    noteData: update.noteData != nil ? NoteData(
        body: update.noteData?.body  // Applied
    ) : oldNode.noteData,
    templateData: oldNode.templateData,  // TODO: Apply template updates
    smartFolderData: oldNode.smartFolderData  // TODO: Apply smart folder updates
)
```

## TODOs for Extension

### 1. Task Data Updates
Location: `DataManager.swift:290`
```swift
// TODO: Apply task updates if present
taskData: update.taskData != nil ? TaskData(
    description: update.taskData?.description ?? oldNode.taskData?.description,
    status: update.taskData?.status ?? oldNode.taskData?.status,
    priority: update.taskData?.priority ?? oldNode.taskData?.priority,
    dueAt: update.taskData?.dueAt ?? oldNode.taskData?.dueAt,
    earliestStartAt: update.taskData?.earliestStartAt ?? oldNode.taskData?.earliestStartAt,
    completedAt: update.taskData?.completedAt ?? oldNode.taskData?.completedAt,
    archived: update.taskData?.archived ?? oldNode.taskData?.archived
) : oldNode.taskData
```

### 2. Template Data Updates
Location: `DataManager.swift:294`
```swift
// TODO: Apply template updates if present
templateData: update.templateData != nil ? TemplateData(
    description: update.templateData?.description ?? oldNode.templateData?.description,
    category: update.templateData?.category ?? oldNode.templateData?.category,
    usageCount: update.templateData?.usageCount ?? oldNode.templateData?.usageCount,
    targetNodeId: update.templateData?.targetNodeId ?? oldNode.templateData?.targetNodeId,
    createContainer: update.templateData?.createContainer ?? oldNode.templateData?.createContainer
) : oldNode.templateData
```

### 3. Smart Folder Data Updates
Location: `DataManager.swift:295`
```swift
// TODO: Apply smart folder updates if present
smartFolderData: update.smartFolderData != nil ? SmartFolderData(
    ruleId: update.smartFolderData?.ruleId ?? oldNode.smartFolderData?.ruleId,
    rules: oldNode.smartFolderData?.rules,  // Complex field, not in update
    autoRefresh: update.smartFolderData?.autoRefresh ?? oldNode.smartFolderData?.autoRefresh,
    description: update.smartFolderData?.description ?? oldNode.smartFolderData?.description
) : oldNode.smartFolderData
```

## Testing Considerations

### Tests That Need Updates
1. **TreeViewModel Tests**
   - Test that `updateNodeTitle` returns an updated node even when offline
   - Verify the node has the new title immediately
   - Confirm the operation is queued for sync

2. **NoteEditorView Tests**
   - Test that save operations complete successfully when offline
   - Verify optimistic updates are applied
   - Check that `hasUnsavedChanges` is cleared even offline

3. **DataManager Tests**
   - Test optimistic update logic for various field combinations
   - Verify cache is updated with optimistic changes
   - Ensure queued operations contain correct update data

### Example Test Updates
```swift
// Before (assumed direct API call)
func testUpdateNodeTitle() async {
    // Mock API to fail
    mockAPI.shouldFail = true

    let result = await viewModel.updateNodeTitle(nodeId: "123", newTitle: "New")

    XCTAssertNil(result)  // Expected nil when offline
}

// After (with optimistic updates)
func testUpdateNodeTitle() async {
    // Mock network as offline
    mockNetworkMonitor.isConnected = false

    let result = await viewModel.updateNodeTitle(nodeId: "123", newTitle: "New")

    XCTAssertNotNil(result)  // Now returns optimistic update
    XCTAssertEqual(result?.title, "New")  // Title is updated
    XCTAssertTrue(offlineQueue.pendingOperations.contains {
        $0.type == .updateNode && $0.nodeId == "123"
    })  // Operation is queued
}
```

## Benefits
1. **Immediate UI Feedback**: Users see their changes instantly
2. **Consistent UX**: Same behavior online and offline
3. **Reduced Perceived Latency**: No waiting for network round trips
4. **Better Offline Experience**: Full functionality when disconnected

## Limitations
1. **Node Immutability**: Requires full reconstruction for any change
2. **Complex Fields**: Some fields (like smart folder rules) may be harder to merge
3. **Conflict Resolution**: Not yet implemented for when offline changes conflict with server state
4. **Memory Usage**: Creating new Node objects for each update

## Future Enhancements
1. Implement conflict resolution strategy
2. Add visual indicators for pending sync operations
3. Create a Node builder pattern to simplify reconstruction
4. Consider making Node properties mutable with `var` for easier updates
5. Add retry logic with exponential backoff for failed syncs
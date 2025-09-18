# TODO: Coding Standards Compliance Issues

## Files Audited
- TreeView_macOS.swift
- TreeView_iOS.swift
- TreeViewModel.swift
- TreeNodeView.swift
- NodeDetailsView_macOS.swift
- NodeDetailsView_iOS.swift
- NodeDetailsViewModel.swift

## Missing Logging Per CODING_STANDARDS.md

### TreeView_macOS.swift
1. **Missing function call logging:**
   - `moveToNextSibling()` - No logging at start of function
   - `moveToPreviousSibling()` - No logging at start of function
   - `moveToFirstChild()` - No logging at start of function
   - `moveToParent()` - No logging at start of function
   - `setupKeyEventMonitor()` - No logging
   - `findLastVisibleDescendant()` - No logging
   - `getSiblings()` - No logging
   - `executeSmartFolderRule()` - Needs logging for start/end/result
   - `instantiateTemplate()` - Needs logging for start/end/result

2. **Missing state change logging:**
   - When `selectedNodeId` changes in move functions
   - When `expandedNodes` changes
   - When `focusedNodeId` changes

3. **Missing navigation logging:**
   - Each navigation action should log where it's navigating from/to

### NodeDetailsView_macOS.swift
1. **Missing button click logging:**
   - Sort order decrease button (line 184) - No logging
   - Sort order increase button (line 200) - No logging
   - Tags "Manage" button (line 241) - No logging
   - Template target node picker button (line 369) - No logging
   - Smart folder rule picker button - No logging
   - Parent picker "Cancel" button (line 653) - No logging
   - Parent picker "None" button (line 677) - No logging
   - Parent picker node selection buttons (line 700) - No logging
   - Target node picker buttons - Similar missing logging

2. **Missing state change logging:**
   - TextField changes for title, sortOrder, description, etc.
   - Picker changes for status, priority, etc.
   - Date picker changes

### NodeDetailsViewModel.swift
1. **Missing chain of execution logging:**
   - `updateField()` - Should log old value and new value
   - `checkForChanges()` - Should log what changed
   - `cancel()` - Missing logging entirely
   - `reloadTagsOnly()` - Needs complete chain logging
   - `setTreeViewModel()` - Should log when parent change will move selection

2. **Missing error logging:**
   - More detailed error information in catch blocks

### TreeViewModel.swift
1. **Missing function call logging:**
   - `setDataManager()` - Has some logging but missing parameter details
   - `updateNodesFromDataManager()` - No logging
   - `getRootNodes()` - No logging
   - `getChildren()` - No logging
   - `getParentChain()` - No logging
   - `updateSingleNode()` - Has start log but missing completion/error
   - `toggleTaskStatus()` - Missing
   - `deleteNode()` - Missing

### TreeNodeView.swift
1. **Missing button/gesture logging:**
   - Double tap gesture - No logging
   - Context menu button clicks - No logging for each action
   - Expand/collapse button clicks - No logging

### Common Issues Across All Files

1. **Incomplete chain of execution:**
   - Need to show complete flow from UI interaction → ViewModel → DataManager → API
   - Example: When toggling a task, should see:
     ```
     TreeNodeView: "🔘 Task checkbox clicked for node: abc123"
     TreeNodeView: "📞 onToggleTaskStatus calling with node: Task Title"
     TreeViewModel: "📞 toggleTaskStatus received node: abc123"
     DataManager: "📞 toggleNodeCompletion processing node: abc123"
     API: "🌐 PATCH /nodes/abc123 with status: done"
     API: "✅ Response from /nodes/abc123: {updated node}"
     DataManager: "✅ Node updated in cache"
     TreeViewModel: "✅ UI updated with new status"
     ```

2. **Missing parameter details:**
   - Functions should log their input parameters
   - Example: `loadNode(nodeId: "abc")` should log the nodeId

3. **Missing result logging:**
   - Functions should log what they return/accomplish
   - Example: After loading nodes, log how many were loaded

4. **Inconsistent emoji usage:**
   - Should follow the standard emoji guide:
     - 🔘 UI interactions
     - 📞 Function calls
     - 🌐 API requests
     - ✅ Success
     - ❌ Errors
     - 🔄 State changes
     - 🧭 Navigation
     - ⚠️ Warnings

## Recommendations

1. Add a logging wrapper/helper that enforces the format
2. Consider adding debug assertions to ensure critical paths are logged
3. Create code snippets/templates for common logging patterns
4. Add linting rules to check for logging in key functions
5. Ensure all keyboard shortcuts follow the pattern:
   ```swift
   logger.log("⌨️ [Key combo] pressed - [action]", category: "TreeView")
   // perform action
   logger.log("✅ [Action] completed: [result]", category: "TreeView")
   ```

## Priority Order for Fixes

1. **High Priority** - User-facing actions without logging:
   - All button clicks
   - All keyboard shortcuts
   - All navigation actions

2. **Medium Priority** - State management:
   - State changes
   - Data updates
   - Selection changes

3. **Low Priority** - Helper functions:
   - Utility functions
   - View builders
   - Computed properties

## Notes

- Current logging is better than most files, but still missing comprehensive coverage
- TreeView_macOS has good keyboard shortcut logging but missing navigation function logging
- NodeDetailsView has some button logging but many are missing
- Need to ensure "No guessing, no assumptions" principle is followed
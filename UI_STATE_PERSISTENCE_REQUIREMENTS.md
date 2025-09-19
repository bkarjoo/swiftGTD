# UI State Persistence Requirements

## Problem Statement
When SwiftGTD is closed and reopened, users lose their workspace context - open tabs and focused nodes are not preserved.

## Scope
Persist only:
1. **Open tabs** (their names)
2. **Focused node ID** per tab

## Technical Architecture

### 1. UIState Model
```swift
struct UIState: Codable {
    struct TabState: Codable {
        let id: UUID
        let title: String
        let focusedNodeId: String?
    }

    let tabs: [TabState]
}
```

### 2. Storage Strategy
- Save to a JSON file in app's Application Support directory
- Save immediately on:
  - Tab opened/closed
  - Tab renamed
  - Focus changed in any tab

### 3. State Restoration Logic
On app launch:
1. Load saved state from file
2. Recreate tabs with saved names
3. For each tab:
   - If focused node still exists → restore focus
   - If focused node was deleted → reset to root (no focus)

## Implementation Details

### Save Triggers
- `TabbedTreeView.tabs` array changes (add/remove)
- `TabModel.title` changes
- `TreeViewModel.focusedNodeId` changes

### File Location
```
~/Library/Application Support/SwiftGTD/ui-state.json
```

### Error Handling
- If state file is corrupted → start fresh with single "Main" tab
- If focused node doesn't exist → silently reset to root
- No user-facing errors for state persistence issues

## Code Changes Required

1. **Add UIState.swift** - Model for persisted state
2. **Add UIStateManager.swift** - Handle save/load operations
3. **Modify TabbedTreeView.swift** - Add save triggers and restore logic
4. **Modify TabModel** - Track when focus changes

## Sample Implementation Flow

```swift
// On focus change in TreeViewModel
.onChange(of: focusedNodeId) { newValue in
    UIStateManager.shared.saveFocus(newValue, forTab: tabId)
}

// On tab creation/deletion
func addTab() {
    // ... existing code
    UIStateManager.shared.saveState(tabs)
}

// On app launch
.onAppear {
    let restoredState = UIStateManager.shared.loadState()
    restoreTabs(from: restoredState)
}
```

## Important Notes
- The `ui-state.json` file should be added to `.gitignore` as it's user-specific
- No window position/size persistence
- No expanded/collapsed state persistence
- No "Reset Workspace" option needed
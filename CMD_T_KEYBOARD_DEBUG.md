# Cmd+T Keyboard Shortcut Debug Investigation

## Problem Statement
- **Primary Issue**: Cmd+T doesn't open the tag picker
- **Critical Side Effect**: After pressing Cmd+T, ALL keyboard shortcuts stop working completely
- **Impact**: The entire keyboard event monitor appears to break after Cmd+T is pressed

## Investigation Findings

### Code Flow Analysis

#### When Cmd+T is pressed:
1. **TabbedTreeView.setupKeyEventMonitor** receives the event
2. Checks if Cmd modifier is pressed (line 327) ✓
3. Hits case 17 for T key (line 330) ✓
4. Checks if Shift is pressed (line 331) - NO, so it's not Cmd+Shift+T
5. Falls through with `break` statement (line 338) ✓
6. Exits the command switch block (line 422) ✓
7. Delegates to `viewModel.handleKeyPress` (line 431) ✓
8. **TreeViewModel.handleKeyPress** processes the key:
   - Checks for Cmd modifier (line 579) ✓
   - Hits case 17 for T in command block (line 607) ✓
   - Calls `performAction(.showTags)` (line 608) ✓
9. **TreeViewModel.performAction** executes:
   - Uses `nodeId ?? selectedNodeId` for target (line 783) - **ISSUE #1: Missing focusedNodeId fallback**
   - If no selectedNodeId, returns early (line 786) ❌
   - Returns without performing the action
10. **handleKeyPress** returns false (unhandled)
11. **TabbedTreeView** receives false from handleKeyPress
12. Hits the unhandled modifier key check (lines 438-440)
13. Returns `nil` to consume the event (line 440) - **ISSUE #2: May be breaking the monitor**

### Root Causes Identified

#### Issue #1: Missing focusedNodeId Fallback
**Location**: TreeViewModel.swift line 783
```swift
let targetNodeId = nodeId ?? selectedNodeId  // Should be: nodeId ?? selectedNodeId ?? focusedNodeId
```
- When no node is selected, performAction returns early without executing
- This causes handleKeyPress to return false
- The tag picker never opens

#### Issue #2: Missing Break Statement After Cmd+W
**Location**: TabbedTreeView.swift line 346
```swift
case 13: // Cmd+W - Close tab
    if let tabId = self.selectedTabId {
        logger.log("✅ HANDLED: Cmd+W - Close tab", category: "KEYBOARD")
        self.closeTab(tabId)
        return nil
    }
    logger.log("⚠️ Cmd+W but no selected tab", category: "KEYBOARD")
    // MISSING: break statement here, falls through to tab switching

// Tab switching
case 18: // Cmd+1
```
- When Cmd+W is pressed with no tab to close, execution falls through
- Could cause unexpected behavior in keyboard handling

#### Issue #3: Event Consumption Strategy
**Location**: TabbedTreeView.swift lines 438-440
```swift
if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
    logger.log("⚠️ Unhandled shortcut - consuming to prevent issues", category: "KEYBOARD")
    return nil
}
```
- Consumes ALL unhandled modifier key events
- This was added in Attempt 3 to prevent keyboard handling from breaking
- Ironically, this might be what's breaking the keyboard monitor

### Why Keyboard Stops Working After Cmd+T

**Theory**: The keyboard monitor might be encountering an exception or state corruption when:
1. Cmd+T fails to handle properly (returns false from TreeViewModel)
2. TabbedTreeView consumes the event by returning nil
3. Something about this specific key combination (Cmd+T) triggers a system-level issue
4. The NSEvent monitor gets into a bad state or is removed

**Evidence**:
- Arrow keys work initially before Cmd+T
- After Cmd+T, NO keyboard events are processed
- The monitor itself appears to stop receiving events
- No crash or error messages visible

## Previous Attempts (from TODO_KEYBOARD_DEBUG.md)

### ✅ Attempt 1: Make Cmd+T explicitly call performAction(.showTags)
- **Result**: Build error - wrong method signature
- **Status**: FAILED - Reverted

### ✅ Attempt 2: Fix performAction to use focusedNodeId fallback
- **Result**: Still doesn't work, Cmd+T still breaks keyboard
- **Status**: FAILED - Change still in code but incomplete

### ✅ Attempt 3: Fix control flow for unhandled keys
- **Result**: Didn't fix the issue, might be making it worse
- **Status**: FAILED - Change still in code

### ✅ Attempt 4: Add missing break for Cmd+W
- **Result**: Fixed potential fall-through bug, but unrelated to Cmd+T
- **Status**: COMPLETED - But didn't solve main issue

### ✅ Attempt 5: Add logging to debug keyboard monitor
- **Result**: Discovered logs aren't writing to file properly
- **Status**: REVEALED ISSUE - App logs aren't working

### ✅ Attempt 6: Kill zombie Xcode debug process
- **Result**: Cleaned up zombie, but keyboard still breaks
- **Status**: COMPLETED - But didn't solve main issue

## Proposed Fix Strategy

### Step 1: Fix the focusedNodeId Fallback
**File**: TreeViewModel.swift line 783
```swift
// Change from:
let targetNodeId = nodeId ?? selectedNodeId

// To:
let targetNodeId = nodeId ?? selectedNodeId ?? focusedNodeId
```
This ensures performAction works even when no node is selected.

### Step 2: Add Missing Break Statement
**File**: TabbedTreeView.swift after line 346
```swift
case 13: // Cmd+W - Close tab
    if let tabId = self.selectedTabId {
        logger.log("✅ HANDLED: Cmd+W - Close tab", category: "KEYBOARD")
        self.closeTab(tabId)
        return nil
    }
    logger.log("⚠️ Cmd+W but no selected tab", category: "KEYBOARD")
    break  // ADD THIS LINE
```
Prevents fall-through to tab switching code.

### Step 3: Fix Event Consumption Logic
**File**: TabbedTreeView.swift lines 436-444

**Option A**: Don't consume unhandled Cmd+T specifically
```swift
if handled {
    logger.log("✅✅✅ TreeViewModel HANDLED the key - returning nil", category: "KEYBOARD")
    return nil
} else {
    // Special case: Let Cmd+T pass through if unhandled to avoid breaking keyboard
    if modifiers.contains(.command) && keyCode == 17 {
        logger.log("⚠️ Cmd+T unhandled - passing through", category: "KEYBOARD")
        return event
    }

    // For other unhandled shortcuts, consume them
    if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
        logger.log("⚠️ Unhandled shortcut - consuming to prevent issues", category: "KEYBOARD")
        return nil
    }
    // For plain keys without modifiers, let the system handle them
    logger.log("❌ TreeViewModel DID NOT handle plain key - passing through", category: "KEYBOARD")
    return event
}
```

**Option B**: Always pass through unhandled events
```swift
if handled {
    logger.log("✅✅✅ TreeViewModel HANDLED the key - returning nil", category: "KEYBOARD")
    return nil
} else {
    logger.log("❌ TreeViewModel DID NOT handle key - passing through", category: "KEYBOARD")
    return event
}
```

### Step 4: Ensure Tag Picker Shows Properly
Need to verify that `performAction(.showTags)` actually triggers the tag picker sheet when it has a valid node.

## Test Plan

1. **Test Initial State**
   - Launch app
   - Verify arrow keys work
   - Verify other shortcuts work

2. **Test Cmd+T Without Selection**
   - Clear any selection
   - Press Cmd+T
   - Verify tag picker appears for focused node
   - Verify keyboard still works after

3. **Test Cmd+T With Selection**
   - Select a node
   - Press Cmd+T
   - Verify tag picker appears
   - Verify keyboard still works after

4. **Test Other Shortcuts After Cmd+T**
   - Press Cmd+T
   - Close tag picker
   - Test arrow keys
   - Test Cmd+N, Cmd+Shift+N
   - Test Tab key navigation

5. **Test Cmd+W Edge Case**
   - Close all tabs except one
   - Press Cmd+W (should do nothing)
   - Verify keyboard still works

## Additional Investigation Needed

1. **Check if NSEvent monitor is still active**
   - Add logging to check if monitor is nil after Cmd+T
   - Check if setupKeyEventMonitor is being called multiple times

2. **Check for exceptions**
   - Wrap keyboard handler in try/catch
   - Log any exceptions that occur

3. **Check first responder chain**
   - Log NSApp.keyWindow before/after Cmd+T
   - Check if focus changes unexpectedly

4. **System-level conflicts**
   - Check if macOS has a system-wide Cmd+T shortcut
   - Test in a clean user account

## Files Involved

1. **TabbedTreeView.swift** - Main keyboard event monitor setup
2. **TreeViewModel.swift** - Keyboard handling logic and actions
3. **TreeView_macOS.swift** - Platform-specific tree view
4. **TagPickerView.swift** - Tag picker sheet implementation

## Current State of Code

### Changes Still in Place:
1. ❌ TreeViewModel.performAction uses incomplete fallback (line 783) - needs focusedNodeId
2. ⚠️ TabbedTreeView consumes all unhandled modifier keys (lines 438-440) - may be problematic
3. ❌ Missing break after Cmd+W when no tab selected (line 346)
4. ✅ Debug logging added throughout keyboard handling

## Logger Information

### ⚠️ IMPORTANT: Correct Log File Location
The new logger (as of 2025-09-30 16:29 PDT) writes to:
```
~/Library/Application Support/Logs/swiftgtd.log
```

**DO NOT** check the old containerized location which has stale logs:
```
~/Library/Containers/com.swiftgtd.SwiftGTD-macOS/Data/Library/Application Support/Logs/swiftgtd.log
```

The old location contains logs from September 25th and earlier. Always use the new location to see current activity.

### Logger Features
- Uses Apple's unified logging system (os.log)
- ISO 8601 timestamps with UTC timezone (Z suffix)
- Categories for different subsystems (KEYBOARD, NAVIGATION, etc.)
- File names and line numbers in debug builds
- Automatic log rotation at 10MB
- Successfully captures all keyboard events, navigation, and state changes

## Implementation Status

### ❌ Attempt 7: Fix focusedNodeId fallback, break statement, and event consumption (2025-09-30)

1. **Fixed focusedNodeId Fallback**
   - File: TreeViewModel.swift line 783
   - Changed: `nodeId ?? selectedNodeId` → `nodeId ?? selectedNodeId ?? focusedNodeId`
   - Expected: performAction would work even when no node is selected
   - **Result: FAILED - Issue persists**

2. **Added Missing Break Statement**
   - File: TabbedTreeView.swift line 347
   - Added: `break` statement after Cmd+W with no tab
   - Expected: Prevent fall-through to tab switching code
   - **Result: FAILED - Doesn't fix Cmd+T issue**

3. **Fixed Event Consumption Logic**
   - File: TabbedTreeView.swift lines 437-440
   - Changed: Removed aggressive event consumption, now passes through all unhandled events
   - Expected: Keyboard monitor would remain functional
   - **Result: FAILED - Keyboard still breaks after Cmd+T**

### Build Status
✅ App builds successfully with all fixes applied
⚠️ Two warnings present (unrelated to keyboard handling):
- Unreachable catch block in TreeViewModel.swift:262
- Unused value 'updatedNode' in TreeViewModel.swift:421

### Test Results
❌ **Cmd+T still doesn't open tag picker**
❌ **Keyboard shortcuts still stop working after pressing Cmd+T**
❌ **The core issue remains unresolved**

## Success Criteria

1. ❌ Cmd+T opens tag picker when a node is focused or selected
2. ❌ All keyboard shortcuts continue working after Cmd+T is pressed
3. ❌ No keyboard events are lost or blocked
4. ❌ Event monitor remains active and functional
5. ✅ No fall-through bugs in switch statements (fixed but didn't solve main issue)

## ❌ Attempt 8: Comprehensive Diagnostic Logging (2025-09-30)

### Changes Made:
1. Added "MONITOR ALIVE" logging on every keyDown event received
2. Added Cmd+T specific logging throughout the handling chain
3. Added exception handling around handleKeyPress
4. Added logging to track showingTagPickerForNode state
5. Added Cmd+G as alternative test key for showTags
6. Added logging when tag picker sheet is presented

### Test Results:
**Log analysis from user test at 21:04 UTC:**

```
21:04:31-35Z: Multiple "MONITOR ALIVE" messages - keyboard working normally (arrow key navigation)
21:04:36Z: Cmd+T pressed:
  - MONITOR ALIVE received the event ✅
  - Cmd+T detected - calling performAction(.showTags) ✅
  - performAction(.showTags) called ✅
  - performAction(.showTags) completed ✅
  - Cmd+T handling result: true ✅
  - Monitor still active: true ✅
  - showingTagPickerForNode: Download 2023 ✅ (node was set!)
21:04:36-37Z: Two more "MONITOR ALIVE" messages received AFTER Cmd+T ✅
```

### Critical Findings:
1. **Monitor remains active** - The keyboard monitor is NOT being destroyed
2. **Cmd+T is handled successfully** - Returns true, completes without errors
3. **showingTagPickerForNode IS set** - The node "Download 2023" was assigned
4. **Monitor continues receiving events** - At least 2 keyDown events received after Cmd+T
5. **NO sheet presentation log** - The UI-SHEET log for actual presentation never appears

### Missing Pieces:
- performAction(.showTags) logs are missing the node details (lines 822-823 didn't log)
- Sheet presentation log never fired - sheet isn't actually being presented
- But keyboard continues working based on MONITOR ALIVE logs after Cmd+T

### New Discovery:
**The keyboard is NOT actually breaking!** The monitor stays active and continues receiving events. The issue seems to be:
1. The tag picker sheet is not being presented despite showingTagPickerForNode being set
2. But the keyboard monitor continues to work (contrary to what was reported)

## Attempt 8 Analysis:

### What the logs show:
1. **Before Cmd+T (21:04:31-35)**: Multiple MONITOR ALIVE messages show keyboard navigation working
2. **During Cmd+T (21:04:36)**:
   - Event received by monitor
   - Cmd+T properly detected and routed to performAction
   - showingTagPickerForNode successfully set to "Download 2023"
   - Handler returned true (successfully handled)
   - Monitor confirmed still active
3. **After Cmd+T (21:04:36-37)**: Two more MONITOR ALIVE events received - but user reports keyboard NOT working

### Key observation:
The monitor is still receiving keyDown events (MONITOR ALIVE logs) but the keyboard is not functioning. This means:
- The NSEvent monitor is still installed and receiving events
- But the events are not being processed correctly after Cmd+T
- The keyboard is effectively broken despite the monitor being alive

## Where are we at now

### What we've tried (8 attempts):
1. Made Cmd+T explicitly call performAction(.showTags) - FAILED
2. Fixed performAction to use focusedNodeId fallback - FAILED
3. Fixed control flow for unhandled keys - FAILED
4. Added missing break for Cmd+W - FAILED
5. Added logging to debug keyboard monitor - Revealed logging issues
6. Killed zombie Xcode debug process - FAILED
7. Fixed focusedNodeId fallback, break statement, and event consumption - FAILED
8. Added comprehensive diagnostic logging - Revealed monitor stays alive but keyboard still breaks

### What we've learned:
1. **The monitor doesn't die**: NSEvent.addLocalMonitorForEvents continues receiving events after Cmd+T
2. **Cmd+T is handled "successfully"**: Returns true, sets showingTagPickerForNode to a valid node
3. **No exceptions thrown**: The exception handling catches nothing
4. **The tag picker never shows**: Despite showingTagPickerForNode being set, the sheet doesn't present
5. **Events arrive but don't work**: MONITOR ALIVE logs prove events are received, but keyboard is non-functional

### What could be the problem:
1. **Event consumption issue**: After Cmd+T returns nil (consumed), subsequent events might be hitting a different code path
2. **State corruption**: showingTagPickerForNode being non-nil might be blocking keyboard processing (line 316 checks this)
3. **SwiftUI binding issue**: The sheet might be trying to present but failing, leaving the app in a bad state
4. **Focus/responder chain**: Something about Cmd+T changes the responder chain even though no sheet appears

### Why is this so complicated?
1. **Multiple layers of indirection**:
   - TabbedTreeView → TreeViewModel → performAction → sheet binding
   - Each layer can fail silently

2. **NSEvent monitor behavior**:
   - Returning nil vs event has subtle implications
   - The monitor can be "alive" but effectively broken

3. **SwiftUI + AppKit interaction**:
   - NSEvent monitors are AppKit
   - Sheets are SwiftUI
   - The bridge between them can have race conditions

4. **State checking before processing**:
   - Line 316 checks `viewModel.showingTagPickerForNode != nil` and returns event
   - If showingTagPickerForNode gets set but sheet doesn't show, ALL events get passed through unhandled

5. **The smoking gun might be line 316**:
   ```swift
   if ... viewModel.showingTagPickerForNode != nil ... {
       return event  // Don't process if modal showing
   }
   ```
   If the tag picker state is set but the sheet isn't actually showing, every subsequent keypress would hit this check and return unprocessed!

## Attempt 9: Fix the modal check blocking keyboard events

Based on the logs, I believe the root cause is that `showingTagPickerForNode` gets set to a non-nil value but the sheet doesn't actually present. This causes line 316 in TabbedTreeView to block ALL subsequent keyboard events because it thinks a modal is showing. I will comment out the `showingTagPickerForNode` check from the modal detection logic. This should allow keyboard events to continue processing even after Cmd+T. I expect to see keyboard navigation continue working after Cmd+T, though the tag picker still won't show (that's a separate issue).

### Changes Made:
1. Commented out `viewModel.showingTagPickerForNode != nil` from line 321 in TabbedTreeView.swift
2. Added logging to show when showingTagPickerForNode would normally block events
3. Added logging to modal check to confirm what's blocking

### Why This Should Fix It:
The logs from Attempt 8 showed that after Cmd+T:
- `showingTagPickerForNode` gets set to "Download 2023"
- The keyboard monitor stays alive and receives events
- BUT the keyboard stops working

The smoking gun is in the modal check at line 314-327. When ANY of those conditions are true, the event handler returns `event` unprocessed. Since `showingTagPickerForNode` is non-nil after Cmd+T, EVERY subsequent keypress hits this check and gets returned unprocessed. The keyboard appears broken because no keys are being handled, even though the monitor is alive.

By removing the `showingTagPickerForNode != nil` check, keyboard events will continue to be processed even when this variable is set. This should definitively fix the keyboard breaking after Cmd+T.

### Test Request for User:
Please perform the following test:
1. Navigate with arrow keys to confirm keyboard is working
2. Press Cmd+T
3. Try arrow keys again to see if keyboard navigation still works
4. Report whether keyboard continues to function after Cmd+T

### User Feedback:
"I restarted the app. I pressed the cmd t. Nothing happened. But to my surprise the keyboard still works. Also other shortcuts such as cmd h which were not working before are working now. So progress."

### Analysis of Results:
✅ **SUCCESS** - The keyboard no longer breaks after Cmd+T!
- Keyboard navigation continues working after Cmd+T
- Other shortcuts (like Cmd+H) now work that were previously broken
- This confirms the root cause was the modal check blocking all events when `showingTagPickerForNode` was set

Remaining issue:
- Tag picker still doesn't show when Cmd+T is pressed (separate problem to investigate)

## Attempt 10: Investigate why Cmd+T doesn't show tag picker

Now that the keyboard no longer breaks, I will investigate why the tag picker sheet doesn't present when Cmd+T is pressed. The logs show that `showingTagPickerForNode` is being set, but the sheet never appears. I suspect there's an issue with how the view observes this @Published property or how the sheet binding is configured.

### What we know:
1. Cmd+T is detected and handled successfully (logs show this)
2. `performAction(.showTags)` is called and completes
3. `showingTagPickerForNode` is set to a valid node ("Download 2023" in the test)
4. BUT the sheet never presents (no UI-SHEET log appears)
5. The `.sheet(item:)` modifier exists in TreeView_macOS.swift at line 140-146
6. The performAction node detail logs (lines 822-823) never appeared in logs

### Changes to Make:
1. First, check why the node detail logs aren't appearing in performAction
2. Add logging to track the actual state change of showingTagPickerForNode
3. Add logging in TreeView_macOS to see if the view is observing the change
4. Verify the sheet modifier is properly bound

### Why This Should Help:
The missing node detail logs suggest the code path might be different than expected. By adding comprehensive logging at each step, we can identify exactly where the chain breaks between pressing Cmd+T and the sheet presenting.

### Test Request for User:
Please perform the following test:
1. Restart the app
2. Press Cmd+T
3. Report what happens and whether the tag picker appears

### User Feedback:
"cmd t didn't fix, but i have realized something that could be a clue. I don't think the issue is cmd t. Cmd t is supposed to show tag editor window. But here's the thing right click, tag doesn't even show it. So I think the issue is the tag window trigger is broken."

### Critical Discovery:
The issue is NOT with Cmd+T at all! The tag picker presentation is broken regardless of how it's triggered:
- Cmd+T doesn't show tag picker ❌
- Right-click → Tags doesn't show tag picker ❌
- This means the sheet presentation mechanism itself is broken
- The keyboard shortcut is working fine - it's the TagPickerView sheet that won't present

## Root Cause Found

After investigating, I found there are TWO competing sheet modifiers for the tag picker:

1. **TreeNodeView.swift (line 254)**: Has its own `@State private var showingTagPickerForNode: Node?` with a `.sheet` modifier
2. **TreeView_macOS.swift (line 140)**: Uses `$viewModel.showingTagPickerForNode` with a `.sheet` modifier

The problem:
- When right-clicking, TreeNodeView sets its LOCAL state variable (line 178)
- When pressing Cmd+T, TreeViewModel sets the VIEWMODEL's @Published property
- Neither sheet presents because there are conflicting sheet modifiers
- SwiftUI gets confused when there are multiple sheet modifiers for similar purposes on nested views

This explains why:
- The logs show `showingTagPickerForNode` being set in the ViewModel
- But the sheet never presents
- And why both Cmd+T and right-click fail

## Attempt 11: Remove duplicate sheet modifiers and unify tag picker presentation

I will fix the competing sheet modifiers by removing the local state in TreeNodeView and making it use the ViewModel's state instead. This should resolve the conflict and allow the tag picker to present properly from both Cmd+T and right-click.

### Changes to Make:
1. Remove the local `@State` variable `showingTagPickerForNode` from TreeNodeView.swift
2. Remove the `.sheet` modifier from TreeNodeView.swift (line 254)
3. Make the right-click menu use the ViewModel's `showTagPicker` method instead of setting local state
4. Ensure all tag picker triggers go through the same ViewModel property

### Why This Should Fix It:
Having two competing sheet modifiers on nested views confuses SwiftUI's presentation system. By consolidating to a single sheet modifier at the TreeView_macOS level that binds to the ViewModel's @Published property, both keyboard shortcuts and context menus will trigger the same presentation mechanism.

### Test Request for User:
Please test the following:
1. Restart the app
2. Try Cmd+T - does the tag picker appear?
3. Try right-click → Tags - does the tag picker appear?
4. Confirm keyboard navigation continues to work

### User Feedback:
"it didn't fix it"

### Why My Assumption Was Wrong:
I assumed the issue was duplicate sheet modifiers competing with each other. But removing the duplicate didn't fix it, which means:
1. **The sheet binding itself is broken** - Even with a single sheet modifier, it's not presenting
2. **My diagnosis was incomplete** - I didn't verify that the sheet modifier at TreeView_macOS level was actually working
3. **I didn't check the logs** - I should have monitored the ATTEMPT 10 logs to see if the onChange was firing

### Should We Revert?
**No, keep the changes.** Having duplicate sheet modifiers was still wrong and could cause issues. The cleanup was correct even if it didn't solve the root problem.

### What Went Wrong:
1. I didn't verify my hypothesis with logging first
2. I assumed SwiftUI sheet conflicts without evidence
3. I didn't check if the remaining sheet modifier actually works

### Attempt 12 Plan:
**More Investigation Needed:**
1. Add logging to verify the sheet modifier is even being evaluated
2. Check if the view is re-rendering when showingTagPickerForNode changes
3. Test if OTHER sheets work (like showingDetailsForNode)
4. Add a manual test button to set showingTagPickerForNode directly
5. Check if there's something wrong with the Node type that prevents it from being used with sheet(item:)

The core issue remains: `showingTagPickerForNode` is being set (we saw this in logs) but the sheet doesn't present. This suggests the problem is in the SwiftUI binding/presentation layer, not in the state management.

## Critical Discovery from Logs

**The onChange modifier in TreeView_macOS is NOT firing!**
- TreeViewModel logs show `showingTagPickerForNode` is set to "Download 2023" (21:31:34)
- But NO "UI-BINDING" logs appear from the onChange modifier in TreeView_macOS
- This means TreeView_macOS is not observing the @Published property change

## Summary for Next Developer

### What's Fixed:
✅ Keyboard no longer breaks after Cmd+T (Attempt 9 fixed this)
✅ Duplicate sheet modifiers removed (Attempt 11 cleaned this up)

### What's Still Broken:
❌ Tag picker doesn't show from Cmd+T
❌ Tag picker doesn't show from right-click → Tags
❌ TreeView_macOS not observing ViewModel's @Published changes

### Key Files Involved:
1. **TreeView_macOS.swift** (line 140-156) - Has the sheet modifier that should present
2. **TreeViewModel.swift** (line 44) - Has `@Published var showingTagPickerForNode`
3. **TabbedTreeView.swift** (line 188) - Creates TreeView_macOS with viewModel

### The Real Problem:
The TreeView_macOS view is not properly observing the ViewModel's @Published property. When `showingTagPickerForNode` changes in the ViewModel, the view doesn't re-render, so the sheet never presents.

### Possible Causes to Investigate:
1. **@ObservedObject vs @StateObject** - TreeView_macOS uses @ObservedObject (line 12). The ViewModel might be getting recreated
2. **View identity** - The `.id(currentTab.id)` on line 190 of TabbedTreeView might be causing view recreation
3. **ViewModel reference** - Check if the ViewModel instance is changing between setting the property and the view update
4. **SwiftUI bug** - Sheet presentation with optional items has had issues in SwiftUI

### Next Steps for Attempt 12:
1. Change TreeView_macOS from `@ObservedObject` to `@StateObject` if possible
2. Add logging to TreeView_macOS init to detect if it's being recreated
3. Try using a non-optional binding with `.sheet(isPresented:)` instead of `.sheet(item:)`
4. Test if other @Published properties from the ViewModel work
5. Consider moving the sheet modifier to TabbedTreeView level

### What NOT to Try Again:
- Don't mess with the modal check in keyboard handling (that's fixed)
- Don't add more duplicate sheet modifiers
- Don't assume the problem is in the state setting (logs prove that works)

### Test Commands:
- Check logs: `grep "ATTEMPT 10\|UI-BINDING\|UI-STATE" ~/Library/Application\ Support/Logs/swiftgtd.log`
- Build: `./rebuild_unsigned_macOS.sh`
- Current state: Cmd+T sets the property but view doesn't react

Good luck!

## Attempt 12: Remove .id() modifier that might be causing view recreation (2025-09-30)

### Hypothesis
The issue appears to be in **TabbedTreeView.swift line 190**:
```swift
TreeView_macOS(viewModel: currentTab.viewModel)
    .environmentObject(dataManager)
    .id(currentTab.id)
```

The `.id(currentTab.id)` modifier causes TreeView_macOS to be completely recreated whenever the view updates. Since TreeView_macOS uses `@ObservedObject` (which doesn't own the ViewModel), the recreated view loses its observation of the @Published properties.

### Changes Made
**File**: TabbedTreeView.swift line 190
**Change**: Removed the `.id(currentTab.id)` modifier
```swift
TreeView_macOS(viewModel: currentTab.viewModel)
    .environmentObject(dataManager)
    // Removed .id() modifier which was causing view recreation
    // and breaking @ObservedObject observation of @Published properties
```

### Why This Should Work
- The view will maintain its identity and continue observing the ViewModel's @Published properties
- The onChange modifier in TreeView_macOS should fire when showingTagPickerForNode changes
- The sheet binding should remain connected to the ViewModel

### Build Status
✅ App builds successfully
⚠️ Warning present: unreachable catch block in TabbedTreeView.swift:466

### Test Plan
1. Press Cmd+T - check if tag picker appears
2. Try right-click → Tags - check if tag picker appears
3. Verify keyboard navigation continues working after Cmd+T
4. Check if other shortcuts work

### User Test Results
"It doesn't work. But my testing revealed something new. The details pop up and the tag pop up is being suppressed when in 2 pane mode. When you get out of 2 pane mode by shrinking the width of the window they show."

### Analysis
**CRITICAL DISCOVERY**: The sheets ARE working, but they're being suppressed in split pane (2-pane) mode!
- When window is wide (≥ 900px default): Split pane mode active → sheets don't show
- When window is narrow (< 900px): Regular mode → sheets work correctly
- This explains why tag picker and details sheets appear to be "broken"

### Root Cause
Looking at TreeView_macOS.swift lines 33-49:
- In split pane mode: Uses `splitPaneLayout` (no sheet modifiers)
- In regular mode: Uses `regularTreeView` (has sheet modifiers at lines 132-146)
- The sheet modifiers for tag picker and details are ONLY attached to `regularTreeView`
- Split pane mode doesn't have these sheet modifiers, so the sheets can't present

### Status
❌ FAILED - But revealed the actual root cause: sheets are only defined in regular mode, not split pane mode

## Attempt 13: Add missing sheet modifiers to split pane layout (2025-09-30)

### Problem Identified
The sheet modifiers for tag picker and details are only attached to `regularTreeView` (lines 132-146) but NOT to `splitPaneLayout`. When in split pane mode, there are no sheet modifiers to present the tag picker or details sheets.

### Changes Made
**File**: TreeView_macOS.swift line 126 (after splitPaneLayout function)
**Change**: Add the missing sheet modifiers to splitPaneLayout

```swift
private func splitPaneLayout(windowWidth: CGFloat) -> some View {
    HStack(spacing: 0) {
        // ... existing split pane content ...
    }
    // Add these sheet modifiers that were missing:
    .sheet(item: $viewModel.showingNoteEditorForNode) { node in
        NoteEditorView(node: node) {
            await viewModel.refreshNodes()
        }
    }
    .sheet(item: $viewModel.showingDetailsForNode) { node in
        NodeDetailsView(nodeId: node.id, treeViewModel: viewModel)
    }
    .sheet(item: $viewModel.showingTagPickerForNode) { node in
        TagPickerView(node: node) {
            await viewModel.updateSingleNode(nodeId: node.id)
        }
    }
}
```

### Why This Should Fix It
- Split pane mode will now have the same sheet modifiers as regular mode
- The @Published properties in ViewModel will trigger sheet presentation regardless of layout mode
- Cmd+T and right-click → Tags should work in both narrow and wide windows

### Test Plan
1. Make window wide (> 900px) to trigger split pane mode
2. Press Cmd+T - tag picker should appear
3. Try right-click → Tags - should also work
4. Shrink window to regular mode and verify it still works
5. Test details sheet (Cmd+D) in both modes

### User Test Results
"it works. You can commit it"

### Status
✅ SUCCESS - Tag picker now shows in split pane mode! Committed as 4a0c27b
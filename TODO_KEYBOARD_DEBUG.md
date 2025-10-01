# Keyboard Shortcuts Debug TODO

## Problem
- Cmd+T doesn't open tag picker
- After pressing Cmd+T, ALL keyboard shortcuts stop working (arrow keys, etc.)
- Keyboard event monitor appears to be completely broken after Cmd+T is pressed

## What We've Tried

### ✅ Attempt 1: Make Cmd+T explicitly call performAction(.showTags)
- **Location**: TabbedTreeView.swift line 336-340
- **What we did**: Instead of letting Cmd+T fall through with `break`, directly called `viewModel.performAction(.showTags)`
- **Result**: Build error - wrong method signature
- **Status**: FAILED - Reverted

### ✅ Attempt 2: Fix performAction to use focusedNodeId fallback
- **Location**: TreeViewModel.swift line 783
- **What we did**: Changed `nodeId ?? selectedNodeId` to `nodeId ?? selectedNodeId ?? focusedNodeId`
- **Result**: Still doesn't work, Cmd+T still breaks keyboard
- **Status**: FAILED - Change still in code

### ✅ Attempt 3: Fix control flow for unhandled keys
- **Location**: TabbedTreeView.swift lines 436-440
- **What we did**: Removed code that consumed unhandled shortcuts with modifiers, now passes all unhandled events through
- **Original**: Returned `nil` for unhandled modifier keys
- **Changed to**: Return `event` for all unhandled keys
- **Result**: Didn't fix the issue
- **Status**: FAILED - Change still in code

### ✅ Attempt 4: Add missing break for Cmd+W
- **Location**: TabbedTreeView.swift line 347
- **What we did**: Added `break` statement after Cmd+W when no tab to close
- **Result**: Fixed potential fall-through bug, but unrelated to Cmd+T issue
- **Status**: COMPLETED - But didn't solve main issue

### ✅ Attempt 5: Add logging to debug keyboard monitor
- **Location**: TabbedTreeView.swift onAppear and setupKeyEventMonitor
- **What we did**: Added print statements and logger.log calls
- **Result**: Discovered onAppear is being called but logs aren't writing to file
- **Status**: REVEALED ISSUE - App logs aren't working properly

### ✅ Attempt 6: Kill zombie Xcode debug process
- **What we did**: Found and killed stuck process from Wed08AM that was in debug mode
- **Result**: Cleaned up zombie, but keyboard still breaks after Cmd+T
- **Status**: COMPLETED - But didn't solve main issue

## Current State of Code

### Changes Still in Place:
1. TreeViewModel.performAction uses `nodeId ?? selectedNodeId ?? focusedNodeId` (line 783)
2. TabbedTreeView passes through all unhandled keys with `return event` (lines 437-439)
3. Cmd+W has proper `break` statement (line 347)
4. Debug logging with print statements in onAppear and setupKeyEventMonitor

## What We Know

1. ✅ Arrow keys work initially when app starts
2. ✅ Keyboard monitor IS being set up (works for arrows initially)
3. ✅ Pressing Cmd+T doesn't show tag picker
4. ✅ After pressing Cmd+T, NO keyboard shortcuts work anymore
5. ✅ The keyboard event monitor itself breaks/stops after Cmd+T
6. ✅ TreeViewModel.handleKeyPress expects Cmd+T to work (line 607-609)
7. ✅ performAction(.showTags) requires a selected or focused node
8. ✅ App logs aren't being written to the log file (seeing old session only)

## Key Code Paths

### When Cmd+T is pressed:
1. TabbedTreeView.setupKeyEventMonitor closure receives event
2. Checks if Cmd is pressed (line 327) ✓
3. Hits case 17 for T key (line 330) ✓
4. Checks if Shift is pressed (line 331) - NO
5. Falls through with `break` (line 338) ✓
6. Exits command switch block (line 422) ✓
7. Calls viewModel.handleKeyPress (line 432) ✓
8. TreeViewModel checks for Cmd modifier (line 579) ✓
9. Hits case 17 for T in command block (line 607) ✓
10. Calls performAction(.showTags) (line 608) ✓
11. performAction needs selectedNodeId or focusedNodeId (line 783)
12. If no node selected/focused, returns early (line 786) - LIKELY ISSUE
13. handleKeyPress returns true or false
14. TabbedTreeView returns nil or event based on result

## Theories Not Yet Tested

1. **Returning `event` for Cmd+T might trigger system behavior** that breaks our monitor
2. **NSEvent monitor might be getting removed** somehow after Cmd+T
3. **First responder or focus might be changing** after Cmd+T attempt
4. **The event monitor closure might be throwing an exception** that kills it

## Next Steps to Try

- [ ] Make Cmd+T ALWAYS return nil (consume it) even when unhandled
- [ ] Add try/catch around the entire keyboard handler to catch exceptions
- [ ] Check if NSApp.keyWindow changes after Cmd+T
- [ ] Log the return value of handleKeyPress to see if it's true/false
- [ ] Check if event monitor is nil after Cmd+T is pressed
- [ ] Try using global event monitor instead of local
- [ ] Check if there's a system-wide Cmd+T shortcut conflicting
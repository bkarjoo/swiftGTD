# TODO - Performance Optimizations

## Performance Issues After Refactor

The app has become slower after the recent refactoring. Here are the identified issues and fixes:

### 1. Debounce State Saving ✅
- **Issue**: `saveStateImmediately()` is called on every focus/selection change, writing to disk immediately
- **Fix**: Implement debounced saving with a delay (e.g., 500ms) to batch multiple changes
- **Status**: COMPLETE - Implemented 1-second periodic saves in UIStateManager

### 2. Reduce Subscription Overhead ✅
- **Issue**: Creating Combine subscriptions for EVERY tab's focus and selection changes
- **Fix**: Only subscribe to necessary changes, consider using a single subscription manager
- **Status**: COMPLETE - Subscriptions now only on active tab's TreeViewModel

### 3. Remove Redundant Logging ✅
- **Issue**: Still have many debug logs throughout the codebase that impact performance
- **Fix**: Remove or conditionally compile debug logging statements
- **Status**: COMPLETE - Removed 100+ verbose debug logs

### 4. Optimize Node Lookups ✅
- **Issue**: Frequent `allNodes.first(where:)` calls iterate through entire node list
- **Fix**: Cache frequently accessed nodes in a dictionary for O(1) lookup
- **Status**: COMPLETE - Added nodeCache dictionary, all lookups now O(1)

### 5. Batch Updates ✅
- **Issue**: Multiple state changes trigger individual UI updates
- **Fix**: Group related state changes and update UI once
- **Status**: COMPLETE - Added batchUI helper with withTransaction, composite intent methods

## Priority Order
1. Debounce state saving (biggest impact)
2. Reduce subscription overhead
3. Optimize node lookups
4. Batch updates
5. Remove redundant logging
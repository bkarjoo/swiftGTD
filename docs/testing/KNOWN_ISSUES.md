# Known Testing Issues

This document tracks known issues with the test suite that are deferred for future resolution.

## Auth Header Test Isolation (NetworkingTests)

**Status:** Deferred  
**Identified:** Phase 13 (2025-09-16)  
**Impact:** Low - Tests pass individually but fail when run in parallel  

### Issue Description
The APIClientAuthHeaderTests experience intermittent failures when run in parallel with other tests. This is due to shared state through UserDefaults where the auth token is stored.

### Root Cause
- APIClient stores auth tokens in UserDefaults (singleton pattern)
- All APIClient instances share the same UserDefaults storage
- When tests run in parallel, they interfere with each other's token state
- The setUp/tearDown methods clear UserDefaults, but parallel execution causes race conditions

### Current Behavior
- Tests pass when run individually or serially
- Tests may fail when run with `--parallel` flag
- Production code works correctly (desired singleton behavior)

### Workaround
Run auth tests separately:
```bash
# Run auth tests alone
swift test --package-path Packages --filter APIClientAuthHeaderTests

# Run other tests
swift test --package-path Packages --skip APIClientAuthHeaderTests
```

### Proposed Solution
Refactor APIClient to accept injectable token storage:

```swift
protocol TokenStorage {
    func getToken() -> String?
    func setToken(_ token: String?)
}

class UserDefaultsTokenStorage: TokenStorage { 
    // Current implementation
}

class InMemoryTokenStorage: TokenStorage {
    // For testing
}

class APIClient {
    init(tokenStorage: TokenStorage = UserDefaultsTokenStorage()) {
        // ...
    }
}
```

### Decision
Deferred to a future "test infrastructure" phase. The current implementation is correct for production use, and the test issue only affects parallel test execution. The refactoring would be substantial and is not critical for Phase 13's scope.

### References
- Phase 13 PR: [pending]
- Related files: 
  - `Packages/Sources/Networking/APIClient.swift`
  - `Packages/Tests/NetworkingTests/APIClientAuthHeaderTests.swift`

---

## MockDataManager Singleton Dependencies (FeaturesTests)

**Status:** Acknowledged - Working as intended  
**Identified:** Phase 16 (2025-09-16)  
**Impact:** Low - Tests pass but may have noise from live singletons

### Issue Description
MockDataManager inherits from real DataManager, which initializes live singleton dependencies (NetworkMonitor, CacheManager, OfflineQueueManager). This creates potential for test noise and side effects.

### Current Behavior
- Tests work correctly
- NetworkMonitor logs appear during tests
- CacheManager creates actual cache directories
- No test failures or flakiness observed

### Proposed Solution
Create DataManagerProtocol to enable cleaner mocking:

```swift
protocol DataManagerProtocol: ObservableObject {
    var nodes: [Node] { get set }
    var tags: [Tag] { get set }
    var errorMessage: String? { get set }
    func syncAllData() async
    func toggleNodeCompletion(_ node: Node) async -> Node?
    // ... other methods
}

class MockDataManager: DataManagerProtocol {
    // Pure mock without real dependencies
}
```

### Decision
Acceptable for current phase. Consider refactoring in future test infrastructure improvements.

---

## Publisher Test Timing (FeaturesTests)

**Status:** Acknowledged - Monitor for flakiness  
**Identified:** Phase 16 (2025-09-16)  
**Impact:** Low - Works locally, potential CI flakiness

### Issue Description
TreeViewModel publisher tests use `Task.sleep(nanoseconds: 100_000_000)` to wait for Combine publishers to propagate changes. This works reliably in local testing but could be flaky on slower CI machines.

### Current Behavior
- Tests pass consistently locally
- 0.1 second delay is sufficient for publisher propagation
- No flakiness observed yet

### Proposed Solution
Use XCTestExpectation with Combine helpers:

```swift
let expectation = XCTestExpectation(description: "Publisher update")
let cancellable = viewModel.objectWillChange
    .sink { _ in
        expectation.fulfill()
    }
await fulfillment(of: [expectation], timeout: 1.0)
```

Or create a Combine test helper:
```swift
extension XCTestCase {
    func waitForPublisher<T>(_ publisher: AnyPublisher<T, Never>, 
                            timeout: TimeInterval = 1.0) async throws -> T
}
```

### Decision
Keep current implementation. If CI flakiness occurs, implement deterministic waiting using expectations.

### References
- Phase 16 PR: [pending]
- Related files:
  - `Packages/Tests/FeaturesTests/TreeViewModelLoadTests.swift`
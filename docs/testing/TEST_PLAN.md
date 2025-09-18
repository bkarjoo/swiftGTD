# SwiftGTD – Test Plan & Intern Guidelines

This document is the step‑by‑step guide for interns to add meaningful automated tests with tiny, reviewable phases. Follow the phases in order and keep each PR narrowly scoped.

**Principles**
- Minimal scope: one tiny outcome per PR.
- No production changes unless the phase explicitly calls for DI plumbing.
- Deterministic tests: no network, no timers, no simulator.
- Clear DoD: every phase lists concrete deliverables and assertions.

**Test Targets**
- ModelsTests (SPM)
- CoreTests (SPM)
- NetworkingTests (SPM)
- ServicesTests (SPM)
- FeaturesTests (SPM)
- UITests/SnapshotTests (optional later)

**Intern Workflow**
- Branch: `test/<phase-number>-<short-name>` (e.g., `test/01-networking-target`).
- Commits: concise, present tense, reference the phase (e.g., "Phase 08: add toggle encoding test").
- PR: title starts with the phase number; checklist completed.
- Review: respond to feedback within 24h; keep PR diff focused.

---

## Phased Plan (Tiny Steps)

For each phase: implement items, run tests locally, open a PR with the phase’s DoD checked.

1) Add NetworkingTests target
- Deliverable: new SPM `NetworkingTests` target only.
- DoD: `swift test` discovers the target; no failing tests.

2) Add ServicesTests target
- Deliverable: new SPM `ServicesTests` target only.
- DoD: target visible; build remains green.

3) Add Fixtures folder
- Deliverable: `Packages/Tests/Fixtures/` with a sample node JSON file.
- DoD: tests can load fixture via bundle path.

4) Models decode tests (variants)
- Deliverable: tests for project/area/note/folder JSON decoding.
- DoD: assertions for coding keys and optional fields pass.

5) Models round‑trip (goldens)
- Deliverable: encode→decode tests for representative fixtures.
- DoD: equality on key fields; stable schemas.

6) Core hex edge cases
- Deliverable: tests for 3/6/8‑digit and invalid hex.
- DoD: expected hex out; sensible defaults on invalid.

7) APIClient DI plumbing
- Deliverable: add init allowing injectable `URLSession` (default `.shared`).
- DoD: no behavior change; app still builds; simple URLProtocol mock compiles in tests.

8) APIClient toggle encoding test
- Deliverable: test capturing request body for toggle.
- DoD: verifies `status` toggle and `completed_at` value/null.

9) APIClient auth header test
- Deliverable: test for `Authorization: Bearer <token>` header.
- DoD: header present/absent per token state.

10) APIClient HTTP error mapping
- Deliverable: tests for 400/401/500 responses.
- DoD: throws `APIError.httpError(code)` exactly.

11) APIClient decode error
- Deliverable: test for 200 with malformed JSON.
- DoD: throws decoding error; no crash.

12) DataManager DI plumbing
- Deliverable: `APIClientProtocol` + DataManager init with it (default `.shared`).
- DoD: app still builds; protocol limited to used methods.

13) DataManager toggle success
- Deliverable: fake API returns toggled node; state updates.
- DoD: `nodes[index]` replaced; `errorMessage == nil`.

14) DataManager non‑task guard
- Deliverable: test that non‑task returns nil and no mutation.
- DoD: nodes unchanged.

15) DataManager toggle failure path
- Deliverable: fake API throws; error captured.
- DoD: returns nil; sets `errorMessage`.

16) TreeViewModel load via DataManager
- Deliverable: fake DataManager; verify `nodeChildren` build + sort.
- DoD: children sorted by `createdAt`; allNodes populated.

17) TreeViewModel toggle in‑place update
- Deliverable: fake DataManager returns toggled node; no full reload.
- DoD: only that node updates in `allNodes` (and `nodeChildren` if applicable).

18) TreeViewModel delete flow
- Deliverable: small tree; delete removes descendants and clears focus.
- DoD: removed from `allNodes`/`nodeChildren`; `focusedNodeId` cleared if needed.

19) Add NetworkMonitor test infrastructure
- Deliverable: Mock NWPathMonitor for NetworkMonitor testing.
- DoD: Can simulate connected/disconnected states deterministically.

20) NetworkMonitor state transitions
- Deliverable: Test connectivity changes and connection type detection.
- DoD: isConnected updates correctly; connectionType (wifi/cellular/wired) detected.

21) CacheManager save/load nodes
- Deliverable: Test saving and loading nodes to/from JSON cache.
- DoD: 500+ nodes round-trip correctly; file size tracked; metadata persists.

22) CacheManager cache cleanup
- Deliverable: Test old cache cleanup and size limits.
- DoD: Removes files older than 30 days; respects size constraints.

23) OfflineQueueManager queue operations
- Deliverable: Test queueing create/update/delete/toggle operations.
- DoD: Operations persisted to disk; loaded on restart; proper ordering.

24) OfflineQueueManager process queue
- Deliverable: Test processing queued operations with mock API.
- DoD: Processes in correct order (creates→updates→toggles→deletes); handles failures.

25) OfflineQueueManager temp ID mapping
- Deliverable: Test temporary ID replacement after sync.
- DoD: Temp IDs replaced in nodes and parent references; map returned correctly.

26) DataManager offline create
- Deliverable: Test creating nodes while offline.
- DoD: Temp ID generated; node added locally; operation queued; cache updated.

27) DataManager offline toggle
- Deliverable: Test toggling task completion offline.
- DoD: Local state updated; operation queued; works for both temp and real IDs.

28) DataManager offline delete
- Deliverable: Test deleting nodes (and descendants) offline.
- DoD: Removes locally; queues delete for real nodes; removes from queue for temp nodes.

29) DataManager sync on reconnect
- Deliverable: Test auto-sync when network restored.
- DoD: Pending operations processed; temp IDs replaced; fresh data fetched.

30) Sync conflict resolution
- Deliverable: Test conflicts between offline and server changes.
- DoD: Server wins for conflicts; local creates preserved; no data loss.

31) DataManager cache fallback
- Deliverable: Test loading from cache when offline on startup.
- DoD: Shows cached data when offline; doesn't lose data if server returns empty.

32) Integration: Full offline flow
- Deliverable: End-to-end test of offline create→edit→sync cycle.
- DoD: Node created offline, modified offline, synced correctly when online.

Optional follow‑ups (each its own PR): UI snapshot setup; three baseline snapshots; MainActor/concurrency checks; CI coverage gate.

---

## What To Test (Per Layer)

ModelsTests
- Node decoding: task completed_at nil/value; project/area/note/folder.
- Round‑trip encode/decode with fixtures; NodeType mappings; Auth/Tag coding keys.

CoreTests
- Color hex round‑trip and edge cases; optional Logger formatting.

NetworkingTests
- Toggle encoding, auth header, URL composition, success decode, HTTP error, decode error.
- NetworkMonitor state transitions, connection type detection.

ServicesTests  
- Toggle success/non‑task/failure; delete removes items and updates state.
- CacheManager save/load/cleanup; OfflineQueueManager queue/process operations.
- DataManager offline CRUD operations; sync on reconnect; conflict resolution.
- Temp ID mapping and replacement after sync.

FeaturesTests
- loadAllNodes via DataManager and via API fallback; toggle in‑place update; delete flow.

---

## Definition of Done (Each Phase)
- Tests compile and pass with `swift test --package-path Packages`.
- No unrelated files changed.
- PR includes: short description, list of assertions covered, and why this phase is valuable.
- If DI is introduced: no behavior change; defaults preserve existing call sites.

**How To Run Tests**
- Command: `swift test --package-path Packages --parallel`.
- If Xcode: open `Packages` as a package and run the test schemes.

**Submission Checklist**
- Branch and PR follow naming rules.
- Tests are deterministic (no network, no sleeps).
- Mocks/fakes live in test targets only.
- Fixtures placed under `Packages/Tests/Fixtures/`.
- Coverage does not regress materially for touched area.

**Common Pitfalls**
- Touching production code outside DI phases.
- Relying on live servers or simulator for unit tests.
- Flaky time‑based assertions; use expectations appropriately.

**Review Criteria**
- Clarity of test intent and naming.
- Correctness of assertions and edge cases.
- Isolation from external systems.
- Small, reviewable diffs aligned to a single phase.

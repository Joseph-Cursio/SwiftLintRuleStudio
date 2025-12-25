# Swift 6 Concurrency Migration Plan

## Overview
This document outlines the plan to migrate SwiftLint Rule Studio to Swift 6 with strict concurrency checking to improve parallel test reliability and catch concurrency issues at compile time.

## Current Status
- **Swift Version**: 5.0
- **Available Swift**: 6.2.3
- **Strict Concurrency**: Not enabled
- **Parallel Test Issues**: Documented in `PARALLEL_TEST_INVESTIGATION.md`

## Benefits of Swift 6 Strict Concurrency

1. **Compile-Time Safety**: Catch data races and actor isolation violations before runtime
2. **Better Parallel Test Reliability**: Enforce proper concurrency patterns
3. **Future-Proofing**: Align with Swift's concurrency direction
4. **Explicit Concurrency**: Make concurrency boundaries clear in code

## Migration Strategy

### Phase 1: Enable Targeted Strict Concurrency (Low Risk)
**Goal**: Enable strict concurrency checking only for new code and explicitly marked code.

**Steps**:
1. Update Xcode project to Swift 6.0
2. Set `SWIFT_STRICT_CONCURRENCY = targeted` in build settings
3. Fix any immediate compilation errors
4. Run tests to verify behavior

**Expected Impact**: Minimal - only checks code with concurrency annotations

### Phase 2: Convert ViolationStorage to Actor (Medium Risk)
**Goal**: Replace `DispatchQueue` with Swift concurrency actor.

**Current Implementation**:
```swift
class ViolationStorage {
    private let databaseQueue: DispatchQueue
    // Uses databaseQueue.async { ... } for operations
}
```

**Target Implementation**:
```swift
actor ViolationStorage {
    private var database: OpaquePointer?
    // Direct async/await without explicit queue
}
```

**Benefits**:
- Compiler-enforced isolation
- No manual queue management
- Better integration with Swift concurrency

**Challenges**:
- SQLite C API requires careful handling
- Need to ensure database operations are properly isolated
- May need `nonisolated` for some initialization code

### Phase 3: Remove @MainActor from Test Structs (Low Risk)
**Goal**: Reduce test serialization bottlenecks.

**Current Issue**: Multiple test structs marked `@MainActor` serialize all tests on main thread.

**Approach**:
1. Review each test struct
2. Remove `@MainActor` where not needed
3. Use `@MainActor.run` for specific UI-related test code
4. Mark helper methods as `nonisolated` where appropriate

**Files to Review**:
- `ViolationInspectorViewModelTests.swift`
- `YAMLConfigurationEngineTests.swift`
- `WorkspaceAnalyzerTests.swift`
- `RuleRegistryTests.swift`

### Phase 4: Enable Complete Strict Concurrency (High Risk)
**Goal**: Full compile-time concurrency checking.

**Steps**:
1. Set `SWIFT_STRICT_CONCURRENCY = complete`
2. Fix all compilation errors
3. Add `Sendable` conformance where needed
4. Review and fix actor isolation violations
5. Run full test suite

**Expected Issues**:
- Many types may need `Sendable` conformance
- Some closures may need `@Sendable` annotation
- Cross-actor access patterns may need refactoring

## Implementation Details

### 1. ViolationStorage Actor Conversion

**Before**:
```swift
class ViolationStorage {
    private let databaseQueue: DispatchQueue
    
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws {
        try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                // Database operations
            }
        }
    }
}
```

**After**:
```swift
actor ViolationStorage {
    private var database: OpaquePointer?
    
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws {
        // Direct database operations - compiler ensures isolation
        try openDatabaseIfNeeded()
        // ... SQL operations
    }
    
    nonisolated func init(databasePath: URL?) throws {
        // Initialization can be nonisolated
    }
}
```

### 2. Sendable Conformance

Types that cross concurrency boundaries will need `Sendable`:

```swift
struct Violation: Sendable {
    // Already value type, just needs conformance
}

struct ViolationFilter: Sendable {
    // Add Sendable conformance
}
```

### 3. Test Isolation Improvements

**Before**:
```swift
@MainActor
struct ViolationInspectorViewModelTests {
    func testSomething() async throws {
        // All tests serialize on main actor
    }
}
```

**After**:
```swift
struct ViolationInspectorViewModelTests {
    func testSomething() async throws {
        // Can run in parallel
        await MainActor.run {
            // UI-specific code if needed
        }
    }
}
```

## Testing Strategy

### 1. Incremental Testing
- Enable strict concurrency incrementally
- Run tests after each phase
- Fix issues as they arise

### 2. Parallel Test Validation
- Run tests with `-parallel-testing-enabled YES`
- Monitor for reduced failures
- Use Thread Sanitizer to verify fixes

### 3. Performance Monitoring
- Compare test execution times
- Monitor app performance
- Ensure no regressions

## Risk Assessment

| Phase | Risk Level | Effort | Benefit |
|-------|-----------|--------|---------|
| Phase 1: Targeted | Low | Low | Medium |
| Phase 2: Actor Conversion | Medium | Medium | High |
| Phase 3: Test Refactoring | Low | Low | Medium |
| Phase 4: Complete | High | High | Very High |

## Recommended Approach

**Option A: Incremental (Recommended)**
1. Start with Phase 1 (targeted strict concurrency)
2. Monitor for issues
3. Gradually move to Phase 2-4
4. **Timeline**: 2-3 weeks

**Option B: Full Migration**
1. Complete all phases at once
2. More disruptive but faster overall
3. **Timeline**: 1 week (intensive)

**Option C: Wait for v1.1**
1. Complete v1.0 with current Swift 5.0
2. Migrate to Swift 6 in v1.1
3. **Timeline**: Post-v1.0

## Decision Criteria

**Migrate Now If**:
- Parallel test failures are blocking development
- You want to catch concurrency issues early
- You have time for refactoring

**Wait If**:
- v1.0 release is priority
- Current test isolation is sufficient
- You want to minimize risk before release

## Next Steps

1. **Decision**: Choose migration approach (A, B, or C)
2. **If A or B**: Start with Phase 1 (targeted strict concurrency)
3. **Monitor**: Track compilation errors and test results
4. **Iterate**: Fix issues incrementally

## References

- [Swift 6 Migration Guide](https://www.swift.org/documentation/concurrency/)
- `PARALLEL_TEST_INVESTIGATION.md` - Current parallel test issues
- `DIAGNOSING_PARALLEL_TESTS.md` - Diagnostic tools and techniques


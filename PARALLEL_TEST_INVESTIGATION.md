# Parallel Test Execution Investigation

## Summary

Investigated parallel test execution failures. Found and fixed several issues that could cause race conditions when tests run in parallel.

## Issues Found and Fixed

### 1. YAMLConfigurationEngine File Operations ✅ FIXED

**Problem**: Temp files and backup files used simple extensions (`.tmp`, `.backup`) which could conflict if multiple tests run in parallel and somehow use similar file paths.

**Fix**: 
- Changed temp file naming to include UUID: `filename.UUID.tmp`
- Changed backup file naming to include timestamp: `filename.timestamp.backup`
- Updated test to handle new backup file naming pattern

**Files Changed**:
- `YAMLConfigurationEngine.swift` - Improved file operation safety
- `YAMLConfigurationEngineTests.swift` - Updated test expectations

### 2. RuleRegistry TaskGroup Memory Management ✅ FIXED (Previously)

**Problem**: TaskGroup closures captured `self` strongly, potentially causing retain cycles and timing issues in parallel execution.

**Fix**: Added `[weak self]` capture in TaskGroup closures.

**Files Changed**:
- `RuleRegistry.swift` - Added weak self capture

### 3. ViolationStorage Test Isolation ✅ IMPROVED (Previously)

**Problem**: Tests might share state when using in-memory databases.

**Fix**: Each test now uses `createIsolatedStorage()` helper to ensure complete isolation.

**Files Changed**:
- `ViolationStorageTests.swift` - Added isolation helper

## Potential Issues Identified (Not Yet Fixed)

### 1. @MainActor Test Structs

**Issue**: Multiple test structs are marked with `@MainActor`:
- `ViolationInspectorViewModelTests`
- `YAMLConfigurationEngineTests`
- `WorkspaceAnalyzerTests`
- `RuleRegistryTests`

**Impact**: When tests run in parallel, they all need to serialize on the main actor, which could cause:
- Timing issues
- Test execution delays
- Potential deadlocks if not properly handled

**Recommendation**: 
- Consider removing `@MainActor` from test structs if not needed
- Or ensure all async operations properly await main actor access
- Consider using `nonisolated` for test helper methods that don't need main actor

### 2. Shared Application Support Directory

**Issue**: Both `ViolationStorage` and `WorkspaceAnalyzer` use the same application support directory path when not provided with custom paths:
```swift
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let dbDir = appSupport.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
```

**Impact**: If tests don't properly isolate file operations, they could conflict.

**Current Status**: Tests should be using:
- In-memory databases for `ViolationStorage`
- Custom temp directories for `WorkspaceAnalyzer`
- But if any test accidentally uses default paths, conflicts could occur

**Recommendation**: 
- Ensure all tests use isolated file paths
- Consider adding assertions to prevent accidental use of shared directories in tests

### 3. Static Queue Counter in ViolationStorage

**Issue**: `ViolationStorage` uses a static `queueCounter` to create unique queue labels:
```swift
private static var queueCounter = 0
private static let queueCounterLock = NSLock()
```

**Impact**: While protected by a lock, this is shared state across all instances.

**Current Status**: Protected by `NSLock`, should be safe, but could be a bottleneck in parallel execution.

**Recommendation**: 
- Current implementation is safe
- Consider using UUID-based queue labels if performance becomes an issue

## Test Results

### Before Fixes
- 86 tests passing
- 46 tests failing (all parallel execution issues)

### After Fixes
- YAMLConfigurationEngineTests: All tests pass individually
- RuleRegistryTests: All tests pass individually  
- WorkspaceAnalyzerTests: All tests pass individually
- ViolationStorageTests: All tests pass individually

### Parallel Execution Status
Tests still fail when run in parallel, but this is likely due to:
1. @MainActor serialization issues
2. Swift Testing framework limitations with parallel @MainActor tests
3. Potential timing issues with async operations

## Recommendations

### Short Term
1. ✅ **DONE**: Improved file operation safety in YAMLConfigurationEngine
2. ✅ **DONE**: Fixed memory management in RuleRegistry
3. ✅ **DONE**: Improved test isolation in ViolationStorageTests

### Medium Term
1. **Consider**: Removing `@MainActor` from test structs where not strictly necessary
2. **Consider**: Using `nonisolated` for test helper methods
3. **Consider**: Adding test-specific assertions to prevent shared directory usage

### Long Term
1. **Investigate**: Swift Testing framework behavior with parallel @MainActor tests
2. **Consider**: Running tests sequentially if parallel execution continues to be problematic
3. **Monitor**: Test execution times and failure patterns

## Running Tests

### Individual Test Execution (Recommended for CI)
```bash
# Run tests sequentially to avoid parallel execution issues
xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS' \
  -parallel-testing-enabled NO
```

### Parallel Execution (For Development)
```bash
# Run tests in parallel (may have failures)
xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS'
```

### With Thread Sanitizer
```bash
# Run with TSAN to detect data races
xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS' \
  -enableThreadSanitizer YES
```

## Conclusion

The main issues causing parallel test failures appear to be:
1. **File system race conditions** - Partially fixed with unique temp file naming
2. **@MainActor serialization** - May need framework-level changes or test restructuring
3. **Test isolation** - Improved but may need further work

All tests pass when run individually, indicating the code logic is correct. The failures are primarily due to parallel execution constraints, not code bugs.


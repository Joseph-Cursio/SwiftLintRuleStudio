# Diagnosing Parallel Test Execution Issues

This guide explains how to use compiler flags and build settings to diagnose parallel execution issues in tests.

## Thread Sanitizer (TSAN) - Most Important

Thread Sanitizer detects data races, use-after-free, and other threading issues that can cause parallel test failures.

### Enable via Xcode:
1. Edit Scheme → Test → Diagnostics
2. Check "Thread Sanitizer"
3. Run tests

### Enable via Command Line:
```bash
xcodebuild test \
  -scheme SwiftLIntRuleStudio \
  -destination 'platform=macOS' \
  -enableThreadSanitizer YES
```

### What TSAN Detects:
- **Data Races**: Concurrent access to shared mutable state
- **Use-After-Free**: Accessing deallocated memory
- **Lock Order Inversions**: Potential deadlocks
- **Unsafe Concurrency**: Violations of Swift concurrency rules

## Swift Concurrency Strict Checking

Enable strict concurrency checking to catch actor isolation issues:

### Build Settings to Add:
```
SWIFT_STRICT_CONCURRENCY = complete
```

This enables:
- Complete concurrency checking
- Actor isolation violations
- Sendable requirement violations
- MainActor isolation issues

### Alternative (Less Strict):
```
SWIFT_STRICT_CONCURRENCY = targeted
```
Only checks code marked with concurrency annotations.

## Additional Debugging Flags

### 1. Swift Compiler Flags

Add to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`:
```
SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited) SWIFT_CONCURRENCY_STRICT"
```

### 2. Runtime Environment Variables

Set these when running tests:
```bash
# Enable detailed concurrency logging
SWIFT_CONCURRENCY_DEBUG=1

# Enable actor isolation checking
SWIFT_ACTOR_STRICT_CONCURRENCY=1

# Enable detailed task logging
SWIFT_TASK_DEBUG=1
```

### 3. Xcode Scheme Environment Variables

Edit Scheme → Test → Arguments → Environment Variables:
- `SWIFT_CONCURRENCY_DEBUG=1`
- `SWIFT_ACTOR_STRICT_CONCURRENCY=1`

## Running Tests with Diagnostics

### Full Diagnostic Command:
```bash
xcodebuild test \
  -scheme SwiftLIntRuleStudio \
  -destination 'platform=macOS' \
  -enableThreadSanitizer YES \
  -only-testing:SwiftLIntRuleStudioTests/ViolationStorageTests
```

### With Environment Variables:
```bash
SWIFT_CONCURRENCY_DEBUG=1 \
SWIFT_ACTOR_STRICT_CONCURRENCY=1 \
xcodebuild test \
  -scheme SwiftLIntRuleStudio \
  -destination 'platform=macOS' \
  -enableThreadSanitizer YES
```

## Common Issues TSAN Will Find

1. **Shared Mutable State**: Multiple threads accessing the same variable
   - Solution: Use actors, locks, or make state immutable

2. **Actor Isolation Violations**: Accessing actor-isolated code from wrong context
   - Solution: Use `await` and proper actor isolation

3. **Race Conditions in Initialization**: Multiple threads initializing the same object
   - Solution: Use synchronization primitives or lazy initialization

4. **SQLite Concurrency Issues**: Multiple threads accessing the same database connection
   - Solution: Use serial queues (already done in ViolationStorage)

## Interpreting TSAN Output

TSAN reports look like:
```
WARNING: ThreadSanitizer: data race
  Write at 0x... by thread T1:
  Read at 0x... by thread T2:
```

This shows:
- **Location**: Where the race occurred
- **Threads**: Which threads were involved
- **Type**: Read/Write operation

## Performance Impact

- **TSAN**: 5-10x slower, but essential for finding races
- **Strict Concurrency**: Minimal performance impact, compile-time only
- **Debug Flags**: Minimal runtime impact

## Recommended Workflow

1. **First**: Enable TSAN and run failing tests
2. **Second**: Fix any data races TSAN finds
3. **Third**: Enable strict concurrency checking
4. **Fourth**: Fix any compile-time warnings
5. **Finally**: Re-run tests to verify fixes

## Keeping TSAN Enabled

### Option 1: Enable in Xcode Scheme (Recommended for Development)

1. Open Xcode
2. Product → Scheme → Edit Scheme...
3. Select "Test" in the left sidebar
4. Go to "Diagnostics" tab
5. Check "Thread Sanitizer"
6. Click "Close"

This will keep TSAN enabled for all test runs in Xcode.

### Option 2: Always Use Command Line Flag

Always include `-enableThreadSanitizer YES` when running tests:

```bash
xcodebuild test -scheme SwiftLIntRuleStudio -destination 'platform=macOS' \
  -enableThreadSanitizer YES
```

### Option 3: Create a Test Script

Create a script `test-with-tsan.sh`:

```bash
#!/bin/bash
xcodebuild test \
  -scheme SwiftLIntRuleStudio \
  -destination 'platform=macOS' \
  -enableThreadSanitizer YES \
  "$@"
```

Then run: `./test-with-tsan.sh`

## Example: Finding ViolationStorage Issues

If ViolationStorageTests are failing in parallel:

```bash
# Run with TSAN
xcodebuild test \
  -scheme SwiftLIntRuleStudio \
  -destination 'platform=macOS' \
  -enableThreadSanitizer YES \
  -only-testing:SwiftLIntRuleStudioTests/ViolationStorageTests
```

TSAN will report if:
- Multiple ViolationStorage instances share state
- Database connections are accessed concurrently
- Queue synchronization is incorrect
- Static variables are accessed unsafely

## Current Status

**TSAN Analysis Results**: When running ViolationStorageTests with TSAN enabled, no data races were detected. This suggests:
- The failures are likely **not** due to data races
- Issues may be related to:
  - Test isolation (shared state between test instances)
  - SQLite in-memory database setup/teardown
  - Test execution order dependencies
  - Async/await timing issues

**Next Steps**: Since TSAN didn't find races, focus on:
1. Ensuring each test has isolated state
2. Verifying SQLite in-memory databases are truly isolated
3. Checking for test dependencies or execution order issues


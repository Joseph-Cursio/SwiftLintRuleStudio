# Test Isolation Analysis

## Issues Found

### 1. **Excessive `@MainActor` Usage** 🔄 **IN PROGRESS**

**Problem**: All 41 test files use `@MainActor`, which serializes all tests on the main actor, preventing parallel execution.

**Status**: 🔄 **PARTIALLY FIXED** - Removed from model tests and some service tests

**Files Fixed** (7 files):
- ✅ `RuleTests.swift` - Model tests don't need @MainActor
- ✅ `ViolationTests.swift` - Model tests don't need @MainActor
- ✅ `CacheManagerTests.swift` - CacheManager is not @MainActor
- ✅ `WorkspaceAnalyzerTests.swift` - WorkspaceAnalyzer is not @MainActor
- ✅ `ViolationStorageTests.swift` - ViolationStorage is an actor, not @MainActor
- ✅ `YAMLConfigurationEngineTests.swift` - Removed @MainActor, added helper function, updated 5+ tests
- ✅ `ImpactSimulatorTests.swift` - Removed @MainActor, added helper function, updated all 9 tests

**Progress**: 7 of 41 files updated (~17% complete)

**Files Remaining** (~35 files):
- Service tests for @MainActor services (WorkspaceManager, RuleRegistry, OnboardingManager, etc.)
- ViewModel tests (may need @MainActor for UI-related code)
- View tests (likely need @MainActor for ViewInspector)

**Impact**: 
- ✅ Model tests can now run in parallel
- ✅ Non-@MainActor service tests can run in parallel
- ⚠️ @MainActor service tests still need special handling

**Recommendation**: 
- ✅ **DONE**: Removed `@MainActor` from model tests
- ✅ **DONE**: Removed `@MainActor` from non-@MainActor service tests
- 🔄 **TODO**: For @MainActor services, use `await MainActor.run { }` inside test functions
- 🔄 **TODO**: Review ViewModel and View tests to determine if they need @MainActor

### 2. **Shared Cache Manager** ✅ **FIXED**

**Problem**: `SwiftLintCLIIntegrationTests` used a shared cache manager across tests.

**Location**: `SwiftLIntRuleStudioTests/Core/Utilities/SwiftLintCLIIntegrationTests.swift:28`

**Status**: ✅ **FIXED** - All tests now use isolated cache managers

**Solution Applied**:
- Removed `createSharedCacheManager()` method
- Updated `createIsolatedCacheManager()` to return `(CacheManager, URL)` tuple for cleanup
- Replaced all 8 instances of `createSharedCacheManager()` with `createIsolatedCacheManager()`
- Added `cleanupCacheDirectory()` helper method
- Added `defer { cleanupCacheDirectory(cacheDir) }` to all tests for proper cleanup

**Impact**: 
- ✅ Each test now has its own isolated cache directory
- ✅ No race conditions between parallel tests
- ✅ Cache state doesn't leak between tests
- ✅ Proper cleanup after each test completes

### 3. **Direct UserDefaults.standard Usage** ✅ **FIXED**

**Problem**: `WorkspaceManagerIntegrationTests` uses `UserDefaults.standard` directly.

**Location**: `SwiftLIntRuleStudioTests/Core/Services/WorkspaceManagerIntegrationTests.swift:389, 451`

**Status**: ✅ **FIXED** - Now uses `IsolatedUserDefaults.create()` for test isolation

**Solution Applied**:
- Added `IsolatedUserDefaults.create()` for test tracking
- Added proper cleanup with `defer` blocks
- Documented limitation: `WorkspaceManager` uses `UserDefaults.standard` internally
- Still clears `UserDefaults.standard` for test setup, but now with proper isolation tracking

**Note**: Full isolation would require modifying `WorkspaceManager` to accept a `UserDefaults` parameter, which is a larger refactoring. The current fix improves isolation while working within the existing architecture.

### 4. **Simple Model Tests Don't Need @MainActor** ⚠️ **MEDIUM PRIORITY**

**Problem**: Tests that only test data models use `@MainActor`.

**Files**:
- `RuleTests.swift`
- `ViolationTests.swift`

**Impact**: 
- Unnecessary serialization
- Slower test execution
- Prevents parallel execution

**Recommendation**: Remove `@MainActor` from these test structs.

### 5. **ViewInspector Test Failures** ⚠️ **MEDIUM PRIORITY**

**Problem**: Many ViewInspector-based tests are failing.

**Possible Causes**:
- ViewInspector requires views to be on main actor
- Test isolation interfering with view inspection
- Missing ViewInspector setup/configuration

**Recommendation**: 
- Ensure ViewInspector tests properly handle main actor isolation
- Check ViewInspector version compatibility
- Verify ViewInspector is properly linked to test target

## Recommendations

### Immediate Actions

1. **Remove `@MainActor` from non-UI tests**
   - Start with `RuleTests` and `ViolationTests`
   - Remove from service tests that don't interact with UI
   - Keep only for tests that actually need UI interaction

2. **Fix shared cache manager**
   - Change `createSharedCacheManager()` to use isolated directories
   - Or add UUID to directory name for isolation

3. **Fix UserDefaults.standard usage**
   - Replace with `IsolatedUserDefaults.create()`
   - Or inject UserDefaults dependency

### Medium-Term Actions

4. **Review ViewInspector test setup**
   - Check if ViewInspector needs special configuration
   - Verify main actor handling in ViewInspector tests
   - Consider if tests need to be sequential vs parallel

5. **Add test isolation verification**
   - Create a test that verifies isolation is working
   - Check for any remaining shared state

### Long-Term Actions

6. **Consider test organization**
   - Group tests that need sequential execution
   - Separate parallel-safe tests from those that need isolation

## Test Isolation Helpers Status

✅ **Good**: `TestIsolationHelpers.swift` provides good isolation patterns
✅ **Good**: `WorkspaceTestHelpers.swift` properly creates isolated workspaces
✅ **Good**: `IsolatedUserDefaults` pattern is well-designed
⚠️ **Issue**: Not all tests are using these helpers consistently

## Expected Impact After Fixes

- **Parallel Execution**: Tests should be able to run in parallel
- **Test Reliability**: Fewer flaky tests due to shared state
- **Test Speed**: Faster test execution with parallel runs
- **Test Failures**: Should reduce from ~99 failures to much fewer

## Next Steps

1. Fix `@MainActor` usage (start with simple model tests)
2. Fix shared cache manager
3. Fix UserDefaults.standard usage
4. Re-run tests to verify improvements
5. Address ViewInspector test failures


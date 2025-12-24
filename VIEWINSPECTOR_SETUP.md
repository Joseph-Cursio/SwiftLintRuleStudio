# ViewInspector Setup Instructions

This document explains how to add ViewInspector to the project for testing SwiftUI view display inconsistencies.

## Quick Start: Simple Tests (No Setup Required)

You can run the simple consistency tests immediately without any setup:

1. Open `RuleDisplayConsistencySimpleTests.swift` in Xcode
2. Run the tests using **Product → Test** (⌘U)
3. These tests verify data model consistency and view initialization

These tests don't require ViewInspector and can catch many inconsistencies at the data level.

## Full Testing with ViewInspector

For comprehensive UI testing that inspects actual view rendering, use ViewInspector:

## Adding ViewInspector as a Swift Package Dependency

1. **Open Xcode** and open the `SwiftLIntRuleStudio.xcodeproj` project

2. **Add Package Dependency:**
   - Go to **File → Add Package Dependencies...**
   - Enter the URL: `https://github.com/nalexn/ViewInspector`
   - Click **Add Package**
   - Select version: **Up to Next Major Version** with `0.9.7` or later
   - Click **Add Package**

3. **Add to Test Target:**
   - In the package selection screen, make sure **ViewInspector** is checked for the **SwiftLIntRuleStudioTests** target
   - Click **Add Package**

## Running the Consistency Tests

Once ViewInspector is added:

1. Open `RuleDisplayConsistencyTests.swift` in Xcode
2. Run the tests using **Product → Test** (⌘U) or click the diamond icons next to each test
3. The tests will verify:
   - Enabled state is displayed consistently in `RuleListItem`
   - Enabled state is displayed consistently in `RuleDetailView`
   - The toggle in `RuleDetailView` matches the rule's enabled state
   - Consistency between list and detail views for the same rule
   - Specific test for the `duplicate_imports` rule issue

## What These Tests Check

The `RuleDisplayConsistencyTests` verify:

1. **Enabled State Display:**
   - Rules with `isEnabled = true` show "Enabled" label in both views
   - Rules with `isEnabled = false` don't show "Enabled" label
   - The toggle in `RuleDetailView` matches the rule's `isEnabled` state

2. **Consistency Between Views:**
   - If a rule shows as enabled in the list, it should also show as enabled in the detail view
   - The toggle state should match the rule's `isEnabled` property

3. **State Synchronization:**
   - When a rule's enabled state changes, the detail view should reflect it
   - The view should sync its state when it appears or when the rule changes

## Troubleshooting

If tests fail:

1. **ViewInspector not found:**
   - Make sure ViewInspector is added to the test target
   - Clean build folder (⌘⇧K) and rebuild

2. **Inspection errors:**
   - ViewInspector may need view extensions for custom views
   - Check that `RuleListItem` and `RuleDetailView` conform to `Inspectable`

3. **Test failures:**
   - Review the test output to see which assertions failed
   - This indicates where the display inconsistency is occurring

## Alternative: Manual Testing Without ViewInspector

If you prefer not to use ViewInspector, you can manually test by:

1. Running the app
2. Finding a rule that shows as enabled in the list
3. Selecting it and checking if it shows as enabled in the detail panel
4. Checking if the toggle matches the enabled state

The ViewInspector tests automate this process and can catch regressions.


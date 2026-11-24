//
//  RecordingThrows.swift
//  SwiftLintRuleStudioCoreTests
//
//  A `propertyCheck` body that throws must fail, and on its own it does not.
//

import Testing

/// Runs a `propertyCheck` body, recording any error that escapes it as a failure.
///
/// swift-property-based, every release through 2.0.1, runs a `propertyCheck` body under `try?` on
/// Swift 6.2 and later, so an error that escapes the body is dropped and the property passes
/// (x-sheep/swift-property-based#29). A YAML step that throws would then read as a held law.
/// `#expect(try …)` and `#require(try …)` do not help: both rethrow an error from their own
/// expression instead of recording it. Wrap the body instead:
///
///     await propertyCheck(input: gen) { spec in
///         await recordingThrows {
///             let back = try YAMLConfigurationEngine.parse(try YAMLConfigurationEngine.serialize(config))
///             #expect(back == config)
///         }
///     }
///
/// The error is recorded inside the property, so the library still counts it, shrinks it and
/// reports the input. Two kinds of error are not recorded:
/// - `ExpectationFailedError`: `#require` has already recorded its issue.
/// - anything thrown once the task is cancelled. This is broader than Swift Testing, which skips
///   only a `CancellationError` (or `Test.cancel()`'s internal error) and still records anything
///   else thrown after a cancel. `Test.cancel()`'s error cannot be matched by type outside the
///   framework, and the test is reported cancelled either way, so the helper drops it all.
func recordingThrows(
    isolation _: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
    } catch is ExpectationFailedError {
        return
    } catch {
        guard !Task.isCancelled else { return }
        Issue.record(error, sourceLocation: sourceLocation)
    }
}

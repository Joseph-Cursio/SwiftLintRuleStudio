import Foundation
import enum SwiftLintCLISeam.SwiftLintError
import SwiftLintFramework

/// What `swiftlint lint` does to each file's violations before it reports them
/// (`LintOrAnalyzeCommand.collectViolations`), taken from the root config alone — a nested
/// config's `strict`, `lenient` and `baseline` count for nothing there:
///
/// 1. `strict` raises every warning to an error, or `lenient` lowers every error to a warning;
/// 2. then the violations the `baseline` holds are dropped.
///
/// The order matters. A baseline first drops the violations it holds exactly, severity and
/// all, and only then compares the rest by their line's text — where a line with more
/// violations than the baseline has keeps all of them. So a violation `strict` raised can
/// stay where, filtered first, it would have gone.
struct ReportFilter {
    private let strict: Bool
    private let lenient: Bool
    private let baseline: Baseline?

    /// Reads `root`'s settings, and its baseline as `swiftlint lint` reads it: one that isn't
    /// there is skipped (SwiftLint prints a warning), one it can't read fails the lint. Call
    /// this with `URL.cwd` overridden to the workspace: SwiftLint keys a baseline's files by
    /// their path from the working directory, and reads them back from there.
    init(root: Configuration) throws {
        strict = root.strict
        lenient = root.lenient
        baseline = try root.baseline.flatMap(Self.baseline(at:))
    }

    private static func baseline(at path: URL) throws -> Baseline? {
        do {
            return try Baseline(fromPath: path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw InProcessConfigurationError.unreadable(file: path, reason: String(describing: error))
        }
    }

    /// One file's violations as `swiftlint lint` reports them. A baseline matches the
    /// violations of one file at a time, so call this once per file.
    func callAsFunction(_ violations: [StyleViolation]) throws -> [StyleViolation] {
        let adjusted: [StyleViolation]
        switch (strict, lenient) {
        case (false, false):
            adjusted = violations
        case (false, true):
            adjusted = violations.map { $0.severity == .error ? $0.with(severity: .warning) : $0 }
        case (true, false):
            adjusted = violations.map { $0.severity == .warning ? $0.with(severity: .error) : $0 }
        case (true, true):
            // `swiftlint lint` ends the process here, at the first file it lints.
            throw SwiftLintError.executionFailed(
                message: "Invalid command line or config options: 'strict' and 'lenient' are mutually exclusive."
            )
        }
        return baseline?.filter(adjusted) ?? adjusted
    }
}

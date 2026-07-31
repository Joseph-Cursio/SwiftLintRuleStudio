//
//  ExportFilenameTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ExportFilename.timestamp, the shared export filename stamp.
//

import Foundation
@testable import SwiftLintRuleStudio
import Testing

@MainActor
@Suite("ExportFilename.timestamp")
struct ExportFilenameTests {

    /// A fixed instant to format. The expected rendering is derived from the
    /// Gregorian calendar in the current time zone, so these tests hold on any
    /// machine regardless of its regional settings.
    private static let referenceDate = Date(timeIntervalSince1970: 1_775_000_000)

    private static func gregorianComponents(for date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }

    // MARK: - Shape

    @Test("Produces a yyyyMMdd_HHmmss stamp")
    func producesExpectedShape() throws {
        let stamp = ExportFilename.timestamp(from: Self.referenceDate)

        let pattern = try Regex(#"^\d{8}_\d{6}$"#)
        #expect(stamp.wholeMatch(of: pattern) != nil, "unexpected stamp: \(stamp)")
        #expect(stamp.count == 15)
    }

    @Test("The default argument stamps the current time")
    func defaultsToNow() throws {
        let before = Date()
        let stamp = ExportFilename.timestamp()
        let after = Date()

        let pattern = try Regex(#"^\d{8}_\d{6}$"#)
        #expect(stamp.wholeMatch(of: pattern) != nil)

        // The stamp must fall within the window the call was made in, compared
        // at whole-second resolution since the format truncates.
        let lowerBound = ExportFilename.timestamp(from: before.addingTimeInterval(-1))
        let upperBound = ExportFilename.timestamp(from: after.addingTimeInterval(1))
        #expect(stamp >= lowerBound)
        #expect(stamp <= upperBound)
    }

    // MARK: - Correctness

    @Test("Renders the Gregorian date and time of the instant")
    func rendersGregorianComponents() {
        let stamp = ExportFilename.timestamp(from: Self.referenceDate)
        let parts = Self.gregorianComponents(for: Self.referenceDate)

        let expected = String(
            format: "%04d%02d%02d_%02d%02d%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )

        #expect(stamp == expected)
    }

    @Test("Uses a 24-hour clock rather than a 12-hour one")
    func uses24HourClock() {
        // 2026-03-31 20:00:00 UTC, chosen so the local hour is >= 13 across the
        // Americas and Europe; guard the assertion on the actual local hour so
        // the test stays valid in any zone.
        let evening = Date(timeIntervalSince1970: 1_775_001_600)
        let hour = Self.gregorianComponents(for: evening).hour ?? 0

        let stamp = ExportFilename.timestamp(from: evening)
        let hourField = stamp.dropFirst(9).prefix(2)

        #expect(hourField == String(format: "%02d", hour))
        #expect(Int(hourField) ?? -1 < 24)
    }

    @Test("Is unaffected by a non-Gregorian ambient calendar")
    func ignoresNonGregorianCalendars() {
        // Regression guard: with only a fixed dateFormat, the ambient locale
        // decides the era — a Japanese-calendar user saw "0008" for 2026.
        let stamp = ExportFilename.timestamp(from: Self.referenceDate)
        let year = Self.gregorianComponents(for: Self.referenceDate).year ?? 0

        #expect(stamp.hasPrefix(String(format: "%04d", year)))
        #expect(year > 1_900, "sanity: the reference date is a modern Gregorian year")
    }

    // MARK: - Ordering

    @Test("Later instants stamp to lexicographically greater strings")
    func sortsChronologically() {
        let dates = [
            Date(timeIntervalSince1970: 1_600_000_000),
            Date(timeIntervalSince1970: 1_700_000_000),
            Self.referenceDate,
            Date(timeIntervalSince1970: 1_900_000_000)
        ]

        let stamps = dates.map { ExportFilename.timestamp(from: $0) }

        // Filenames are sorted as text in export listings, so lexicographic and
        // chronological order have to agree.
        #expect(stamps == stamps.sorted())
    }

    @Test("Instants within the same second stamp identically")
    func truncatesToWholeSeconds() {
        let base = Self.referenceDate
        let sameSecond = base.addingTimeInterval(0.4)

        #expect(ExportFilename.timestamp(from: base) == ExportFilename.timestamp(from: sameSecond))
    }

    @Test("Instants a second apart stamp differently")
    func distinguishesAdjacentSeconds() {
        let base = Self.referenceDate
        let nextSecond = base.addingTimeInterval(1)

        #expect(ExportFilename.timestamp(from: base) != ExportFilename.timestamp(from: nextSecond))
    }

    // MARK: - Filename safety

    @Test("Contains no characters that are unsafe in a filename")
    func isFilenameSafe() {
        let stamp = ExportFilename.timestamp(from: Self.referenceDate)
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>| ")

        let isPlainASCII = stamp.unicodeScalars.allSatisfy(\.isASCII)

        #expect(stamp.rangeOfCharacter(from: unsafe) == nil)
        #expect(isPlainASCII)
    }

    @Test("Survives a round trip through a matching formatter")
    func roundTripsThroughFormatter() throws {
        let stamp = ExportFilename.timestamp(from: Self.referenceDate)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let parsed = try #require(formatter.date(from: stamp))
        let expected = Self.referenceDate.timeIntervalSince1970.rounded(.down)

        #expect(abs(parsed.timeIntervalSince1970 - expected) < 1)
    }

    // MARK: - Historical dates

    @Test("Pads single-digit months, days and times")
    func padsSingleDigitFields() {
        // 2021-01-02 03:04:05 UTC — every field is single digit in UTC.
        let padded = Date(timeIntervalSince1970: 1_609_557_845)
        let stamp = ExportFilename.timestamp(from: padded)
        let parts = Self.gregorianComponents(for: padded)

        let expected = String(
            format: "%04d%02d%02d_%02d%02d%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )

        #expect(stamp == expected)
        #expect(stamp.count == 15, "padding must keep the width fixed")
    }
}

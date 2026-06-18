//
//  URLConfigFetcherResolveURLTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for URLConfigFetcher.resolveToRawURL (GitHub blob / Gist → raw
//  rewriting). Split from URLConfigFetcherTests.swift to keep that file
//  under the file_length limit.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

// MARK: - resolveToRawURL

@Suite("URLConfigFetcher.resolveToRawURL")
struct URLConfigFetcherResolveURLTests {

    @Test("rewrites github.com /blob/ URLs to raw.githubusercontent.com")
    func rewritesGithubBlobURL() throws {
        let blob = try #require(URL(string: "https://github.com/realm/SwiftLint/blob/main/.swiftlint.yml"))
        let raw = URLConfigFetcher.resolveToRawURL(blob)
        #expect(raw.host == "raw.githubusercontent.com")
        #expect(raw.path == "/realm/SwiftLint/main/.swiftlint.yml")
        #expect(raw.scheme == "https")
    }

    @Test("rewrites gist.github.com URLs to gist.githubusercontent.com/.../raw")
    func rewritesGistURL() throws {
        let gist = try #require(URL(string: "https://gist.github.com/alice/abc123"))
        let raw = URLConfigFetcher.resolveToRawURL(gist)
        #expect(raw.host == "gist.githubusercontent.com")
        #expect(raw.path == "/alice/abc123/raw")
    }

    @Test("leaves already-raw gist URLs untouched")
    func leavesRawGistAlone() throws {
        let alreadyRaw = try #require(URL(string: "https://gist.github.com/alice/abc123/raw"))
        let resolved = URLConfigFetcher.resolveToRawURL(alreadyRaw)
        #expect(resolved == alreadyRaw)
    }

    @Test("leaves unrelated https URLs untouched")
    func leavesOtherHostsAlone() throws {
        let url = try #require(URL(string: "https://example.com/path/.swiftlint.yml"))
        #expect(URLConfigFetcher.resolveToRawURL(url) == url)
    }

    /// Idempotence: resolving an already-resolved URL must be a no-op, so
    /// `resolveToRawURL(resolveToRawURL(x)) == resolveToRawURL(x)` for every
    /// input class. Each rewrite changes the host away from `github.com` /
    /// `gist.github.com`, so a second pass falls through unchanged — a
    /// regression here (e.g. double-rewriting or re-appending `/raw`) would
    /// corrupt URLs that flow through the resolver more than once.
    /// Surfaced as an idempotence candidate by SwiftInferProperties.
    @Test(
        "resolveToRawURL is idempotent across all input classes",
        arguments: [
            "https://github.com/realm/SwiftLint/blob/main/.swiftlint.yml",            // github blob
            "https://gist.github.com/alice/abc123",                                   // gist (gets /raw)
            "https://gist.github.com/alice/abc123/raw",                               // already-raw gist
            "https://github.com/realm/SwiftLint",                                     // github, no /blob/
            "https://raw.githubusercontent.com/realm/SwiftLint/main/.swiftlint.yml",  // already raw
            "https://example.com/path/.swiftlint.yml"                                 // unrelated host
        ]
    )
    func resolveToRawURLIsIdempotent(input: String) throws {
        let url = try #require(URL(string: input))
        let once = URLConfigFetcher.resolveToRawURL(url)
        let twice = URLConfigFetcher.resolveToRawURL(once)
        #expect(twice == once)
    }
}

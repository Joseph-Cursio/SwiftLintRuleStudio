//
//  URLConfigFetcherValidateURLTests.swift
//  SwiftLintRuleStudioTests
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

// The URLProtocol stub and shared fetcher helpers live in
// URLConfigFetcherStubURLProtocol.swift to keep this file under file_length.
func httpsURL(_ string: String = "https://example.com/.swiftlint.yml") throws -> URL {
    try #require(URL(string: string))
}

@Suite("URLConfigFetcher.validateURL")
struct URLConfigFetcherValidateURLTests {

    @Test("https URL with host is valid")
    func httpsURLIsValid() throws {
        let fetcher = URLConfigFetcher()
        let url = try httpsURL()
        #expect(fetcher.validateURL(url) == .valid)
    }

    @Test("http URL is reported as insecure scheme")
    func httpURLIsInsecure() throws {
        let fetcher = URLConfigFetcher()
        let url = try #require(URL(string: "http://example.com/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .insecureScheme)
    }

    @Test("file URL is reported as unsupported scheme")
    func fileURLIsUnsupported() throws {
        let fetcher = URLConfigFetcher()
        let url = try #require(URL(string: "file:///tmp/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .unsupportedScheme)
    }

    @Test("URL without scheme is invalid format")
    func noSchemeIsInvalid() throws {
        let fetcher = URLConfigFetcher()
        // relative path produces no scheme
        let url = try #require(URL(string: "/tmp/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .invalidFormat)
    }

    @Test("https URL without host is invalid format")
    func httpsWithoutHostIsInvalid() throws {
        let fetcher = URLConfigFetcher()
        let url = try #require(URL(string: "https:///path/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .invalidFormat)
    }
}

//
//  URLConfigFetcherTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for URLConfigFetcher
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
@MainActor
struct URLConfigFetcherTests {

    // MARK: - URL Validation

    @Test("Valid HTTPS URL passes validation")
    func testValidHTTPSURL() throws {
        let fetcher = URLConfigFetcher()
        let url = try #require(URL(string: "https://example.com/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .valid)
    }

    @Test("HTTP URL rejected as insecure")
    func testHTTPURLRejected() throws {
        let fetcher = URLConfigFetcher()
        let url = try #require(URL(string: "http://example.com/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .insecureScheme)
    }

    @Test("File URL rejected as unsupported")
    func testFileURLRejected() throws {
        let fetcher = URLConfigFetcher()
        let url = try #require(URL(string: "file:///tmp/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .unsupportedScheme)
    }

    @Test("FTP URL rejected as unsupported")
    func testFTPURLRejected() throws {
        let fetcher = URLConfigFetcher()
        let url = try #require(URL(string: "ftp://example.com/.swiftlint.yml"))
        #expect(fetcher.validateURL(url) == .unsupportedScheme)
    }

    // MARK: - GitHub URL Resolution

    @Test("GitHub blob URL converted to raw URL")
    func testGitHubBlobConversion() throws {
        let input = try #require(URL(string: "https://github.com/owner/repo/blob/main/.swiftlint.yml"))
        let resolved = URLConfigFetcher.resolveToRawURL(input)
        #expect(resolved.host == "raw.githubusercontent.com")
        #expect(resolved.path == "/owner/repo/main/.swiftlint.yml")
    }

    @Test("GitHub blob URL with nested path converted correctly")
    func testGitHubBlobNestedPath() throws {
        let input = try #require(URL(string: "https://github.com/owner/repo/blob/develop/configs/.swiftlint.yml"))
        let resolved = URLConfigFetcher.resolveToRawURL(input)
        #expect(resolved.host == "raw.githubusercontent.com")
        #expect(resolved.path == "/owner/repo/develop/configs/.swiftlint.yml")
    }

    @Test("Gist URL converted to raw URL")
    func testGistConversion() throws {
        let input = try #require(URL(string: "https://gist.github.com/user/abc123"))
        let resolved = URLConfigFetcher.resolveToRawURL(input)
        #expect(resolved.host == "gist.githubusercontent.com")
        #expect(resolved.path.hasSuffix("/raw"))
    }

    @Test("Already raw GitHub URL unchanged")
    func testRawGitHubURLUnchanged() throws {
        let input = try #require(URL(string: "https://raw.githubusercontent.com/owner/repo/main/.swiftlint.yml"))
        let resolved = URLConfigFetcher.resolveToRawURL(input)
        #expect(resolved == input)
    }

    @Test("Non-GitHub URL unchanged")
    func testNonGitHubURLUnchanged() throws {
        let input = try #require(URL(string: "https://example.com/config/.swiftlint.yml"))
        let resolved = URLConfigFetcher.resolveToRawURL(input)
        #expect(resolved == input)
    }

    // MARK: - Mock URLProtocol Tests

    @Test("Fetches valid YAML content")
    func testFetchValidYAML() async throws {
        let yamlContent = "disabled_rules:\n  - trailing_whitespace\n"
        let responseData = try #require(yamlContent.data(using: .utf8))
        let session = MockURLProtocol.createSession(responseData: responseData, statusCode: 200)
        let fetcher = URLConfigFetcher(session: session)
        let url = try #require(URL(string: "https://example.com/.swiftlint.yml"))
        let result = try await fetcher.fetchConfig(from: url)
        #expect(result == yamlContent)
    }

    @Test("Rejects invalid YAML content")
    func testRejectsInvalidYAML() async throws {
        let invalidContent = "{{{{not yaml at all::::"
        let responseData = try #require(invalidContent.data(using: .utf8))
        let session = MockURLProtocol.createSession(responseData: responseData, statusCode: 200)
        let fetcher = URLConfigFetcher(session: session)

        await #expect(throws: URLConfigFetcherError.self) {
            let url = try #require(URL(string: "https://example.com/.swiftlint.yml"))
            _ = try await fetcher.fetchConfig(from: url)
        }
    }

    @Test("Handles HTTP error status")
    func testHTTPErrorStatus() async throws {
        let session = MockURLProtocol.createSession(responseData: Data(), statusCode: 404)
        let fetcher = URLConfigFetcher(session: session)

        await #expect(throws: URLConfigFetcherError.self) {
            let url = try #require(URL(string: "https://example.com/.swiftlint.yml"))
            _ = try await fetcher.fetchConfig(from: url)
        }
    }

    @Test("Rejects insecure URL during fetch")
    func testRejectsInsecureURLDuringFetch() async throws {
        let fetcher = URLConfigFetcher()
        await #expect(throws: URLConfigFetcherError.self) {
            let url = try #require(URL(string: "http://example.com/.swiftlint.yml"))
            _ = try await fetcher.fetchConfig(from: url)
        }
    }
}

// MARK: - Mock URLProtocol

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var responseStatusCode: Int = 200

    static func createSession(responseData: Data, statusCode: Int) -> URLSession {
        MockURLProtocol.responseData = responseData
        MockURLProtocol.responseStatusCode = statusCode

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = MockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

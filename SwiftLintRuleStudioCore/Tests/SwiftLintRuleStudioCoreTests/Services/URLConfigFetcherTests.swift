//
//  URLConfigFetcherTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for URLConfigFetcher fetch + validation logic.
//
//  Network calls are intercepted via a custom URLProtocol installed on a
//  URLSession injected through URLConfigFetcher.init(session:). No real
//  network traffic is performed.
//

import Foundation
import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport

// MARK: - URLProtocol stub

/// Intercepts every request on the test URLSession and returns a canned
/// response or error. State is stored in nonisolated globals guarded by a
/// lock so that Sendable / strict concurrency rules are satisfied.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    struct Stub: Sendable {
        let data: Data?
        let statusCode: Int
        let headers: [String: String]
        let error: Error?
    }

    nonisolated(unsafe) static var stubProvider: (@Sendable (URL) -> Stub)?
    nonisolated(unsafe) static var observedURLs: [URL] = []
    nonisolated(unsafe) private static let lock = NSLock()

    nonisolated static func install(_ provider: @escaping @Sendable (URL) -> Stub) {
        lock.lock(); defer { lock.unlock() }
        stubProvider = provider
        observedURLs = []
    }

    nonisolated static func reset() {
        lock.lock(); defer { lock.unlock() }
        stubProvider = nil
        observedURLs = []
    }

    nonisolated static func recordedURLs() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return observedURLs
    }

    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override nonisolated init(
        request: URLRequest,
        cachedResponse: CachedURLResponse?,
        client: URLProtocolClient?
    ) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    override nonisolated func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        Self.observedURLs.append(url)
        let provider = Self.stubProvider
        Self.lock.unlock()

        guard let provider = provider else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        let stub = provider(url)

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = stub.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override nonisolated func stopLoading() {}
}

private func makeStubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    config.timeoutIntervalForRequest = 5
    config.timeoutIntervalForResource = 5
    return URLSession(configuration: config)
}

private func makeFetcher() -> URLConfigFetcher {
    URLConfigFetcher(session: makeStubbedSession())
}

private func httpsURL(_ string: String = "https://example.com/.swiftlint.yml") throws -> URL {
    try #require(URL(string: string))
}

// MARK: - validateURL

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
}

// MARK: - fetchConfig (stubbed network)

@Suite("URLConfigFetcher.fetchConfig", .serialized)
struct URLConfigFetcherFetchTests {

    private func install(_ provider: @escaping @Sendable (URL) -> StubURLProtocol.Stub) {
        StubURLProtocol.install(provider)
    }

    @Test("returns body for a 200 response with valid YAML")
    func returnsBodyOn200() async throws {
        let body = "line_length:\n  warning: 120\n  error: 200\n"
        install { _ in
            StubURLProtocol.Stub(
                data: body.data(using: .utf8),
                statusCode: 200,
                headers: ["Content-Type": "text/yaml"],
                error: nil
            )
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetchConfig(from: try httpsURL())
        #expect(result == body)
    }

    @Test("rejects http URL before any network call")
    func rejectsHTTPURL() async throws {
        install { _ in
            StubURLProtocol.Stub(data: Data(), statusCode: 200, headers: [:], error: nil)
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        let url = try #require(URL(string: "http://example.com/.swiftlint.yml"))

        await #expect(throws: URLConfigFetcherError.self) {
            _ = try await fetcher.fetchConfig(from: url)
        }
        // Confirm no network request was issued.
        #expect(StubURLProtocol.recordedURLs().isEmpty)

        do {
            _ = try await fetcher.fetchConfig(from: url)
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .insecureURL = error { /* ok */ } else {
                Issue.record("expected .insecureURL, got \(error)")
            }
        }
    }

    @Test("rejects unsupported scheme as invalidURL")
    func rejectsUnsupportedScheme() async throws {
        install { _ in
            StubURLProtocol.Stub(data: Data(), statusCode: 200, headers: [:], error: nil)
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        let url = try #require(URL(string: "ftp://example.com/.swiftlint.yml"))

        do {
            _ = try await fetcher.fetchConfig(from: url)
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .invalidURL = error { /* ok */ } else {
                Issue.record("expected .invalidURL, got \(error)")
            }
        }
        #expect(StubURLProtocol.recordedURLs().isEmpty)
    }

    @Test("404 response throws httpError(404)")
    func http404() async throws {
        install { _ in
            StubURLProtocol.Stub(
                data: "not found".data(using: .utf8),
                statusCode: 404,
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchConfig(from: try httpsURL())
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .httpError(let code) = error {
                #expect(code == 404)
            } else {
                Issue.record("expected .httpError(404), got \(error)")
            }
        }
    }

    @Test("500 response throws httpError(500)")
    func http500() async throws {
        install { _ in
            StubURLProtocol.Stub(data: Data(), statusCode: 500, headers: [:], error: nil)
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchConfig(from: try httpsURL())
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .httpError(let code) = error {
                #expect(code == 500)
            } else {
                Issue.record("expected .httpError(500), got \(error)")
            }
        }
    }

    @Test("transport error is reported as networkError")
    func transportErrorIsNetworkError() async throws {
        install { _ in
            StubURLProtocol.Stub(
                data: nil,
                statusCode: 0,
                headers: [:],
                error: URLError(.cannotConnectToHost)
            )
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchConfig(from: try httpsURL())
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .networkError = error { /* ok */ } else {
                Issue.record("expected .networkError, got \(error)")
            }
        }
    }

    @Test("URLError.timedOut is reported as .timeout")
    func timeoutMapsToTimeoutCase() async throws {
        install { _ in
            StubURLProtocol.Stub(
                data: nil,
                statusCode: 0,
                headers: [:],
                error: URLError(.timedOut)
            )
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchConfig(from: try httpsURL())
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .timeout = error { /* ok */ } else {
                Issue.record("expected .timeout, got \(error)")
            }
        }
    }

    @Test("non-UTF8 response body throws invalidYAML")
    func nonUTF8BodyIsInvalidYAML() async throws {
        // 0xFF 0xFE 0xFD is not valid UTF-8.
        let bytes = Data([0xFF, 0xFE, 0xFD, 0xFC])
        install { _ in
            StubURLProtocol.Stub(data: bytes, statusCode: 200, headers: [:], error: nil)
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchConfig(from: try httpsURL())
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .invalidYAML(let message) = error {
                #expect(message.contains("UTF-8"))
            } else {
                Issue.record("expected .invalidYAML, got \(error)")
            }
        }
    }

    @Test("malformed YAML response body throws invalidYAML")
    func malformedYAMLBodyIsInvalidYAML() async throws {
        // Unbalanced bracket / bad flow mapping — Yams.compose rejects this.
        let malformed = "key: [unterminated\n  another: ]\n"
        install { _ in
            StubURLProtocol.Stub(
                data: malformed.data(using: .utf8),
                statusCode: 200,
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchConfig(from: try httpsURL())
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .invalidYAML = error { /* ok */ } else {
                Issue.record("expected .invalidYAML, got \(error)")
            }
        }
    }

    @Test("valid YAML that is a top-level array still returns body (Yams accepts it)")
    func topLevelArrayYAMLIsReturned() async throws {
        // URLConfigFetcher only validates that the body is parseable YAML — it
        // does not enforce a mapping shape. Document that contract here.
        let body = "- one\n- two\n- three\n"
        install { _ in
            StubURLProtocol.Stub(
                data: body.data(using: .utf8),
                statusCode: 200,
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetchConfig(from: try httpsURL())
        #expect(result == body)
    }

    @Test("empty body is accepted (parses as null YAML)")
    func emptyBodyIsAccepted() async throws {
        install { _ in
            StubURLProtocol.Stub(data: Data(), statusCode: 200, headers: [:], error: nil)
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetchConfig(from: try httpsURL())
        #expect(result.isEmpty)
    }

    @Test("github.com /blob/ URL is rewritten before the network call")
    func blobURLIsResolvedBeforeFetch() async throws {
        let body = "disabled_rules:\n  - line_length\n"
        install { _ in
            StubURLProtocol.Stub(
                data: body.data(using: .utf8),
                statusCode: 200,
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        let blob = try #require(URL(string: "https://github.com/realm/SwiftLint/blob/main/.swiftlint.yml"))
        let result = try await fetcher.fetchConfig(from: blob)
        #expect(result == body)

        let recorded = StubURLProtocol.recordedURLs()
        #expect(recorded.count == 1)
        #expect(recorded.first?.host == "raw.githubusercontent.com")
        #expect(recorded.first?.path == "/realm/SwiftLint/main/.swiftlint.yml")
    }

    @Test("207 (non-2xx) response throws httpError with that status")
    func nonSuccess2xxBoundary() async throws {
        // 299 should still pass; 300 should fail. Verify the upper boundary.
        install { _ in
            StubURLProtocol.Stub(data: Data(), statusCode: 300, headers: [:], error: nil)
        }
        defer { StubURLProtocol.reset() }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchConfig(from: try httpsURL())
            Issue.record("expected throw")
        } catch let error as URLConfigFetcherError {
            if case .httpError(let code) = error {
                #expect(code == 300)
            } else {
                Issue.record("expected .httpError(300), got \(error)")
            }
        }
    }
}

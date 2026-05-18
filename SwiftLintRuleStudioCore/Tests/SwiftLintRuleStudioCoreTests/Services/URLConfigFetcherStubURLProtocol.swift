//
//  URLConfigFetcherStubURLProtocol.swift
//  SwiftLintRuleStudioCoreTests
//
//  Test fixture extracted from URLConfigFetcherTests so the test file stays
//  under file_length. Intercepts every request on the test URLSession and
//  returns a canned response or error. State lives in nonisolated globals
//  guarded by a lock so strict-concurrency / Sendable rules are satisfied.
//

import Foundation
@testable import SwiftLintRuleStudioCore

final class StubURLProtocol: URLProtocol, @unchecked Sendable {

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

    override nonisolated static func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = stub.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override nonisolated func stopLoading() {}
}

func makeStubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    config.timeoutIntervalForRequest = 5
    config.timeoutIntervalForResource = 5
    return URLSession(configuration: config)
}

func makeFetcher() -> URLConfigFetcher {
    URLConfigFetcher(session: makeStubbedSession())
}

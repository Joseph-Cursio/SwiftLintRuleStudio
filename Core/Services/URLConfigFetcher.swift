//
//  URLConfigFetcher.swift
//  SwiftLintRuleStudio
//
//  Service for downloading YAML configuration from URLs
//

import Foundation
import Yams

// MARK: - Protocol

protocol URLConfigFetcherProtocol: Sendable {
    func fetchConfig(from url: URL) async throws -> String
    func validateURL(_ url: URL) -> URLValidationResult
}

// MARK: - Types

enum URLValidationResult: Sendable, Equatable {
    case valid
    case insecureScheme
    case invalidFormat
    case unsupportedScheme
}

enum URLConfigFetcherError: LocalizedError, Sendable {
    case invalidURL
    case insecureURL
    case networkError(String)
    case invalidYAML(String)
    case httpError(statusCode: Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is not valid."
        case .insecureURL:
            return "Only HTTPS URLs are supported for security."
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidYAML(let message):
            return "The fetched content is not valid YAML: \(message)"
        case .httpError(let statusCode):
            return "HTTP error \(statusCode)."
        case .timeout:
            return "Request timed out after 30 seconds."
        }
    }
}

// MARK: - Implementation

final class URLConfigFetcher: URLConfigFetcherProtocol, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config)
        }
    }

    func fetchConfig(from url: URL) async throws -> String {
        let validation = validateURL(url)
        switch validation {
        case .valid:
            break
        case .insecureScheme:
            throw URLConfigFetcherError.insecureURL
        case .invalidFormat, .unsupportedScheme:
            throw URLConfigFetcherError.invalidURL
        }

        let resolvedURL = Self.resolveToRawURL(url)

        let (data, response) = try await fetchData(from: resolvedURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLConfigFetcherError.networkError("Invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLConfigFetcherError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw URLConfigFetcherError.invalidYAML("Could not decode response as UTF-8 text.")
        }

        // Validate as YAML
        do {
            _ = try Yams.compose(yaml: content)
        } catch {
            throw URLConfigFetcherError.invalidYAML(error.localizedDescription)
        }

        return content
    }

    func validateURL(_ url: URL) -> URLValidationResult {
        guard let scheme = url.scheme?.lowercased() else {
            return .invalidFormat
        }

        if scheme == "http" {
            return .insecureScheme
        }

        if scheme != "https" {
            return .unsupportedScheme
        }

        guard url.host != nil else {
            return .invalidFormat
        }

        return .valid
    }

    // MARK: - URL Resolution

    /// Converts GitHub blob URLs and Gist URLs to raw content URLs
    static func resolveToRawURL(_ url: URL) -> URL {
        let host = url.host?.lowercased() ?? ""
        let path = url.path

        // GitHub blob URL: github.com/owner/repo/blob/branch/path
        // -> raw.githubusercontent.com/owner/repo/branch/path
        if host == "github.com" && path.contains("/blob/") {
            let rawPath = path.replacingOccurrences(of: "/blob/", with: "/")
            var components = URLComponents()
            components.scheme = "https"
            components.host = "raw.githubusercontent.com"
            components.path = rawPath
            if let rawURL = components.url {
                return rawURL
            }
        }

        // Gist URL: gist.github.com/user/gistId
        // -> gist.githubusercontent.com/user/gistId/raw
        if host == "gist.github.com" && !path.contains("/raw") {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "gist.githubusercontent.com"
            components.path = path + "/raw"
            if let rawURL = components.url {
                return rawURL
            }
        }

        return url
    }

    // MARK: - Private

    private func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw URLConfigFetcherError.timeout
            }
            throw URLConfigFetcherError.networkError(error.localizedDescription)
        } catch {
            throw URLConfigFetcherError.networkError(error.localizedDescription)
        }
    }
}

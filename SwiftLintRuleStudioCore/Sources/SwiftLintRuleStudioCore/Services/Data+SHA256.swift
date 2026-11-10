//
//  Data+SHA256.swift
//  SwiftLintRuleStudio
//

import CryptoKit
import Foundation

public extension Data {
    /// Computes a SHA-256 hex digest of this data
    func sha256() -> String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

extension SwiftLintCLI {
    private static let docFileReadAttempts = 20

    func generateDocsForRule(ruleId: String) async throws -> String {
        // Check current SwiftLint version
        let currentVersion = try await getVersion()

        if let cachedContent = await readCachedDocs(ruleId: ruleId, currentVersion: currentVersion) {
            return cachedContent
        }

        // Version changed or cache missing - generate new docs
        let docsDir = docsDirectory(for: currentVersion)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        if let existingContent = await readExistingDocs(
            ruleId: ruleId,
            docsDir: docsDir,
            currentVersion: currentVersion
        ) {
            return existingContent
        }

        // Generate docs - generate docs for ALL rules (not just enabled ones)
        // This ensures opt-in rules like empty_count have their documentation and examples
        _ = try await executeCommandViaShell(command: "swiftlint", arguments: [
            "generate-docs",
            "--path", docsDir.path
        ])

        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        let fileExists = await waitForFile(at: docFile, attempts: 50, delayNanoseconds: 100_000_000)

        guard fileExists else {
            let message = "Documentation file not found for rule: \(ruleId) after generation"
            throw SwiftLintError.executionFailed(message: message)
        }

        // Wait for content to be readable (up to 2 more seconds)
        guard let finalContent = await readDocFileWithRetries(
            docFile,
            attempts: Self.docFileReadAttempts,
            delayNanoseconds: 100_000_000
        ) else {
            throw SwiftLintError.executionFailed(message: "Could not read documentation file for rule: \(ruleId)")
        }

        // Cache the directory and version for future use
        try? cacheManager.saveDocsDirectory(docsDir)
        try? cacheManager.saveSwiftLintVersion(currentVersion)

        return finalContent
    }

    private func docsDirectory(for version: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent("rule_docs", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private func readCachedDocs(ruleId: String, currentVersion: String) async -> String? {
        guard let cachedVersion = try? cacheManager.getCachedSwiftLintVersion(),
              cachedVersion == currentVersion,
              let cachedDocsDir = cacheManager.getCachedDocsDirectory() else {
            return nil
        }
        let docFile = cachedDocsDir.appendingPathComponent("\(ruleId).md")
        guard FileManager.default.fileExists(atPath: docFile.path) else { return nil }
        if let content = await readDocFileWithRetries(docFile, attempts: Self.docFileReadAttempts, delayNanoseconds: 100_000_000) {
            return content
        }
        return nil
    }

    private func readExistingDocs(ruleId: String, docsDir: URL, currentVersion: String) async -> String? {
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        guard FileManager.default.fileExists(atPath: docFile.path) else { return nil }
        if let content = await readDocFileWithRetries(docFile, attempts: Self.docFileReadAttempts, delayNanoseconds: 100_000_000) {
            try? cacheManager.saveDocsDirectory(docsDir)
            try? cacheManager.saveSwiftLintVersion(currentVersion)
            return content
        }
        return nil
    }

    private func waitForFile(at fileURL: URL, attempts: Int, delayNanoseconds: UInt64) async -> Bool {
        var remaining = attempts
        while remaining > 0 {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return true
            }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            remaining -= 1
        }
        return false
    }

    private func readDocFileWithRetries(
        _ fileURL: URL,
        attempts: Int,
        delayNanoseconds: UInt64
    ) async -> String? {
        var remaining = attempts
        while remaining > 0 {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty {
                return content
            }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            remaining -= 1
        }
        return nil
    }
}

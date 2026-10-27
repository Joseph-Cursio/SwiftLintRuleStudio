import Foundation
@testable import SwiftLintFramework
@testable import SwiftLintInProcessBackend
import Testing

/// What an in-process lint leaves in SwiftLint's process-wide configuration caches. SwiftLint
/// keys them by path, and a rule simulation lints a mirror at a new path for every rule, so
/// whatever one lint left there would stay until the app quits.
///
/// The caches are global and every lint clears them, including the lints of tests running
/// alongside; nothing here relies on an entry staying put. For the same reason this can't
/// tell a lint's clearing at its end from the clearing at the next lint's start: it pins that
/// the caches don't keep what a lint put there.
struct InProcessConfigurationCacheTests {
    private static let source = "let values: [Int] = []\nlet isEmpty = values.count == 0\n"

    @Test("A lint leaves nothing in SwiftLint's configuration caches")
    func leavesNothingCached() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessConfigurationCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        for (path, text) in [
            (".swiftlint.yml", "opt_in_rules:\n  - empty_count\n"),
            ("Root.swift", Self.source),
            ("Sources/Module/Deep/File.swift", Self.source),
            ("Nested/.swiftlint.yml", "disabled_rules:\n  - empty_count\n"),
            ("Nested/Beneath/Inner.swift", Self.source)
        ] {
            let file = workspace.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: file, atomically: true, encoding: .utf8)
        }

        let data = try SwiftLintInProcessActor.lint(configPath: nil, workspacePath: workspace)
        let violations = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        // Root.swift and File.swift; the nested config turns the rule off for Inner.swift.
        #expect(violations.count { $0["rule_id"] as? String == "empty_count" } == 2)

        try CurrentWorkingDirectory.$url.withValue(workspace) {
            let root = try InProcessConfiguration.root(configPath: nil, workspacePath: workspace)
            let files = root.lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false)
            // SwiftLint's keys: the lint's root folder, then each folder its search passes, as the
            // file's path spells it; and the nested config, under the working directory.
            func key(_ folder: URL) -> String {
                "nestedPath" + root.rootDirectory.path + configFile(in: folder).path
            }
            var folders: Set<URL> = []
            for file in files {
                var folder = try #require(file.path).deletingLastPathComponent()
                while folders.insert(folder).inserted, folder.path != "/" {
                    folder = folder.deletingLastPathComponent()
                }
            }
            #expect(folders.count > 3)
            for folder in folders {
                #expect(!Configuration.getIsNestedConfigurationSelf(forIdentifier: key(folder)), "\(folder.path)")
                #expect(Configuration.getCached(forIdentifier: key(folder)) == nil, "\(folder.path)")
            }
            let nested = try #require(folders.first { $0.lastPathComponent == "Nested" })
            #expect(Configuration.getCached(forIdentifier: "\(URL.cwd) - \([configFile(in: nested)])") == nil)

            // The keys are SwiftLint's: asking it about a file caches its answer under them. A test
            // alongside can clear the caches at any moment, hence the retries.
            let inner = try #require(files.first { $0.path?.lastPathComponent == "Inner.swift" })
            let cached = (0..<5).contains { _ in
                _ = root.configuration(for: inner)
                return Configuration.getCached(forIdentifier: key(nested)) != nil
            }
            #expect(cached)
            Configuration.resetCache()
        }
    }

    private func configFile(in folder: URL) -> URL {
        folder.appending(path: Configuration.defaultFileName, directoryHint: .notDirectory)
    }
}

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// `YAMLConfigurationEngine.loadConfig(at:)` and the static parse/serialize pair behind it.
///
/// The engine holds exactly one piece of state, `configPath`, and every other member of the
/// parsing, serialization and comment extensions reads none of it. Fourteen call sites were
/// constructing an engine at a path, calling `load()`, calling `getConfig()` and discarding the
/// engine — and three of them created a temporary directory first, wrote a string they already
/// held into a file, and read it back, to reach a function that takes the string.
@MainActor
struct YAMLConfigStaticLoadTests {

    @Test("loadConfig(at:) agrees with load() + getConfig()")
    func staticLoadMatchesTheEngine() throws {
        let yaml = """
        disabled_rules:
          - force_cast
        opt_in_rules:
          - empty_count
        rules:
          line_length:
            warning: 120
        """
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yaml)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let engine = YAMLConfigurationEngine(configPath: configFile)
        try engine.load()

        let direct = try YAMLConfigurationEngine.loadConfig(at: configFile)
        #expect(direct.disabledRules == engine.getConfig().disabledRules)
        #expect(direct.optInRules == engine.getConfig().optInRules)
        #expect(direct.rules.keys.sorted() == engine.getConfig().rules.keys.sorted())
        #expect(direct.keyOrder == engine.getConfig().keyOrder)
    }

    @Test("A missing file yields an empty configuration rather than throwing")
    func missingFileIsEmptyNotAnError() throws {
        // Load-bearing: `ConfigTreeDiscovery` walks a directory tree and expects to be told
        // "nothing here" rather than to fail. `load()` has always behaved this way.
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".swiftlint.yml")

        let config = try YAMLConfigurationEngine.loadConfig(at: absent)
        #expect(config.rules.isEmpty)
        #expect(config.disabledRules == nil)
    }

    @Test("An empty document throws, as load() does")
    func emptyDocumentThrows() throws {
        // `ConfigImportService` depends on this: it catches the throw and reports
        // "Configuration appears empty" as a validation warning rather than an error.
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        #expect(throws: (any Error).self) {
            try YAMLConfigurationEngine.loadConfig(at: configFile)
        }
    }

    @Test("parse and serialize need no engine and no path")
    func theKernelStandsAlone() throws {
        // The point of the change. Before it, reaching either of these meant naming a file —
        // `ConfigurationTemplateManager` built an engine at `/tmp/temp.yml`, a path it never
        // read, never wrote, and which need not exist, purely to call `serialize`.
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast"]

        let text = try YAMLConfigurationEngine.serialize(config)
        let back = try YAMLConfigurationEngine.parse(text)
        #expect(back.disabledRules == ["force_cast"])
    }
}

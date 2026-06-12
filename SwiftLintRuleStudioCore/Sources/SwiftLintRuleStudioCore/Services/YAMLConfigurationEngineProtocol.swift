import Foundation

/// The behaviour `RuleDetailViewModel` and `RuleBrowserViewModel` need from the YAML
/// configuration engine: load the current `.swiftlint.yml`, read and diff a proposed
/// configuration, and validate/save it back to disk.
///
/// These view models *call* the engine (they never observe it), so depending on this
/// protocol instead of the concrete `YAMLConfigurationEngine` lets their tests inject a
/// stub and exercise the save/diff flow without touching the filesystem — `save`,
/// `load`, and `validate` all do real disk I/O on the concrete type.
///
/// The nested value types `YAMLConfigurationEngine.YAMLConfig` and `.ConfigDiff` are
/// referenced verbatim: they are plain data, used by qualified name across the project,
/// and intentionally left nested rather than hoisted to top level.
///
/// `@MainActor` is stated explicitly to match the rest of the Core layer (which sets
/// `defaultIsolation(MainActor.self)`) and so conformers in other targets adopt the
/// same isolation — mirroring the convention `RuleRegistryProtocol` already uses.
@MainActor
public protocol YAMLConfigurationEngineProtocol {
    /// Load configuration from the file at `configPath` into the engine's in-memory state.
    func load() throws

    /// The current in-memory configuration.
    func getConfig() -> YAMLConfigurationEngine.YAMLConfig

    /// Compute the diff between the loaded configuration and a proposed one.
    func generateDiff(
        proposedConfig: YAMLConfigurationEngine.YAMLConfig
    ) -> YAMLConfigurationEngine.ConfigDiff

    /// Validate a configuration, throwing on invalid severity values or paths.
    func validate(_ config: YAMLConfigurationEngine.YAMLConfig) throws

    /// Serialize and write a configuration to disk, optionally creating a backup.
    func save(config: YAMLConfigurationEngine.YAMLConfig, createBackup: Bool) throws
}

extension YAMLConfigurationEngine: YAMLConfigurationEngineProtocol {}

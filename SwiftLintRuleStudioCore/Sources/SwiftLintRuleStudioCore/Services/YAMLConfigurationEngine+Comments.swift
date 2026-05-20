import Foundation
import LintStudioCore

public extension YAMLConfigurationEngine {
    /// Extract and preserve comments from YAML content using the shared YAMLCommentPreserver.
    func extractComments(from content: String) {
        let preserver = YAMLCommentPreserver(yamlContent: content)
        // Store comments in the config's comments dictionary keyed by following key
        for entry in preserver.comments {
            if let key = entry.followingKey {
                currentConfig.comments[key] = entry.line
            }
        }
    }

    /// Extract and preserve the ordering of top-level YAML keys using the shared preserver.
    func extractKeyOrder(from content: String) {
        let preserver = YAMLCommentPreserver(yamlContent: content)
        currentConfig.keyOrder = preserver.keyOrder
    }

    /// Reinsert preserved comments into serialized YAML output using the shared preserver.
    ///
    /// Only comments whose anchor key still appears in `yaml` are reinserted.
    /// A key dropped from the config — e.g. a `disabled_rules` list emptied to
    /// `nil` — leaves a stale entry in `config.comments`; passing it to the
    /// shared preserver would treat it as orphaned and append it to the end of
    /// the file, corrupting the trailing layout. Filtering against the keys
    /// actually emitted discards a stale comment along with its deleted key.
    func reinsertComments(into yaml: String, config: YAMLConfig) -> String {
        guard !config.comments.isEmpty else { return yaml }

        // Drop comments whose anchor key is no longer present in the output.
        let presentKeys = Self.topLevelKeys(in: yaml)
        let liveComments = config.comments
            .filter { presentKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
        guard !liveComments.isEmpty else { return yaml }

        // Reconstruct a YAMLCommentPreserver from the surviving comments by
        // building a synthetic original YAML that the preserver can parse.
        var syntheticLines: [String] = []
        for (key, commentLine) in liveComments {
            syntheticLines.append(commentLine)
            syntheticLines.append("\(key):")
        }
        let preserver = YAMLCommentPreserver(yamlContent: syntheticLines.joined(separator: "\n"))
        return preserver.reinsertComments(into: yaml)
    }

    /// The set of top-level mapping keys present in serialized YAML output.
    ///
    /// A top-level key sits at column zero and is neither a comment nor a
    /// sequence item. Mirrors the key-detection rule used by the shared
    /// `YAMLCommentPreserver` so anchor lookups stay consistent.
    private static func topLevelKeys(in yaml: String) -> Set<String> {
        var keys: Set<String> = []
        for line in yaml.components(separatedBy: .newlines) {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("-") else { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !key.isEmpty { keys.insert(key) }
        }
        return keys
    }
}

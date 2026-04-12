import Foundation
import LintStudioCore

extension YAMLConfigurationEngine {
    /// Extract and preserve comments from YAML content using the shared YAMLCommentPreserver.
    public func extractComments(from content: String) {
        let preserver = YAMLCommentPreserver(yamlContent: content)
        // Store comments in the config's comments dictionary keyed by following key
        for entry in preserver.comments {
            if let key = entry.followingKey {
                currentConfig.comments[key] = entry.line
            }
        }
    }

    /// Extract and preserve the ordering of top-level YAML keys using the shared preserver.
    public func extractKeyOrder(from content: String) {
        let preserver = YAMLCommentPreserver(yamlContent: content)
        currentConfig.keyOrder = preserver.keyOrder
    }

    /// Reinsert preserved comments into serialized YAML output using the shared preserver.
    public func reinsertComments(into yaml: String, config: YAMLConfig) -> String {
        guard !config.comments.isEmpty else { return yaml }

        // Reconstruct a YAMLCommentPreserver from the stored comments
        // Build a synthetic original YAML that the preserver can parse
        var syntheticLines: [String] = []
        for (key, commentLine) in config.comments.sorted(by: { $0.key < $1.key }) {
            syntheticLines.append(commentLine)
            syntheticLines.append("\(key):")
        }
        let preserver = YAMLCommentPreserver(yamlContent: syntheticLines.joined(separator: "\n"))
        return preserver.reinsertComments(into: yaml)
    }
}

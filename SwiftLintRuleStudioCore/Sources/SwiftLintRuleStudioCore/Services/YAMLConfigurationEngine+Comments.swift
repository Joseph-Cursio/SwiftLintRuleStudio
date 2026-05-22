import Foundation
import LintStudioCore

public extension YAMLConfigurationEngine {
    /// Extract and preserve comments from YAML content using the shared YAMLCommentPreserver.
    ///
    /// A multi-line comment block above a key arrives from the preserver as
    /// several `CommentEntry` values that share one `followingKey`. They are
    /// accumulated in file order and stored as a single newline-joined block
    /// so the whole block survives a round-trip — not just its last line.
    func extractComments(from content: String) {
        let preserver = YAMLCommentPreserver(yamlContent: content)
        var blocks: [String: [String]] = [:]
        for entry in preserver.comments {
            guard let key = entry.followingKey else { continue }
            blocks[key, default: []].append(entry.line)
        }
        for (key, block) in blocks {
            currentConfig.comments[key] = block.joined(separator: "\n")
        }
    }

    /// Extract and preserve the ordering of top-level YAML keys using the shared preserver.
    func extractKeyOrder(from content: String) {
        let preserver = YAMLCommentPreserver(yamlContent: content)
        currentConfig.keyOrder = preserver.keyOrder
    }

    /// Reinsert preserved comments into serialized YAML output.
    ///
    /// Each anchor key's comment block is inserted directly above the line
    /// where that key reappears, as a single unit so a multi-line block keeps
    /// its original top-to-bottom line order.
    ///
    /// Only comments whose anchor key still appears in `yaml` are reinserted.
    /// A key dropped from the config — e.g. a `disabled_rules` list emptied to
    /// `nil` — leaves a stale entry in `config.comments`; filtering against the
    /// keys actually emitted discards that stale comment along with its deleted
    /// key, rather than orphaning it to the end of the file.
    func reinsertComments(into yaml: String, config: YAMLConfig) -> String {
        guard !config.comments.isEmpty else { return yaml }

        // Drop comments whose anchor key is no longer present in the output.
        let presentKeys = Self.topLevelKeys(in: yaml)
        let liveComments = config.comments
            .filter { presentKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
        guard !liveComments.isEmpty else { return yaml }

        var lines = yaml.components(separatedBy: .newlines)
        var insertions: [(index: Int, block: [String])] = []
        for (key, commentBlock) in liveComments {
            guard let targetIdx = lines.firstIndex(where: { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix(key + ":") || trimmed.hasPrefix("\"\(key)\":")
            }) else { continue }
            insertions.append((targetIdx, commentBlock.components(separatedBy: "\n")))
        }

        // Insert in reverse index order so earlier indices stay valid; each
        // block is inserted as a unit, preserving its internal line order.
        for insertion in insertions.sorted(by: { $0.index > $1.index }) {
            lines.insert(contentsOf: insertion.block, at: insertion.index)
        }
        return lines.joined(separator: "\n")
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

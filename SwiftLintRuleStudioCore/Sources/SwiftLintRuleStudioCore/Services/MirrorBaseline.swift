//
//  MirrorBaseline.swift
//  SwiftLintRuleStudio
//
//  A config's `baseline`, copied into the mirror so it filters there as it does in the workspace.
//

import Darwin
import Foundation

/// Copies a `baseline:` file into the mirror, with its file keys pointing where the mirror's
/// files are.
///
/// SwiftLint keys a baseline's violations by the file's path with the working directory taken
/// out: relative for a file in the workspace, which matches in the mirror as it is, but the
/// whole path, less its leading `/`, for one outside it — a folder a link or an `included` entry
/// reaches, whose copy in the mirror has another path. (Under `/private` SwiftLint may spell a
/// file in the workspace that way too.) Left as written, those violations would come back.
///
/// SwiftLint spells a path under `/private` with or without that prefix depending on how it
/// reached the file, so a moved violation is kept under each spelling its copy may have. Each
/// file is reported under one spelling, so that filters no more than the original does; and a
/// baseline only ever filters, so a key still unmatched over-counts, never under-counts.
nonisolated enum MirrorBaseline {
    /// A real folder and where its copy is now.
    struct Place {
        /// Absolute.
        let real: String
        /// Absolute; or nil for the workspace itself, whose files SwiftLint keys relative to the
        /// lint root in the mirror.
        let mirror: String?
    }

    /// The name the copy of a baseline gets beside the config that names it.
    static func copyName(index: Int) -> String {
        ".swiftlint-rule-studio-baseline-\(index).json"
    }

    /// Writes `baseline`, its keys moved to `places`, beside `config` as `copyName(index:)`, and
    /// returns that name — or nil when there is no baseline to copy.
    static func write(_ baseline: URL, besideConfigAt config: URL, index: Int, places: [Place]) throws -> String? {
        guard let data = try? Data(contentsOf: baseline),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let moved = entries.flatMap { entry -> [[String: Any]] in
            guard let violation = entry["violation"] as? [String: Any],
                  let location = violation["location"] as? [String: Any],
                  let key = location["file"] as? String,
                  let keys = move(key, to: places) else { return [entry] }
            return keys.map { key in
                var location = location
                location["file"] = key
                var violation = violation
                violation["location"] = location
                var entry = entry
                entry["violation"] = violation
                return entry
            }
        }
        let name = copyName(index: index)
        try JSONSerialization.data(withJSONObject: moved)
            .write(to: config.deletingLastPathComponent().appendingPathComponent(name))
        return name
    }

    /// The keys `key` may have in the mirror, when it names a file in a mirrored folder by its
    /// whole path; nil when it doesn't.
    static func move(_ key: String, to places: [Place]) -> [String]? {
        let path = "/" + key
        for place in places {
            guard let real = spellings(of: place.real).first(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
                continue
            }
            let rest = String(path.dropFirst(real.count))
            guard let mirror = place.mirror else {
                return [String(rest.drop { $0 == "/" })]
            }
            return spellings(of: mirror).map { String(($0 + rest).dropFirst()) }
        }
        return nil
    }

    /// `path` as itself, resolved, and with and without the `/private` prefix macOS hides.
    private static func spellings(of path: String) -> [String] {
        var spellings = [path]
        if let resolved = realpath(path, nil) {
            spellings.append(String(cString: resolved))
            free(resolved)
        }
        for spelling in spellings {
            let isPrivate = spelling.hasPrefix("/private/")
            spellings.append(isPrivate ? String(spelling.dropFirst("/private".count)) : "/private" + spelling)
        }
        return spellings.reduce(into: []) { unique, spelling in
            if !unique.contains(spelling) { unique.append(spelling) }
        }
    }
}

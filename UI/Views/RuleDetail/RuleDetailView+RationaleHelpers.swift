import Foundation

extension RuleDetailView {
    var relatedRules: [Rule] {
        dependencies.ruleRegistry.rules
            .filter { $0.id != rule.id && $0.category == rule.category }
            .sorted { $0.name < $1.name }
    }
    
    func extractRationale(from markdown: String) -> String? {
        guard !markdown.isEmpty else { return nil }
        
        let lines = markdown.components(separatedBy: .newlines)
        var inRationaleSection = false
        var rationaleLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if let action = rationaleSectionAction(for: trimmed, inRationaleSection: inRationaleSection) {
                switch action {
                case .start:
                    inRationaleSection = true
                    continue
                case .stop:
                    break
                }
            }
            
            if inRationaleSection {
                if shouldSkipRationaleLine(trimmed, hasContent: !rationaleLines.isEmpty) {
                    continue
                }
                if trimmed.isEmpty {
                    break
                }
                rationaleLines.append(trimmed)
            }
        }
        
        if !rationaleLines.isEmpty {
            return rationaleLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private enum RationaleSectionAction {
        case start
        case stop
    }
    
    private func rationaleSectionAction(for trimmed: String, inRationaleSection: Bool) -> RationaleSectionAction? {
        guard trimmed.hasPrefix("##") else { return nil }
        let sectionName = trimmed.lowercased()
        if sectionName.contains("rationale") || sectionName.contains("why") {
            return .start
        }
        return inRationaleSection ? .stop : nil
    }
    
    private func shouldSkipRationaleLine(_ trimmed: String, hasContent: Bool) -> Bool {
        if trimmed.hasPrefix("```") {
            return true
        }
        return !hasContent && trimmed.isEmpty
    }
    
    func extractSwiftEvolutionLinks(from markdown: String) -> [URL] {
        guard !markdown.isEmpty else { return [] }
        
        var links: [URL] = []
        
        // Look for Swift Evolution URLs
        let patterns = [
            #"https?://github\.com/apple/swift-evolution/blob/.*SE-\d+"#,
            #"https?://github\.com/apple/swift-evolution/.*SE-\d+"#,
            #"SE-\d+"#,
            #"swift-evolution.*SE-\d+"#
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
            
            regex?.enumerateMatches(in: markdown, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let range = Range(match.range, in: markdown) else { return }
                
                let matchedString = String(markdown[range])
                
                // Convert to full URL if needed
                if matchedString.hasPrefix("http") {
                    if let url = URL(string: matchedString) {
                        links.append(url)
                    }
                } else if matchedString.contains("SE-") {
                    // Extract SE number and construct URL
                    if let seNumber = matchedString.components(separatedBy: CharacterSet.decimalDigits.inverted)
                        .joined().components(separatedBy: "SE").last,
                       !seNumber.isEmpty {
                        let urlString = "https://github.com/apple/swift-evolution/blob/main/proposals/\(seNumber.prefix(4)).md"
                        if let url = URL(string: urlString) {
                            links.append(url)
                        }
                    }
                }
            }
        }
        
        return Array(Set(links)).sorted { $0.absoluteString < $1.absoluteString }
    }
}

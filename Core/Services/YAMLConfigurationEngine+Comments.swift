import Foundation

extension YAMLConfigurationEngine {
    func extractComments(from content: String) {
        let lines = content.components(separatedBy: .newlines)
        var currentKey: String?
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for comment
            if trimmed.hasPrefix("#") {
                let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                
                // Try to associate with previous or next key
                if let key = currentKey {
                    currentConfig.comments[key] = comment
                } else if index < lines.count - 1 {
                    // Look ahead for key
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if let key = extractKey(from: nextLine) {
                        currentConfig.comments[key] = comment
                    }
                }
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                // Extract key from this line
                if let key = extractKey(from: line) {
                    currentKey = key
                }
            }
        }
    }
    
    private func extractKey(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Match YAML key pattern: "key:" or "  key:"
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                return key
            }
        }
        
        return nil
    }
    
    func extractKeyOrder(from content: String) {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                if let key = extractKey(from: line) {
                    if !currentConfig.keyOrder.contains(key) {
                        currentConfig.keyOrder.append(key)
                    }
                }
            }
        }
    }
    
    func reinsertComments(into yaml: String, config: YAMLConfig) -> String {
        // Basic implementation: append comments at the end
        // More sophisticated comment preservation can be added later
        var result = yaml
        
        if !config.comments.isEmpty {
            result += "\n\n# Preserved comments:\n"
            for (key, comment) in config.comments.sorted(by: { $0.key < $1.key }) {
                result += "# \(key): \(comment)\n"
            }
        }
        
        return result
    }
}

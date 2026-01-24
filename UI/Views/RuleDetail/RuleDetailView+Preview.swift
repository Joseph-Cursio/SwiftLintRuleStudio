import SwiftUI

#Preview {
    let rule = Rule(
        id: "force_cast",
        name: "Force Cast",
        description: "Force casts should be avoided. Use optional binding or guard statements instead.",
        category: .lint,
        isOptIn: false,
        severity: .error,
        parameters: nil,
        triggeringExamples: [
            "let string = value as! String",
            "let number = data as! Int"
        ],
        nonTriggeringExamples: [
            "if let string = value as? String { }",
            "guard let number = data as? Int else { return }"
        ],
        documentation: nil,
        isEnabled: true,
        supportsAutocorrection: false,
        minimumSwiftVersion: "5.0.0",
        defaultSeverity: .error,
        markdownDocumentation: nil
    )
    
    NavigationStack {
        RuleDetailView(rule: rule)
    }
    .frame(width: 800, height: 600)
}

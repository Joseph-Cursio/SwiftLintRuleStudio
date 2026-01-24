import SwiftUI

struct CodeBlock: View {
    let code: String
    let isError: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isError ? Color.red : Color.green)
                .frame(width: 4)
            
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
        }
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

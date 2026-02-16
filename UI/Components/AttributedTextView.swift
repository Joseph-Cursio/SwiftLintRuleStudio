//
//  AttributedTextView.swift
//  SwiftLintRuleStudio
//
//  A SwiftUI wrapper for NSTextView that properly handles attributed text
//  rendering without unwanted margins.
//

import SwiftUI
import AppKit

/// A SwiftUI view that displays NSAttributedString content using NSTextView,
/// providing proper control over text margins and insets.
///
/// This view solves the issue where Text(AttributedString) with HTML-rendered
/// content includes unwanted left margins that cannot be removed through
/// standard SwiftUI or NSParagraphStyle APIs.
struct AttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure text view for display-only attributed text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        
        // Remove all text container margins and padding
        textView.textContainerInset = .zero
        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.widthTracksTextView = true
        }
        
        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Post-process attributed string to remove leading whitespace/newlines
        let cleanedString = stripLeadingWhitespace(from: attributedString)
        
        // Update attributed string content
        textView.textStorage?.setAttributedString(cleanedString)
        
        // Invalidate intrinsic content size to trigger layout update
        textView.invalidateIntrinsicContentSize()
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView else {
            return nil
        }
        
        // Use proposed width if available, otherwise use a reasonable default
        let width = proposal.width ?? 400
        
        // Calculate the height needed to display all text at this width
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }
        
        // Set container width to match proposal
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        
        // Force layout
        layoutManager.ensureLayout(for: textContainer)
        
        // Get used rect
        let usedRect = layoutManager.usedRect(for: textContainer)
        
        return CGSize(width: width, height: ceil(usedRect.height))
    }
    
    /// Strips leading whitespace and newline characters from an attributed string
    private func stripLeadingWhitespace(from attributedString: NSAttributedString) -> NSAttributedString {
        let string = attributedString.string
        
        // Find the offset of the first non-whitespace character
        var offset = 0
        for char in string {
            if !char.isWhitespace && !char.isNewline {
                break
            }
            offset += 1
        }
        
        // If there's leading whitespace, create a substring without it
        if offset > 0 && offset < attributedString.length {
            let range = NSRange(location: offset, length: attributedString.length - offset)
            return attributedString.attributedSubstring(from: range)
        }
        
        return attributedString
    }
}

// MARK: - Convenience Initializers

extension AttributedTextView {
    /// Creates an AttributedTextView from an HTML string.
    ///
    /// - Parameters:
    ///   - html: The HTML string to render
    ///   - font: The base font to use (default: system font)
    ///   - textColor: The text color (default: label color)
    init?(html: String, font: NSFont = .systemFont(ofSize: NSFont.systemFontSize), textColor: NSColor = .labelColor) {
        guard let data = html.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return nil
        }
        
        self.attributedString = attributedString
    }
}

//
//  DraggableDivider.swift
//  SwiftLintRuleStudio
//
//  A 1pt visual divider with an 8pt drag target that resizes an adjacent panel.
//  Hover shows the ↔ resize cursor. Drag updates the bound width within [minWidth, maxWidth].
//

import SwiftUI

struct DraggableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    /// Captured at the start of each drag so translation accumulates correctly.
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                width = max(minWidth, min(maxWidth, dragStartWidth + value.translation.width))
                            }
                            .onEnded { _ in
                                dragStartWidth = width
                            }
                    )
            )
            .onAppear {
                dragStartWidth = width
            }
    }
}

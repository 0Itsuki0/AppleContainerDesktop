//
//  ToolTipModifier.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/19.
//

import SwiftUI

extension View {
    func toolTip<V: View>(@ContentBuilder _ view: () -> V) -> some View {
        modifier(ToolTipModifier(onHover: view))
    }
}

private struct ToolTipModifier<V: View>: ViewModifier {
    @ContentBuilder
    var onHover: V

    @State private var hovering: Bool = false

    func body(content: Content) -> some View {
        content
            .onHover { self.hovering = $0 }
            .overlay {
                if self.hovering {
                    onHover
                }
            }
    }
}

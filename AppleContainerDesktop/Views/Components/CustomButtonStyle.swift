//
//  CustomButtonStyle.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/07.
//

import SwiftUI

struct CustomButtonStyle: ButtonStyle {
    var backgroundShape: BackgroundShape
    var backgroundColor: Color
    
    enum BackgroundShape {
        case circle
        case rectangle
        case roundedRectangle(CGFloat)
    }
    
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.all, 4)
            .background(
                self.makeBackgroundView(isPressed: configuration.isPressed)
            )
    }
    
    @ContentBuilder func makeBackgroundView(isPressed: Bool) -> some View {
        Group {
            switch backgroundShape {
            case .circle:
                Circle()
                    .fill((isPressed || !isEnabled) ? self.backgroundColor.opacity(0.5) :  self.backgroundColor)
            case .rectangle:
                Rectangle()
                    .fill((isPressed || !isEnabled) ?  self.backgroundColor.opacity(0.5) :  self.backgroundColor)
            case .roundedRectangle(let cornerRadius):
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill((isPressed || !isEnabled) ?  self.backgroundColor.opacity(0.5) :  self.backgroundColor)
            }
        }
        
    }

}

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
    var disabled: Bool = false
    
    enum BackgroundShape {
        case circle
        case rectangle
        case roundedRectangle(CGFloat)
    }

    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.all, 4)
            .background(
                self.makeBackgroundView(isPressed: configuration.isPressed)
            )
    }
    
    @ViewBuilder func makeBackgroundView(isPressed: Bool) -> some View {
        Group {
            switch backgroundShape {
            case .circle:
                Circle()
                    .fill((isPressed || disabled) ? self.backgroundColor.opacity(0.5) :  self.backgroundColor)
            case .rectangle:
                Rectangle()
                    .fill((isPressed || disabled) ?  self.backgroundColor.opacity(0.5) :  self.backgroundColor)
            case .roundedRectangle(let cornerRadius):
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill((isPressed || disabled) ?  self.backgroundColor.opacity(0.5) :  self.backgroundColor)
            }
        }
        
    }

}

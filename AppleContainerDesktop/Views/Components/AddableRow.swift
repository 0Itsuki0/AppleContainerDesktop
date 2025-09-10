//
//  AddableRow.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/10.
//

import SwiftUI

struct AddableRow<Content: View>: View {
    @ViewBuilder var content: Content

    var onAdd: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            content
            
            Spacer()
                .frame(width: 48)
            
            HStack(spacing: 8) {
                Button(action: {
                    self.onAdd()
                }, label: {
                    Image(systemName: "plus")
                        .frame(maxHeight: .infinity)
                })
                .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .blue))
                
                Button(action: {
                    self.onDelete()
                }, label: {
                    Image(systemName: "minus")
                        .frame(maxHeight: .infinity)
                })
                .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .secondary))

            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

//
//  AddRemoteImageView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import SwiftUI

struct AddRemoteImageView: View {
    
    var onConfirm: (String) -> Void
    
    @State private var text: String = ""
    @State private var errorMessages: String?
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading) {
                Text("Pull Remote Image")
                    .font(.headline)
                
                Text("Please Enter the image reference. For example: \n1. `alpine:latest` \n2. `docker.io/exampleuser/demo:latest` ")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.secondary)

            }
                        
            VStack(alignment: .leading) {
                TextField("", text: $text)
                
                if let errorMessages = self.errorMessages {
                    Text(errorMessages)
                        .font(.subheadline)
                        .foregroundStyle(.red)

                }

            }
                            
            HStack(spacing: 16) {
                Button(action: {
                    self.dismiss()
                }, label: {
                    Text("Cancel")
                        .padding(.horizontal, 2)
                })
                .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))
                
                Button(action: {
                    let trimmedReference = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedReference.isEmpty else {
                        self.errorMessages = "Image reference cannot be empty."
                        return
                    }
                    onConfirm(trimmedReference)
                    self.dismiss()
                }, label: {
                    Text("Pull")
                        .padding(.horizontal, 2)
                })
                .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))
            }
            
            .frame(maxWidth: .infinity, alignment: .trailing)
            
        }
        .padding(.all, 24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled()
      
    }

}

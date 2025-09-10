//
//  PathEditView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//


import SwiftUI

struct PathEditView: View {
    
    var title: String
    var message: String
    var onConfirm: (URL) -> Void
    var verifyExecutable: Bool
    var verifyFileURL: Bool
    
    @State var text: String

    @State private var errorMessages: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                
                Text(message)
                    .font(.subheadline)
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
                    guard var url = URL(string: text) else {
                        self.errorMessages = "Invalid URL."
                        return
                    }
                    if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                        self.errorMessages = "File does not exist."
                        return
                    }
                    if self.verifyExecutable, !FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                        self.errorMessages = "File is not an executable."
                        return
                    }
                    
                    if self.verifyFileURL, !url.isFileURL {
                        url = URL(filePath: url.path(percentEncoded: false))
                    }
                    
                    onConfirm(url)
                    self.dismiss()
                }, label: {
                    Text("Confirm")
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

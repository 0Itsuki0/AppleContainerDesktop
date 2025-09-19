//
//  ExecutableUnavailableView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/09.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExecutableUnavailableView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager
    
    @State private var showExecutablePathEdit = false
    @State private var showProgressView = false
    @State private var errorMessage: String? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss


    var body: some View {
        
        VStack(spacing: 24) {
            Text("Executable Not found")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("`container` executable is not found at the following Path: \n`\(self.userSettingsManager.executablePathUrl.absolutePath)`.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineHeight(.loose)
                    
                let string: AttributedString = (try? AttributedString(markdown: "Please download it from [GitHub](\(ApplicationManager.containerGithub?.absoluteString ?? "")) or run `brew install --cask container`, and set up a custom path to the executable if needed.")) ??
                AttributedString(stringLiteral: "Please download it from [GitHub](\(ApplicationManager.containerGithub?.path(percentEncoded: true) ?? "") or run `brew install --cask container`, and set up a custom path to the executable if needed.")
                
                Text(string)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineHeight(.loose)
                
            }
                        
            if let errorMessage = self.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 24) {
                Button(action: {
                    showExecutablePathEdit = true
                }, label: {
                    Text("Set Custom Path")
                        .padding(.horizontal, 2)
                })
                .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))

                
                if let gitHubUrl = ApplicationManager.containerGithub {
                    Button(action: {
                        self.openURL(gitHubUrl)
                    }, label: {
                        Text("Download")
                            .padding(.horizontal, 2)
                    })
                    .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))

                }
                
                Button(action: {
                    Task {
                        self.showProgressView = true

                        do {
                            try await SystemService.startSystem(
                                appDataRootUrl: self.userSettingsManager.appRootUrl,
                                executablePathUrl: self.userSettingsManager.executablePathUrl,
                                timeoutSeconds: self.userSettingsManager.startSystemTimeoutSeconds,
                                messageStreamContinuation: self.applicationManager.messageStreamContinuation
                            )

                            self.applicationManager.isSystemRunning = true
                            self.dismiss()
                        
                        } catch(let error) {
                            self.errorMessage = "\(error)"
                        }
                        
                        self.showProgressView = false

                    }
                }, label: {
                    Text("Retry")
                        .padding(.horizontal, 2)
                })
                .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))
            }

        }
        .frame(width: 360, height: 240)
        .padding(.horizontal, 48)
        .padding(.vertical)
        .sheet(isPresented: $showExecutablePathEdit, content: {
            ExecutableEditView(errorMessage: $errorMessage)
                .environment(self.userSettingsManager)
        })
        .onAppear {
            self.showProgressView = false
        }
        .sheet(isPresented: $showProgressView, content: {
            CustomProgressView()
                .environment(self.applicationManager)
        })
        .interactiveDismissDisabled()
    }
}



private struct ExecutableEditView: View {
    @Environment(UserSettingsManager.self) private var userSettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @Binding var errorMessage: String?

    var body: some View {
        @Bindable var userSettingsManager = userSettingsManager

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading) {
                Text("Set Executable Path")
                    .font(.headline)

                Text("Path to `container` executable. For example, `\(UserSettingsManager.defaultExecutablePathString)`")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            FileSelectView(fileURL: $userSettingsManager.executablePathUrl, errorMessage: $errorMessage, allowedContentTypes: [.executable])

            HStack(spacing: 16) {
                Button(action: {
                    self.dismiss()
                }, label: {
                    Text("Done")
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

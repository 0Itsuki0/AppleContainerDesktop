//
//  SettingsView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(UserSettingsManager.self) private var userSettingsManager
    @Environment(\.openURL) private var openURL
    
    @State private var errorMessage: String?
    @State private var showError: Bool = false
        

    var body: some View {
        @Bindable var userSettingsManager = userSettingsManager
        Form {
            Section("Path Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("Executable")
                        Text("Path to `container.exec`")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    
                    FileSelectView(fileURL: $userSettingsManager.executablePathUrl, errorMessage: $errorMessage, allowedContentTypes: [.executable])
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("App Data")

                        Text("Application data directory")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    FileSelectView(fileURL: $userSettingsManager.appRootUrl, errorMessage: $errorMessage, allowedContentTypes: [.directory])
                }
            }
           
            
            Section("Timeout Configuration") {
                HStack {
                    Text("Start System")
                    
                    Spacer()
                    
                    HStack {
                        TextField("", value: $userSettingsManager.startSystemTimeoutSeconds, format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)

                        Text("sec")
                    }
                    .foregroundStyle(.secondary)

                }
                .padding(.vertical, 4)
                
                HStack {
                    Text("Stop System")

                    Spacer()
                    
                    HStack {
                        TextField("", value: $userSettingsManager.shutdownSystemTimeoutSeconds, format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)

                        Text("sec")
                    }
                    .foregroundStyle(.secondary)

                }
                .padding(.vertical, 4)

                HStack {
                    Text("Stop Container")
                    
                    Spacer()

                    HStack {
                        TextField("", value: $userSettingsManager.stopContainerTimeoutSeconds, format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)

                        Text("sec")
                    }
                    .foregroundStyle(.secondary)

                }
                .padding(.vertical, 4)
            }
                    
        }
        .formStyle(.grouped)
        .padding(.all, 8)
        .alert("Oops!", isPresented: $showError, actions: {
            Button(action: {
                self.showError = false
            }, label: {
                Text("OK")
            })
        }, message: {
            Text(self.errorMessage ?? "Unknown Error")
                .lineLimit(5)
        })
        .onChange(of: self.errorMessage, initial: true, {
            if errorMessage != nil {
                self.showError = true
            }
        })
        .onChange(of: self.showError, initial: true, {
            if !showError {
                self.errorMessage = nil
            }
        })
    }
    
    
    private func openFile(_ url: URL) {
        let result = NSWorkspace.shared.selectFile(
            url.absolutePath,
            inFileViewerRootedAtPath: url.parentDirectory.absolutePath
        )
        if !result {
            self.errorMessage = "Failed to open the File."
        }
    }

}

#Preview {
    SettingsView()
        .environment(UserSettingsManager())
        .environment(ApplicationManager())

}

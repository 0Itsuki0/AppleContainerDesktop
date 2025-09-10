//
//  SettingsView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import SwiftUI

struct SettingsView: View {
    @Environment(UserSettingsManager.self) private var userSettingsManager
    @Environment(\.openURL) private var openURL
    
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    @State private var showExecutablePathEdit = false
    @State private var showAppDataPathEdit = false
    

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
                    
                    
                    HStack(spacing: 8) {
                        Text(self.userSettingsManager.executablePathUrl.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        Button {
                            print(self.userSettingsManager.executablePathUrl.pathExtension)
                            self.openFile(self.userSettingsManager.executablePathUrl)

                        } label: {
                            Image(systemName: "arrow.right")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(action: {
                            self.showExecutablePathEdit = true
                        }, label: {
                            Text("Edit")
                        })

                    }

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
                    
                    
                    HStack(spacing: 8)  {
                        
                        Text(self.userSettingsManager.appRootUrl.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        Button {
                            
                            if (FileManager.default.fileExists(atPath: self.userSettingsManager.appRootUrl.path(percentEncoded: false))) {
                                try? FileManager.default.createDirectory(
                                    at: self.userSettingsManager.appRootUrl, withIntermediateDirectories: true)
                            }
                           
                            self.openFile(self.userSettingsManager.appRootUrl)
                        } label: {
                            Image(systemName: "arrow.right")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(action: {
                            self.showAppDataPathEdit = true
                        }, label: {
                            Text("Edit")
                        })
                    }
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
        .sheet(isPresented: $showAppDataPathEdit, content: {
            PathEditView(title: "Edit App Data Path", message: "Changes will take effect the next time system starts.`", onConfirm: { url in
                self.userSettingsManager.appRootUrl = url
            }, verifyExecutable: false, verifyFileURL: true, text: self.userSettingsManager.appRootUrl.path(percentEncoded: false))
        })
        .sheet(isPresented: $showExecutablePathEdit, content: {
            PathEditView(title: "Edit Executable Path", message: "Changes will take effect the next time system starts.", onConfirm: { url in
                self.userSettingsManager.executablePathUrl = url
            },  verifyExecutable: true, verifyFileURL: false, text: self.userSettingsManager.executablePathUrl.path(percentEncoded: false))
        })
        .alert("Oops!", isPresented: $showError, actions: {
            Button(action: {
                self.showError = false
            }, label: {
                Text("OK")
            })
        }, message: {
            Text(self.errorMessage ?? "Unknown Error")
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
            url.path(percentEncoded: false),
            inFileViewerRootedAtPath: url.appending(component: "..").standardized.path(percentEncoded: false)
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

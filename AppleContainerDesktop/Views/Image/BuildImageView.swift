//
//  BuildImageView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import SwiftUI
internal import ContainerizationOCI
import UniformTypeIdentifiers
import ContainerizationOS

struct BuildImageView: View {
    
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss
    
    var onCreationFinish: () -> Void

    @SwiftUI.State private var errorMessage: String?
    
    // use a different one then applicationManager.showProgressView to show the progress view over this sheet
    @SwiftUI.State private var showProgressView: Bool = false

    @SwiftUI.State private var showAdditionalSettings: Bool = false
    
    
    @SwiftUI.State private var dockerFile: URL?
    @SwiftUI.State private var contextDirectory: URL?
    @SwiftUI.State private var tag: String = ""
    @SwiftUI.State private var platformString: String = Platform.current.description
    @SwiftUI.State private var buildArguments: [KeyValueModel] = []
    @SwiftUI.State private var targetStage: String = ""

    // TODO: Additional Parameters to add
    // cpus: Int64 = 2,
    // memory: UInt64 = 1024.mib(),
    // vSockPort: UInt32 = 8088,
    // outputs: [BuildImageOutputConfiguration] = [.init(type: .oci, additionalFields: [:])],
    // labels: [String:String] = [:],
    // noCache: Bool = false,
    // cacheIn: [String] = [],
    // cacheOut: [String] = [],

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Build Image From Dockerfile")
                        .font(.headline)
                                        
                    if let errorMessage = self.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)

                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Context Directory")
                    FileSelectView(fileURL: $contextDirectory, errorMessage: $errorMessage, allowedContentTypes: [.directory])
                        .onChange(of: contextDirectory, {
                            guard let url = contextDirectory, dockerFile == nil else {
                                return
                            }
                            let dockerfileURL = url.appending(path: "Dockerfile")
                            if FileManager.default.fileExists(atPath: dockerfileURL.absolutePath) {
                                self.dockerFile = dockerfileURL
                            }
                        })
                }
                
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dockerfile")
                    FileSelectView(fileURL: $dockerFile, errorMessage: $errorMessage, allowedContentTypes: [.item])
                        .onChange(of: dockerFile, {
                            guard let url = dockerFile, contextDirectory == nil else {
                                return
                            }
                            contextDirectory = url.parentDirectory
                        })
                }

                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Tag")
                    Text("⭑ If empty, a generated UUID will be used.")
                        .lineLimit(1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField(text: $tag, prompt: Text("Ex: demo:latest"), label: {})
                }

                
                Divider()
                
                
                // TODO: add more configurations
                Button(action: {
                    showAdditionalSettings.toggle()
                }, label: {
                    HStack {
                        Text("Additional Settings")
                        Spacer()
                        Image(systemName: showAdditionalSettings ? "chevron.up" : "chevron.down")
                            .padding(.trailing, 4)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                
                if showAdditionalSettings {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Platforms")
                        Text("⭑ Comma separated string, ex: `linux/amd64,linux/arm64,linux/arm/v7`.")
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(text: $platformString, prompt: Text("Ex: linux/amd64,linux/arm64"), label: {})
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Stage")

                        TextField(text: $targetStage, prompt: Text("Ex: production"), label: {})
                    }

                    
                    VStack(alignment: .leading, spacing: 8) {
                        
                        HStack(alignment: .lastTextBaseline) {
                            Text("Build-time variables")
                            Text("key=value")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                        }
                        
                        Text("⭑ Anything with empty key will be removed when creating.")
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        
                        if buildArguments.isEmpty {
                            Button(action: {
                                self.buildArguments.append(.init())
                            }, label: {
                                Text("Add Env")
                                    .padding(.horizontal, 2)
                            })
                            .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))
                        }

                        ForEach($buildArguments, content: { $arg in
                            
                            HStack {

                                AddableRow(content: {
                                    TextField(text: $arg.key, label: {})
                                    Text("=")
                                    TextField(text: $arg.value, label: {})
                                }, onAdd: {
                                    self.buildArguments.append(.init())
                                }, onDelete: {
                                    self.buildArguments.removeAll(where: {$0.id == arg.id})
                                })
                                
                            }

                        })
                        
                    }


                }
                
                
                Divider()
                
                HStack(spacing: 16) {
                    Button(action: {
                        self.dismiss()
                    }, label: {
                        Text("Cancel")
                            .padding(.horizontal, 2)
                    })
                    .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))
                    
                    Button(action: {
                        guard let contextDirectory else {
                            self.errorMessage = "ContextDirectory is required."
                            return
                        }
                        
                        guard let dockerFile else {
                            self.errorMessage = "Dockerfile is required."
                            return
                        }
                        Task {
                            self.showProgressView = true
                            
                            do {
                                let platformStringArray: [String] = self.platformString.split(separator: ",").map({$0.trimmingCharacters(in: .whitespacesAndNewlines)})
                                var platforms: Set<Platform> = Set(try platformStringArray.map({try Platform(from: $0)}))
                                if platforms.isEmpty {
                                    platforms.insert(Platform.current)
                                }
                                
                                let validBuildArguments = self.buildArguments.filter({!$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty})
                                
                                try await ImageService.buildImage(
                                    dockerFile: dockerFile,
                                    contextDirectory: contextDirectory,
                                    tag: self.tag,
                                    cpus: 2,
                                    memory: 1024.mib(),
                                    vSockPort: 8088,
                                    outputs: [.init(type: .oci, additionalFields: [])],
                                    platforms: platforms,
                                    // build time variable
                                    buildArguments: validBuildArguments,
                                    labels: [],
                                    noCache: false,
                                    targetStage: self.targetStage,
                                    cacheIn: [],
                                    cacheOut: [],
                                    messageStreamContinuation: self.applicationManager.messageStreamContinuation
                                )

                                self.onCreationFinish()
                                self.dismiss()
                                
                            } catch (let error) {
                                self.errorMessage = "\(error)"
                            }
                            
                            self.showProgressView = false
                        }
                    }, label: {
                        Text("Build")
                            .padding(.horizontal, 2)
                    })
                    .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))
                }
                
                .frame(maxWidth: .infinity, alignment: .trailing)
                    
            }
            .multilineTextAlignment(.leading)
            .padding(.all, 24)
            .scrollTargetLayout()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: !self.showAdditionalSettings)
        .frame(maxHeight: 440)
        .sheet(isPresented: $showProgressView, content: {
            CustomProgressView()
                .environment(self.applicationManager)
        })
        .animation(.default, value: self.buildArguments.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }
}

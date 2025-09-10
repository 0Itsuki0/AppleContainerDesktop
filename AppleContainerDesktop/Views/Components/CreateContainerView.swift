//
//  CreateContainerView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import SwiftUI
import ContainerClient
internal import ContainerizationOCI

private struct PortsConfiguration: Identifiable {
    let id: UUID = UUID()
    var host: Int = 0
    var container: Int = 0
    var publishProtocol: PublishProtocol = .tcp

    
    var publishedPort: PublishPort {
        return .init(hostAddress: "127.0.0.1", hostPort: self.host, containerPort: self.container, proto: self.publishProtocol)
    }
}


struct CreateContainerView: View {
    
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss
    
    @SwiftUI.State var imageReference: String
    var onCreationFinish: () -> Void
    
    @SwiftUI.State private var process: ContainerProcess = .init()
    
    @SwiftUI.State private var management: ContainerManagement = .init()
    @SwiftUI.State private var ports: [PortsConfiguration] = []
    @SwiftUI.State private var environments: [EnvConfiguration] = []

    @SwiftUI.State private var resource: ContainerConfiguration.Resources = .init()
    @SwiftUI.State private var registryScheme: String = RequestScheme.auto.rawValue

    @SwiftUI.State private var errorMessage: String?
    
    // use a different one then applicationManager.showProgressView to show the progress view over this sheet
    @SwiftUI.State private var showProgressView: Bool = false

    @SwiftUI.State private var showOptionalSettings: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var localImages: [ClientImage] = []


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Create New Container")
                        .font(.headline)
                                        
                    if let errorMessage = self.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)

                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("Image Name")
                        Text("Local or Remote")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        TextField(text: $imageReference, prompt: Text("Ex: alpine:latest"), label: {})
                            .frame(maxHeight: .infinity)
                        Button(action: {
                            Task {
                                do {
                                    self.showProgressView = true
                                    self.localImages = try await ImageService.listImages()
                                    self.showProgressView = false
                                    self.showPickLocalImage = true
                                } catch (let error) {
                                    self.errorMessage = "\(error)"
                                }
                            }
                        }, label: {
                            Image(systemName: "ellipsis")
                                .padding(.horizontal, 2)
                                .frame(maxHeight: .infinity)
                        })
                        .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                
                Divider()
                
                
                // TODO: add more optional settings
                Button(action: {
                    showOptionalSettings.toggle()
                }, label: {
                    HStack {
                        Text("Optional Settings")
                        Spacer()
                        Image(systemName: showOptionalSettings ? "chevron.up" : "chevron.down")
                            .padding(.trailing, 4)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                
                if showOptionalSettings {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Container Name")
                        Text("⭑ If empty, a generated UUID will be used.")
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(text: $management.name, label: {})
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 8) {
                        
                        HStack(alignment: .lastTextBaseline) {
                            Text("Publish Ports")
                            Text("[Host-port]:[Container-port]")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                        }
                        
                        Text("⭑ Anything with port `0` will be removed when creating. \n⭑ Host-ip default to `127.0.0.1`.")
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        

                        
                        if ports.isEmpty {
                            Button(action: {
                                self.ports.append(.init())

                            }, label: {
                                Text("Add Ports")
                                    .padding(.horizontal, 2)
                            })
                            .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))
                        }

                        ForEach($ports, content: { $port in
                            
                            HStack {

                                AddableRow(content: {
                                    TextField("", value: $port.host, format: .number)
                                    Text(":")
                                    TextField("", value: $port.container, format: .number)

                                    Picker(selection: $port.publishProtocol, content: {
                                        Text(PublishProtocol.tcp.rawValue.localizedUppercase)
                                            .tag(PublishProtocol.tcp)
                                        Text(PublishProtocol.udp.rawValue.localizedUppercase)
                                            .tag(PublishProtocol.udp)

                                    }, label: { })

                                }, onAdd: {
                                    self.ports.append(.init())
                                }, onDelete: {
                                    self.ports.removeAll(where: {$0.id == port.id})
                                })
                                
                            }

                        })
                        
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        
                        HStack(alignment: .lastTextBaseline) {
                            Text("Environment Variables")
                            Text("key=value")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                        }
                        
                        Text("⭑ Anything with empty key will be removed when creating.")
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        
                        if environments.isEmpty {
                            Button(action: {
                                self.environments.append(.init())
                            }, label: {
                                Text("Add Env")
                                    .padding(.horizontal, 2)
                            })
                            .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))
                        }

                        ForEach($environments, content: { $env in
                            
                            HStack {

                                AddableRow(content: {
                                    TextField(text: $env.key, label: {})
                                    Text("=")
                                    TextField(text: $env.value, label: {})
                                }, onAdd: {
                                    self.environments.append(.init())
                                }, onDelete: {
                                    self.environments.removeAll(where: {$0.id == env.id})
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
                        let trimmedReference = imageReference.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedReference.isEmpty else {
                            self.errorMessage = "Image is not specified."
                            return
                        }
                        Task {
                            self.showProgressView = true
                            
                            do {
                                let validPorts = self.ports.filter({$0.host > 0 && $0.container > 0})
                                self.management.publishPorts = validPorts.map(\.publishedPort)
                                let validEnvironments = self.environments.filter({!$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty})
                                self.process.environments = validEnvironments.map(\.envString)
                                
                                try await ContainerService.createContainer(
                                    imageReference: trimmedReference,
                                    arguments: [],
                                    process: self.process,
                                    management: self.management,
                                    resource: self.resource,
                                    registryScheme: self.registryScheme,
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
                        Text("Create")
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
        .fixedSize(horizontal: false, vertical: !self.showOptionalSettings)
        .frame(maxHeight: 440)
        .sheet(isPresented: $showProgressView, content: {
            CustomProgressView()
                .environment(self.applicationManager)
        })
        .sheet(isPresented: $showPickLocalImage, content: {
            LocalImagePickingView(images: $localImages, imageReference: $imageReference)
                .interactiveDismissDisabled(false)

        })
        .animation(.default, value: self.ports.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }
}




private struct LocalImagePickingView: View {
    @Binding var images: [ClientImage]
    @Binding var imageReference: String
    
    @SwiftUI.State private var searchText: String = ""
    
    @Environment(\.dismiss) private var dismiss

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredImages: [ClientImage] {
        if trimmedText.isEmpty {
            return images
        }
        let filtered = self.images.filter({
            $0.reference.contains(trimmedText) ||
            $0.description.name.contains(trimmedText)
        })
        
        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SearchBox(text: $searchText)

            
            List {
                ForEach(filteredImages, id: \.digest) { image in
                    Button(action: {
                        imageReference = image.reference
                        self.dismiss()
                    }, label: {
                        Text(image.reference)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    })

                }
            }
            .buttonStyle(.plain)
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(RoundedRectangle(cornerRadius: 4).fill(.clear).stroke(.secondary, style: .init(lineWidth: 1)))
            
            Button(action: {
                self.dismiss()
            }, label: {
                Text("Cancel")
                    .padding(.horizontal, 2)
            })
            .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))
            .frame(maxWidth: .infinity, alignment: .trailing)
        
            
        }
        .multilineTextAlignment(.leading)
        .padding(.all, 24)
        .frame(width: 440, height: 400)

    }
}



//#Preview {
//    CreateContainerView(imageReference: "", onCreationFinish: {})
//        .environment(ApplicationManager())
//}

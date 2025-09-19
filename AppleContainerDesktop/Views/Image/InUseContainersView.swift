//
//  InUseContainersView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import SwiftUI
import ContainerClient
import ContainerizationError

struct InUseContainersView: View {
    @Binding var image: ImageDisplayModel?
    
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showProgressView: Bool = false

    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    var body: some View {
        if let image = self.image {
            let containers = image.inUseContainers.map({ContainerDisplayModel($0)})
            
            VStack(alignment: .leading, spacing: 24) {
                Text(DisplayCategory.container.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Table(of: ContainerDisplayModel.self, columns: {
                    TableColumn(TableHelper.columnHeader("Name")) { container in
                        
                        Button(action: {
                            self.dismiss()
                            applicationManager.selectedContainerID = container.id
                        }, label: {
                            Text(container.name)
                                .font(.headline)
                                .lineLimit(1)
                                .underline()
                            
                        })
                        .buttonStyle(.link)
                        .frame(height: 48) // to set minimum row height
                    }
                    .width(min: 80, ideal: 80)
                    
                    TableColumn(TableHelper.columnHeader("State")) { container in
                        Text(container.state)
                    }
                    .width(64)
                    
                    TableColumn(TableHelper.columnHeader("Actions")) { container in
                        
                        HStack(spacing: 12) {
                            switch container.status {
                            case .running:
                                Button(action: {
                                    Task {
                                        self.showProgressView = true
                                        
                                        do {
                                            try await ContainerService.stopContainers(containers: [container.container], stopTimeoutSeconds: userSettingsManager.stopContainerTimeoutSeconds, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                            try await self.updateContainer(container.id)

                                            self.showProgressView = false
                                        } catch (let error) {
                                            self.errorMessage = "\(error)"
                                        }
                                    }
                                }, label: {
                                    TableHelper.actionImage(systemName: "stop.fill")
                                })
                                .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .gray))
                                
                                
                            case .stopped:
                                Button(action: {
                                    Task {
                                        self.showProgressView = true
                                        
                                        do {
                                            try await ContainerService.startContainer(container.container, attachContainerStdout: false, attachContainerStdIn: false, messageStreamContinuation: applicationManager.messageStreamContinuation)

                                            try await self.updateContainer(container.id)

                                            self.showProgressView = false
                                            
                                        } catch (let error) {
                                            self.errorMessage = "\(error)"
                                        }
                                    }
                                }, label: {
                                    TableHelper.actionImage(systemName: "play.fill")
                                })
                                .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .blue))
                                
                            case .stopping:
                                Image(systemName: "slash.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16)
                                    .foregroundStyle(.secondary)
                                
                            case .unknown:
                                Image(systemName: "slash.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                                .padding(.vertical, 12)
                            
                            Button(action: {
                                Task {
                                    self.showProgressView = true
                                    
                                    do {
                                        try await ContainerService.deleteContainers([container.container], force: true, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                        self.deleteContainer(container.id)
                                        self.showProgressView = false
                                    } catch (let error) {
                                        self.errorMessage = "\(error)"
                                    }
                                }
                                
                            }, label: {
                                TableHelper.actionImage(systemName: "trash.fill")
                            })
                            .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .red))
                            
                        }
                        .padding(.horizontal, 8)
                        
                    }
                    .width(92)
                    
                    
                }, rows: {
                    ForEach(containers)
                })
                .alternatingRowBackgrounds(.disabled)
                
                Button(action: {
                    self.dismiss()
                }, label: {
                    Text("Cancel")
                        .padding(.horizontal, 2)
                })
                .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))
                .frame(maxWidth: .infinity, alignment: .trailing)

            }
            
            .padding(.all, 24)
            .frame(width: 480, height: 440)
            .overlay(alignment: .center, content: {
                if containers.isEmpty {
                    ContentUnavailableView("No Containers Used", systemImage: DisplayCategory.image.icon)
                }
            })
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
                    self.showProgressView = false
                    self.showError = true
                }
            })
            .onChange(of: self.showError, initial: true, {
                if !showError {
                    self.errorMessage = nil
                }
            })
            .sheet(isPresented: $showProgressView, content: {
                CustomProgressView()
                    .environment(self.applicationManager)
            })
            .onDisappear {
                self.showProgressView = false
            }
            .interactiveDismissDisabled()

        }
    }
    
    
    private func updateContainer(_ id: ClientContainerID) async throws {

        let container = try await ContainerService.getContainer(id)
        guard let index = self.image?.inUseContainers.firstIndex(where: {$0.id == id }) else {
            return
        }
        self.image?.inUseContainers[index] = container

    }
    
    private func deleteContainer(_ id: ClientContainerID) {
        self.image?.inUseContainers.removeAll(where: {$0.id == id})
    }
    
}

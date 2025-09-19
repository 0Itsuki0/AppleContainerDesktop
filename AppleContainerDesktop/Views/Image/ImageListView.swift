//
//  ImageListView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//


import SwiftUI
import ContainerClient
import ContainerizationError


struct ImageListView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager

    @State private var searchText: String = ""
    
    @State private var images: [ImageDisplayModel] = []
    @State private var lastUpdated: Date? = nil

    @State private var selections = Set<ImageDisplayModel.ID>()
    
    @State private var createContainerForImage: ImageDisplayModel? = nil

    @State private var showInUseContainerForImage: ImageDisplayModel?

    @State private var showPullRemoteView: Bool = false
    @State private var showBuildImageView: Bool = false

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredImages: [ImageDisplayModel] {
        if trimmedText.isEmpty {
            return images
        }
        let filtered = self.images.filter({
            $0.name.contains(trimmedText) ||
            $0.tag.contains(trimmedText)
        })
        
        return filtered
    }
    

    var body: some View {
        VStack(alignment: .leading , spacing: 24) {
            HStack(alignment: .lastTextBaseline) {
                HStack {
                    Text(DisplayCategory.image.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Menu(content: {
                        Button(action: {
                            self.showPullRemoteView = true
                        }, label: {
                            Text("Pull Remote")
                        })
                        
                        Button(action: {
                            self.showBuildImageView = true
                        }, label: {
                            Text("Build From Dockerfile")
                        })
                        
                    }, label: {
                        Image(systemName: "plus")
                            .font(.subheadline)

                    })
                    .menuIndicator(.hidden)
                    .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .blue))

                }


                Spacer()
                
                if let lastUpdated {
                    HStack {
                        Text(String("Last updated \(lastUpdated.formatted(date: .omitted, time: .standard))"))
                        
                        Button(action: {
                            Task {
                                await self.listImages()
                            }
                        }, label: {
                            Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                        })
                    }
                    
                }
            }
            
            HStack(spacing: 36) {
                SearchBox(text: $searchText)
                    .frame(width: 280)
                
                Spacer()
                
                if !selections.isEmpty {
                    let selectedImages = self.images.filter({self.selections.contains($0.id)})
                    let allDeletable = !selectedImages.contains(where: {$0.inUse})
                    
                    HStack {
                        Button(action: {
                            Task {
                                self.applicationManager.showProgressView = selectedImages.count > 1
                                do {
                                    try await ImageService.deleteImages(selectedImages.map(\.image), messageStreamContinuation: applicationManager.messageStreamContinuation)
                                    await self.listImages()
                                    self.applicationManager.showProgressView = false
                                } catch (let error) {
                                    applicationManager.error = error
                                }
                            }
                        }, label: {
                            Text("Delete")
                                .padding(.horizontal, 2)
                        })
                        .disabled(!allDeletable)
                        .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .red, disabled: !allDeletable))
                    }
                }                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
                        
            Table(of: ImageDisplayModel.self, selection: $selections, columns: {
                TableColumn(TableHelper.columnHeader("Name")) { image in
                    
                    Text(image.name)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(height: 48)
                }
                .width(min: 80, ideal: 80)
                
                TableColumn(TableHelper.columnHeader("Tag")) { image in
                    Text(image.tag)
                        .lineLimit(1)
                }
                .width(min: 64, ideal: 64)
                
                TableColumn(TableHelper.columnHeader("State")) { image in
                    
                    Group {
                        if image.inUse {
                            Button(action: {
                                showInUseContainerForImage = image
                            }, label: {
                                Text("In use")
                                    .lineLimit(1)
                                    .underline()

                            })
                            .buttonStyle(.link)
                        } else {
                            Text("Unused")
                        }
                    }
                    .lineLimit(1)

                }
                .width(64)

                
                
                TableColumn(TableHelper.columnHeader("OS")) { image in
                    Text(image.os)
                }
                .width(min: 36, ideal: 36, max: 72)

                TableColumn(TableHelper.columnHeader("Arch")) { image in
                    Text(image.arch)
                }
                .width(min: 48, ideal: 48, max: 72)

                
                TableColumn(TableHelper.columnHeader("Variant")) { image in
                    Text(image.variant)
                }
                .width(64)
                
                TableColumn(TableHelper.columnHeader("Size")) { image in
                    Text(image.size)
                }
                .width(64)
                
                TableColumn(TableHelper.columnHeader("Created")) { image in
                    Text(image.created)
                }
                .width(min: 64, ideal: 64, max: 200)

                TableColumn(TableHelper.columnHeader("Actions")) { image in

                    HStack(spacing: 12) {
                        Button(action: {
                            self.createContainerForImage = image
                        }, label: {
                            TableHelper.actionImage(systemName: "cube.fill")
                        })
                        .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .blue))


                        
                        Divider()
                            .padding(.vertical, 12)
                        
                        Button(action: {
                            Task {
                                self.applicationManager.showProgressView = true
                                do {
                                    try await ImageService.deleteImages([image.image], messageStreamContinuation: applicationManager.messageStreamContinuation)
                                    
                                    await self.listImages()
                                    self.applicationManager.showProgressView = false
                                } catch (let error) {
                                    applicationManager.error = error
                                }
                            }
                        }, label: {
                            TableHelper.actionImage(systemName: "trash.fill")
                        })
                        .disabled(image.inUse)
                        .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .red, disabled: image.inUse))

                    }
                    .padding(.horizontal, 8)
                }
                .width(92)
                

            }, rows: {
                ForEach(filteredImages)
            })
            .alternatingRowBackgrounds(.disabled)
            .overlay(alignment: .center, content: {
                if !self.applicationManager.isSystemRunning {
                    SystemStoppedView()
                } else if filteredImages.isEmpty {
                    ContentUnavailableView(trimmedText.isEmpty ? "No Images Found" : "No Matching Images", systemImage: DisplayCategory.image.icon)
                }
            })
            
        }
        .onChange(of: self.applicationManager.isSystemRunning, initial: true, {
            guard self.applicationManager.isSystemRunning else {
                self.images = []
                self.lastUpdated = nil
                return
            }
            Task {
                guard self.lastUpdated == nil else {
                    return
                }
                await self.listImages()
            }
        })
        .sheet(item: $createContainerForImage, content: { image in
            CreateContainerView(imageReference: image.image.reference, onCreationFinish: {
                Task {
                    await self.listImages()
                }
            })
        })
        .sheet(isPresented: $showPullRemoteView, content: {
            AddRemoteImageView(onConfirm: { reference in
                Task {
                    self.showPullRemoteView = false
                    self.applicationManager.showProgressView = true
                    do {
                        try await ImageService.pullImage(reference: reference, messageStreamContinuation: self.applicationManager.messageStreamContinuation)
                        
                        await self.listImages()
                        self.applicationManager.showProgressView = false
                    } catch(let error) {
                        applicationManager.error = error

                    }
                }
            })
        })
        .sheet(isPresented: $showBuildImageView, content: {
            BuildImageView(onCreationFinish: {
                Task {
                    await self.listImages()
                }
            })
        })
        .sheet(item: $showInUseContainerForImage, onDismiss: {
            Task {
                await self.listImages()
            }
        }, content: { image in
            InUseContainersView(image: $showInUseContainerForImage)
        })
    }

        
    private func listImages() async {
        do {
            let containers = try await ContainerService.listContainers()
            let images = try await ImageService.listImages()
            var displayModels: [ImageDisplayModel] = []
            var failed: [(String, Error)] = []
            try await withThrowingTaskGroup(of: (ImageDisplayModel?, (String, Error)?).self) { group in
                for image in images {
                    group.addTask {
                        do {
                            let displayModel = try await ImageDisplayModel(image, containers: containers)
                            return (displayModel, nil)
                        } catch(let error) {
                            return (nil, (image.reference, error))
                        }
                    }
                }

                for try await result in group {
                    if let displayModel = result.0 {
                        displayModels.append(displayModel)
                    }
                    if let error = result.1 {
                        failed.append(error)

                    }
                }
            }
            self.images = displayModels
            self.lastUpdated = Date()

            if !failed.isEmpty {
                throw ContainerizationError(
                    .internalError,
                    message: "Failed to process one or more images: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
                )
            }
        } catch(let error) {
            applicationManager.error = error
        }
    }
}

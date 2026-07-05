//
//  VolumeListView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/11/02.
//


import SwiftUI
import ContainerResource

struct VolumeListView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager

    @State private var searchText: String = ""
    
    @State private var volumes: [VolumeDisplayModel] = []
    @State private var lastUpdated: Date? = nil

    @State private var selections = Set<VolumeDisplayModel.ID>()
    
    @State private var showLabelForVolume: VolumeDisplayModel?
    @State private var showOptionForVolume: VolumeDisplayModel?
    
    @State private var showInUseContainerForVolume: VolumeDisplayModel?

    @State private var showCreateVolumeView: Bool = false

    
    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredVolumes: [VolumeDisplayModel] {
        if trimmedText.isEmpty {
            return volumes
        }
        let filtered = self.volumes.filter({
            $0.name.contains(trimmedText)
        })
        
        return filtered
    }
    

    var body: some View {
        VStack(alignment: .leading , spacing: 24) {
            HStack(alignment: .lastTextBaseline) {
                HStack {
                    Text(DisplayCategory.volume.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Button(action: {
                        showCreateVolumeView = true
                    }, label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                    })
                    .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .blue))

                }


                Spacer()
                
                if let lastUpdated {
                    HStack {
                        Text(String("Last updated \(lastUpdated.formatted(date: .omitted, time: .standard))"))
                        
                        Button(action: {
                            Task {
                                await self.listVolumes()
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
                    let selectedVolumes = self.volumes.filter({self.selections.contains($0.id)})
                    let allDeletable = !selectedVolumes.contains(where: {$0.inUse})
                    
                    Button(action: {
                        Task {
                            self.applicationManager.showProgressView = selectedVolumes.count > 1
                            do {
                                try await VolumeService.deleteVolumes(selectedVolumes.map(\.volume),  messageStreamContinuation: applicationManager.messageStreamContinuation)
                                await self.listVolumes()
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
            .frame(maxWidth: .infinity, alignment: .leading)
                        
            Table(of: VolumeDisplayModel.self, selection: $selections, columns: {
                
                TableColumn(TableHelper.columnHeader("Name")) { volume in
                    Text(volume.name)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(height: 48)
                }
                .width(min: 80, ideal: 80)
                
                TableColumn(TableHelper.columnHeader("Type")) { volume in
                    Text(volume.volumeType.rawValue)
                }
                .width(80)

                                
                TableColumn(TableHelper.columnHeader("State")) { volume in
                    Group {
                        if volume.inUse {
                            Button(action: {
                                showInUseContainerForVolume = volume
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
                
                
                TableColumn(TableHelper.columnHeader("Size")) { volume in
                    if let size = volume.size {
                        Text(size)
                    } else {
                        Text("(Not Specified")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 80, ideal: 80, max: 120)

                
                TableColumn(TableHelper.columnHeader("Created")) { volume in
                    Text(volume.created)
                }
                .width(min: 80, ideal: 80, max: 160)
                
                
                TableColumn(TableHelper.columnHeader("Driver")) { volume in
                    Text(volume.driver)
                        .lineLimit(1)
                }
                .width(64)

                
                TableColumn(TableHelper.columnHeader("Format")) { volume in
                    Text(volume.format)
                        .lineLimit(1)
                }
                .width(64)

                TableColumn(TableHelper.columnHeader("Source")) { volume in
                    let source = volume.source
                    let fileURL = URL(filePath: source)
                    HStack(spacing: 8) {
                        Text(source)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200)
                    
                        Button {
                            self.openFile(fileURL)
                        } label: {
                            Image(systemName: "arrow.right")
                                .contentShape(Rectangle())
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.link)
                    }

                }
                .width(min: 160, ideal: 160, max: 240)
                                
                TableColumn(TableHelper.columnHeader("Label & Option")) { volume in
                    let labels = volume.labels
                    let options = volume.options
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            self.showLabelForVolume = volume
                        }, label: {
                            Text("- Labels")
                        })
                        .disabled(labels.isEmpty)
                        Button(action: {
                            self.showOptionForVolume = volume
                        }, label: {
                            Text("- Options")
                        })
                        .disabled(options.isEmpty)
                    }
                    .buttonStyle(.link)
                }
                .width(120)

                TableColumn(TableHelper.columnHeader("Actions")) { volume in

                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                self.applicationManager.showProgressView = true
                                do {
                                    try await VolumeService.deleteVolumes([volume.volume],  messageStreamContinuation: applicationManager.messageStreamContinuation)
                                    await self.listVolumes()
                                    self.applicationManager.showProgressView = false
                                } catch (let error) {
                                    applicationManager.error = error
                                }
                            }
                        }, label: {
                            TableHelper.actionImage(systemName: "trash.fill")
                        })
                        .disabled(volume.inUse)
                        .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .red, disabled: volume.inUse))
                    }
                    .padding(.horizontal, 8)
                }
                .width(80)
                

            }, rows: {
                ForEach(filteredVolumes)
            })
            .alternatingRowBackgrounds(.disabled)
            .overlay(alignment: .center, content: {
                if !self.applicationManager.isSystemRunning {
                    SystemStoppedView()
                } else if filteredVolumes.isEmpty {
                    ContentUnavailableView(trimmedText.isEmpty ? "No Volumes Found" : "No Matching Volumes", systemImage: DisplayCategory.image.icon)
                }
            })
            
        }
        .onChange(of: self.applicationManager.isSystemRunning, initial: true, {
            guard self.applicationManager.isSystemRunning else {
                self.volumes = []
                self.lastUpdated = nil
                return
            }
            Task {
                guard self.lastUpdated == nil else {
                    return
                }
                await self.listVolumes()
            }
        })
        .sheet(isPresented: $showCreateVolumeView, onDismiss: {
            Task {
                await self.listVolumes()
            }
        }, content: {
            CreateVolumeView()
        })
        .sheet(item: $showInUseContainerForVolume, onDismiss: {
            Task {
                await self.listVolumes()
            }
        }, content: { volume in
            
            InUseContainersView(containers: volume.inUseContainers.map({ContainerDisplayModel($0)}), updateContainer: { id in
                
                let container = try await ContainerService.getContainer(id)
                guard let index = self.showInUseContainerForVolume?.inUseContainers.firstIndex(where: {$0.id == id }) else {
                    return
                }
                self.showInUseContainerForVolume?.inUseContainers[index] = container

            }, deleteContainer: { id in
                self.showInUseContainerForVolume?.inUseContainers.removeAll(where: {$0.id == id})
            })
        })
        .sheet(item: $showLabelForVolume, content: { volume in
            VolumeDetailOptionView(dictionary: volume.labels, title: "Metadata", emptyText: "No Metadata Specified.")
        })
        .sheet(item: $showOptionForVolume, content: { volume in
            VolumeDetailOptionView(dictionary: volume.options, title: "Driver Specific Options", emptyText: "No Options Specified.")
        })

    }

        
    private func listVolumes() async {
        do {
            let containers = try await ContainerService.listContainers()
            let volumes = try await VolumeService.listVolumes()
            let displayModels: [VolumeDisplayModel] = volumes.map({VolumeDisplayModel($0, containers: containers)})

            self.volumes = displayModels
            self.lastUpdated = Date()

        } catch(let error) {
            applicationManager.error = error
        }
    }
        
    private func openFile(_ url: URL) {
        let _ = NSWorkspace.shared.selectFile(
            url.absolutePath,
            inFileViewerRootedAtPath: url.parentDirectory.absolutePath
        )
    }

}



private struct VolumeDetailOptionView: View {
    var dictionary: [String : String]
    var title: String
    var emptyText: String

    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        let keyValueModels = KeyValueModel.fromDictionary(dictionary)
        
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Key=Value")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            KeyValuesDisplayView(keyValues: keyValueModels, emptyText: emptyText, leftColumnWidth: 120)
            
        }
        .padding(.all, 24)
        .frame(width: 320, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .topTrailing, content: {
            Button(action: {
                self.dismiss()
            }, label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
            })
            .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .secondary))
            .padding(.all, 24)
        })
        .interactiveDismissDisabled(false)

    }
        
}

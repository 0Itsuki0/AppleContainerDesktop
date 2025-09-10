//
//  ContainerListView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/09.
//


import SwiftUI
import ContainerClient

struct ContainerListView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager

    @SwiftUI.State private var searchText: String = ""
    @SwiftUI.State private var runningContainerOnly: Bool = false
    
    @SwiftUI.State private var containers: [ContainerDisplayModel] = []
    @SwiftUI.State private var lastUpdated: Date? = nil

    @SwiftUI.State private var selections = Set<ContainerDisplayModel.ID>()
    @SwiftUI.State private var showCreateContainerView: Bool = false

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredContainers: [ContainerDisplayModel] {
        if trimmedText.isEmpty {
            return runningContainerOnly ? containers.filter({$0.status == .running}): containers
        }
        let filtered = self.containers.filter({
            $0.name.contains(trimmedText) == true ||
            $0.imageName.contains(trimmedText) ||
            $0.ports.contains(trimmedText) == true
        })
        
        return runningContainerOnly ? filtered.filter({$0.status == .running}): filtered
    }
    
    var body: some View {
        VStack(alignment: .leading , spacing: 24) {
            HStack(alignment: .lastTextBaseline) {
                HStack {
                    Text(DisplayCategory.container.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                    Button(action: {
                        self.showCreateContainerView = true
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
                                await self.listContainers()
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
                
                Toggle(isOn: $runningContainerOnly, label: {
                    Text("Running containers only")
                        .lineLimit(1)
                })
                
                Spacer()
                
                
                if !selections.isEmpty {
                    let selectedContainers = self.containers.filter({self.selections.contains($0.id)})

                    HStack {
                        Button(action: {
                            Task {
                                self.applicationManager.showProgressView = selectedContainers.count > 1
                                do {
                                    try await ContainerService.deleteContainers(selectedContainers.map(\.container), force: true, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                    await self.listContainers()
                                    self.applicationManager.showProgressView = false
                                } catch (let error) {
                                    applicationManager.error = error
                                }
                            }
                        }, label: {
                            Text("Delete")
                                .padding(.horizontal, 2)
                        })
                        .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .red))
                        
                        
                        if selectedContainers.allSatisfy({$0.container.status == .running}) {
                            Button(action: {
                                Task {
                                    self.applicationManager.showProgressView = selectedContainers.count > 1
                                    do {
                                        try await ContainerService.stopContainers(containers: selectedContainers.map(\.container), stopTimeoutSeconds: userSettingsManager.stopContainerTimeoutSeconds, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                        await self.listContainers()
                                        self.applicationManager.showProgressView = false
                                    } catch (let error) {
                                        applicationManager.error = error
                                    }
                                }

                            }, label: {
                                Text("Stop")
                                    .padding(.horizontal, 2)
                            })
                            .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .gray))

                        }

                    }
                }
                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            
            Table(of: ContainerDisplayModel.self, selection: $selections, columns: {
                TableColumn(TableHelper.columnHeader("Name")) { container in
                    
                    Button(action: {
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
                
                TableColumn(TableHelper.columnHeader("Image")) { container in
                    Text(container.imageName)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 80)

                
                TableColumn(TableHelper.columnHeader("Port(s)")) { container in
                    Text(container.ports)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .width(min: 120, ideal: 120, max: 160)
                
                TableColumn(TableHelper.columnHeader("OS")) { container in
                    Text(container.os)
                }
                .width(min: 36, ideal: 36, max: 72)
                
                TableColumn(TableHelper.columnHeader("Arch")) { container in
                    Text(container.arch)
                }
                .width(min: 48, ideal: 48, max: 72)

                
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
                                    self.applicationManager.showProgressView = true

                                    do {
                                        try await ContainerService.stopContainers(containers: [container.container], stopTimeoutSeconds: userSettingsManager.stopContainerTimeoutSeconds, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                        await self.listContainers()
                                        self.applicationManager.showProgressView = false
                                    } catch (let error) {
                                        applicationManager.error = error
                                    }
                                }
                            }, label: {
                                TableHelper.actionImage(systemName: "stop.fill")
                            })
                            .buttonStyle(CustomButtonStyle(backgroundShape: .circle, backgroundColor: .gray))

                            
                        case .stopped:
                            Button(action: {
                                Task {
                                    self.applicationManager.showProgressView = true
                                    
                                    do {
                                        try await ContainerService.startContainer(container.container, attachContainerStdout: false, attachContainerStdIn: false, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                        await self.listContainers()
                                        self.applicationManager.showProgressView = false
                                        
                                    } catch (let error) {
                                        applicationManager.error = error
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
                                self.applicationManager.showProgressView = true

                                do {
                                    try await ContainerService.deleteContainers([container.container], force: true, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                    await self.listContainers()
                                    self.applicationManager.showProgressView = false
                                } catch (let error) {
                                    applicationManager.error = error
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
                ForEach(filteredContainers)
            })
            .alternatingRowBackgrounds(.disabled)
            .overlay(alignment: .center, content: {
                if !self.applicationManager.isSystemRunning {
                    SystemStoppedView()
                } else if filteredContainers.isEmpty {
                    ContentUnavailableView(self.trimmedText.isEmpty && !self.runningContainerOnly ? "No Containers Found" : "No Matching Containers", systemImage: DisplayCategory.container.icon)
                }
            })
            
        }
        .onChange(of: self.applicationManager.isSystemRunning, initial: true, {
            guard self.applicationManager.isSystemRunning else {
                self.containers = []
                self.lastUpdated = nil
                return
            }
            
            Task {
                guard self.lastUpdated == nil else {
                    return
                }
                await self.listContainers()
            }
        })
        .onChange(of: self.applicationManager.refreshContainerNeeded, initial: true, {
            guard self.applicationManager.refreshContainerNeeded else {
                return
            }
            
            Task {
                await self.listContainers()
                self.applicationManager.refreshContainerNeeded = false
            }
        })
        .sheet(isPresented: $showCreateContainerView, content: {
            CreateContainerView(imageReference: "", onCreationFinish: {
                Task {
                    await self.listContainers()
                }
            })
        })
        
    }
    
        
    private func listContainers() async {
        do {
            self.containers = (try await ContainerService.listContainers()).map({ContainerDisplayModel($0)})
            self.lastUpdated = Date()
        } catch(let error) {
            applicationManager.error = error
        }
    }
}



//#Preview {
//    ContainerListView()
//        .environment(ApplicationManager())
//        .environment(UserSettingsManager())
//}

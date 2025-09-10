//
//  ContentView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/04.
//


import SwiftUI


struct ContentView: View {
    
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager

    @Environment(\.openSettings) private var openSettings

    @State private var showExecutableUnavailable = false

    
    var body: some View {
        @Bindable var applicationManager = applicationManager
        Group {
            NavigationSplitView(sidebar: {
                VStack {
                    ForEach(DisplayCategory.allCases) { category in
                        Button(action: {
                            applicationManager.selectedCategory = category
                        }, label: {
                            title(category.displayTitle, iconName: category.icon, selected: category == applicationManager.selectedCategory)
                                .contentShape(Rectangle())
                        })
                    }
                }
                .padding()
                .buttonStyle(.plain)
                .navigationSplitViewColumnWidth(160)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Color.gray.opacity(0.1))

            }, detail: {
                    
                NavigationStack {
                    VStack {
                        switch applicationManager.selectedCategory {
                        case .container:
                            ContainerListView()
                        case .image:
                            ImageListView()
                        }
                    }
                    .environment(self.applicationManager)
                    .environment(self.userSettingsManager)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .navigationDestination(item: $applicationManager.selectedContainerID, destination: { containerID in
                        ContainerDetailView(containerID: containerID)
                    })

                }

            })
            .toolbar(content: {
                ToolbarItem(placement: .confirmationAction, content: {
                    Menu(content: {
                        Section {
                            Button(action: {
                                self.openSettings()
                            }, label: {
                                Label("Settings", systemImage: "gearshape.fill")
                            })
                        }
                        
                        Section {
                            Button(action: {
                                // not checking applicationManager.isSystemRunning incase it is started/stopped elsewhere.
                                Task {
                                    await self.startSystem()
                                }

                            }, label: {
                                Label("Start System", systemImage: "play.fill")
                            })
                            
                            Button(action: {
                                // not checking applicationManager.isSystemRunning incase it is started/stopped elsewhere.
                                Task {
                                    await self.stopSystem()
                                }

                            }, label: {
                                Label("Stop System", systemImage: "stop.fill")
                            })
                            
                            Button(action: {
                                Task {
                                    await self.stopSystem()
                                    self.applicationManager.showError = false
                                    NSApplication.shared.terminate(nil)
                                }
                            }, label: {
                                Label("Terminate", systemImage: "power")
                            })
                        }
                    }, label: {
                        Image(systemName: "ellipsis")
                    })
                    .menuIndicator(.hidden)

                })

            })
            .task {
                guard !self.applicationManager.isSystemRunning else {
                    return
                }
                
                await self.startSystem()
            }
            .alert("Oops!", isPresented: $applicationManager.showError, actions: {
                Button(action: {
                    self.applicationManager.showError = false
                }, label: {
                    Text("OK")
                })
            }, message: {
                let message = String("\(self.applicationManager.error, default: "Unknown Error")")
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            })
            .sheet(isPresented: $applicationManager.showProgressView, content: {
                CustomProgressView()
                    .environment(self.applicationManager)
            })
            .sheet(isPresented: $showExecutableUnavailable, content: {
                ExecutableUnavailableView()
                    .environment(self.applicationManager)
                    .environment(self.userSettingsManager)
            })
            .onChange(of: self.userSettingsManager.executableExists, initial: true, {
                self.showExecutableUnavailable = !self.userSettingsManager.executableExists
            })

        }
        .frame(minWidth: 800, minHeight: 520)
    }
    
    private func title(_ string: String, iconName: String?, selected: Bool) -> some View {
        Group {
            if let iconName {
                Label(string, systemImage: iconName)
            } else {
                Text(string)
            }
        }
        .font(.headline)
        .foregroundColor(selected ? .primary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.all, 4)

    }
    
    private func startSystem() async {
        do {
            self.applicationManager.showProgressView = true
            try await SystemService.startSystem(
                appDataRootUrl: self.userSettingsManager.appRootUrl,
                executablePathUrl: self.userSettingsManager.executablePathUrl,
                timeoutSeconds: self.userSettingsManager.startSystemTimeoutSeconds,
                messageStreamContinuation: self.applicationManager.messageStreamContinuation
            )
            self.applicationManager.showProgressView = false
            self.applicationManager.isSystemRunning = true
        } catch(let error) {
            self.applicationManager.error = error
        }

    }
    
    private func stopSystem() async {
        do {
            self.applicationManager.showProgressView = true
            try await SystemService.stopSystem(
                stopContainerTimeoutSeconds: self.userSettingsManager.stopContainerTimeoutSeconds,
                shutdownTimeoutSeconds: self.userSettingsManager.shutdownSystemTimeoutSeconds,
                messageStreamContinuation: self.applicationManager.messageStreamContinuation)

            self.applicationManager.showProgressView = false
            self.applicationManager.isSystemRunning = false
            
        } catch(let error) {
            self.applicationManager.error = error
        }

    }
}

//
//#Preview {
//    ContentView()
//        .environment(ApplicationManager())
//        .environment(UserSettingsManager())
//}

//
//  ContainerDetailView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/10.
//

import SwiftUI
import ContainerClient



struct ContainerDetailView: View {
    var containerID: ClientContainerID

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager
    
    @State private var container: ContainerDisplayModel?
    @State private var selectedCategory: DetailCategory = .inspect
    
    private let leftColumnWidth: CGFloat = 240
    
    enum DetailCategory: String, Identifiable {
        case logs
        case inspect
        
        var id: String {
            return self.rawValue
        }
        
        static let allCases: [DetailCategory] = [.inspect, .logs]
    }
    
    var body: some View {
        Group {
            if let container = container {
                VStack(alignment: .leading , spacing: 16) {
                    
                    HStack {
                        VStack(alignment: .leading) {
                            
                            HStack(alignment: .lastTextBaseline, content: {
                                Text(container.id)
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text( "\(container.status == .running ? "🟢" : "🔴") \(container.state)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            })
                            
                            Text(container.imageName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            switch container.status {
                            case .running:
                                Button(action: {
                                    Task {
                                        self.applicationManager.showProgressView = true
                                        do {
                                            try await ContainerService.stopContainers(containers: [container.container], stopTimeoutSeconds: userSettingsManager.stopContainerTimeoutSeconds, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                            
                                            await self.getContainerInfo()
                                            self.applicationManager.showProgressView = false
                                            self.applicationManager.refreshContainerNeeded = true
                                        } catch (let error) {
                                            applicationManager.error = error
                                        }
                                    }
                                }, label: {
                                    controlButtonImage(systemName: "stop.fill")
                                })
                                .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .gray))

                                
                            case .stopped:
                                Button(action: {
                                    Task {
                                        self.applicationManager.showProgressView = true
                                        
                                        do {
                                            try await ContainerService.startContainer(container.container, attachContainerStdout: false, attachContainerStdIn: false, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                          
                                            await self.getContainerInfo()
                                            self.applicationManager.showProgressView = false
                                            self.applicationManager.refreshContainerNeeded = true
                                        } catch (let error) {
                                            applicationManager.error = error
                                        }
                                    }
                                }, label: {
                                    controlButtonImage(systemName: "play.fill")
                                })
                                .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))

                            case .stopping:
                                EmptyView()

                            case .unknown:
                                EmptyView()
                            }
                            
                            Button(action: {
                                Task {
                                    self.applicationManager.showProgressView = true
                                    do {
                                        try await ContainerService.deleteContainers([container.container], force: true, messageStreamContinuation: applicationManager.messageStreamContinuation)
                                        self.applicationManager.showProgressView = false
                                        self.applicationManager.selectedContainerID = nil
                                        self.applicationManager.refreshContainerNeeded = true
                                    } catch (let error) {
                                        applicationManager.error = error
                                    }
                                }

                            }, label: {
                                controlButtonImage(systemName: "trash.fill")
                            })
                            .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .red))
                            
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Divider()

                    Picker(selection: $selectedCategory, content: {
                        ForEach(DetailCategory.allCases) { category in
                            Text(category.rawValue.localizedCapitalized)
                                .tag(category)
                        }
                    }, label: {})
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    
                    switch self.selectedCategory {
                    case .logs:
                        ContainerLogsView(containerID: container.id)
                    case .inspect:
                        self.containerInspectView(container)
                    }
                }
                
            } else if !self.applicationManager.showProgressView {
                ContentUnavailableView("Container Not Found", systemImage: "cube.fill")
            }
        }
        .padding()
        .task {
            await self.getContainerInfo()
        }
    }
    
    private func getContainerInfo() async {
        do {
            self.applicationManager.showProgressView = true
            self.container = ContainerDisplayModel(try await ContainerService.getContainer(self.containerID))
            self.applicationManager.showProgressView = false
        } catch(let error) {
            self.applicationManager.error = error
        }
    }
    
    private func sectionHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

    }
    
    private func emptyText(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }
    
    private func leftColumn(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(width: self.leftColumnWidth, alignment: .leading)
            .foregroundStyle(.secondary)
    }
    
    private func rightColumn(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func controlButtonImage(systemName: String) -> some View {
        Image(systemName: systemName)
            .padding(.all, 2)
            .frame(width: 20)
            .frame(maxHeight: .infinity)

    }
    
    @ViewBuilder private func containerInspectView(_ container: ContainerDisplayModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16, content: {
                let environments = KeyValueModel.envFromContainer(container.container)
                Section {
                    if environments.isEmpty {
                        emptyText("No environments added.")
                    }
                    
                    ForEach(environments) { env in
                        HStack {
                            leftColumn(env.key)
                            rightColumn(env.value)
                        }
                        .padding(.horizontal, 16)
                        
                        Divider()
                    }
                    
                } header: {
                    sectionHeader(title: "Environment", subtitle: "Key=Value")
                }
                
                Spacer()
                    .frame(height: 8)
                
                
                Section {
                    let ports = container.container.configuration.publishedPorts
                    if ports.isEmpty {
                        emptyText("No ports added.")
                    }
                    
                    ForEach(0..<ports.count, id: \.self) { index in
                        HStack {
                            let port = ports[index]
                            let host = "\(port.hostAddress):\(port.hostPort)"
                            let container = "\(port.containerPort)[\(port.proto.rawValue.localizedUppercase)]"
                            leftColumn(host)
                            rightColumn(container)
                        }
                        .padding(.horizontal, 16)
                        
                        Divider()
                    }
                    
                } header: {
                    sectionHeader(title: "Ports", subtitle: "Host:Container[Protocol]")
                }
            })
            .scrollTargetLayout()
            .padding(.all, 8)
            .padding(.bottom, 16)
        }
    }
    
}


private struct ContainerLogsView: View {
    var containerID: ClientContainerID
    
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager

    @State private var logs: String = ""
    
    var body: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView("No Logs Available", systemImage: "text.document")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.2)))

            } else {
                ScrollView {
                    
                    VStack(alignment: .leading) {
                        Text(logs)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    }
                    .font(.subheadline)
                    .lineHeight(.loose)
                    .foregroundStyle(.secondary)
                    .scrollTargetLayout()
                    .padding(.all, 8)

                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 4).fill(.black).stroke(.secondary, style: .init(lineWidth: 1)))
            }
        }
        .task {
            await self.getLogs()
        }
    }
    
    private func getLogs() async {
        do {
            self.applicationManager.showProgressView = true
            self.logs = try await ContainerService.getContainerLog(containerID, boot: false)
            self.applicationManager.showProgressView = false
        } catch(let error) {
            self.applicationManager.error = error
        }
    }
}

#Preview {
    ContainerDetailView(containerID: "a260263f-f5ab-4ad0-85bb-3b4c6f0e2f20")
        .environment(ApplicationManager())
        .environment(UserSettingsManager())
        .frame(minWidth: 400, minHeight: 300)

}

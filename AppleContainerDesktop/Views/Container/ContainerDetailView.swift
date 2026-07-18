//
//  ContainerDetailView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/10.
//

import ContainerResource
import SwiftUI

struct ContainerDetailView: View {
    var containerID: ContainerSnapshotID

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
                VStack(alignment: .leading, spacing: 16) {

                    HStack {
                        VStack(alignment: .leading) {

                            HStack(
                                alignment: .lastTextBaseline,
                                content: {
                                    Text(container.id)
                                        .font(.title2)
                                        .fontWeight(.bold)

                                    Text(
                                        "\(container.status == .running ? "🟢" : "🔴") \(container.state)"
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                            )

                            Text(container.imageName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)

                        Spacer()

                        HStack(spacing: 8) {
                            switch container.status {
                            case .running:
                                Button(
                                    action: {
                                        Task {
                                            self.applicationManager
                                                .showProgressView = true
                                            do {
                                                try await ContainerService
                                                    .stopContainers(
                                                        [
                                                            container.container
                                                                .id
                                                        ],
                                                        stopTimeoutSeconds:
                                                            userSettingsManager
                                                            .stopContainerTimeoutSeconds,
                                                        messageStreamContinuation:
                                                            applicationManager
                                                            .messageStreamContinuation
                                                    )

                                                await self.getContainerInfo()
                                                self.applicationManager
                                                    .showProgressView = false
                                                self.applicationManager
                                                    .refreshContainerNeeded =
                                                    true
                                            } catch (let error) {
                                                applicationManager.error = error
                                            }
                                        }
                                    },
                                    label: {
                                        controlButtonImage(
                                            systemName: "stop.fill"
                                        )
                                    }
                                )
                                .buttonStyle(
                                    CustomButtonStyle(
                                        backgroundShape: .roundedRectangle(4),
                                        backgroundColor: .gray
                                    )
                                )

                            case .stopped:
                                Button(
                                    action: {
                                        Task {
                                            self.applicationManager
                                                .showProgressView = true

                                            do {
                                                try await ContainerService
                                                    .startContainer(
                                                        container.container,
                                                        attachContainerStdout:
                                                            false,
                                                        attachContainerStdIn:
                                                            false,
                                                        messageStreamContinuation:
                                                            applicationManager
                                                            .messageStreamContinuation
                                                    )

                                                await self.getContainerInfo()
                                                self.applicationManager
                                                    .showProgressView = false
                                                self.applicationManager
                                                    .refreshContainerNeeded =
                                                    true
                                            } catch (let error) {
                                                applicationManager.error = error
                                            }
                                        }
                                    },
                                    label: {
                                        controlButtonImage(
                                            systemName: "play.fill"
                                        )
                                    }
                                )
                                .buttonStyle(
                                    CustomButtonStyle(
                                        backgroundShape: .roundedRectangle(4),
                                        backgroundColor: .blue
                                    )
                                )

                            case .stopping:
                                EmptyView()

                            case .unknown:
                                EmptyView()
                            }

                            Button(
                                action: {
                                    Task {
                                        self.applicationManager
                                            .showProgressView = true
                                        do {
                                            try await ContainerService
                                                .deleteContainers(
                                                    [container.container],
                                                    force: true,
                                                    messageStreamContinuation:
                                                        applicationManager
                                                        .messageStreamContinuation
                                                )
                                            self.applicationManager
                                                .showProgressView = false
                                            self.applicationManager
                                                .selectedContainerID = nil
                                            self.applicationManager
                                                .refreshContainerNeeded = true
                                        } catch (let error) {
                                            applicationManager.error = error
                                        }
                                    }

                                },
                                label: {
                                    controlButtonImage(systemName: "trash.fill")
                                }
                            )
                            .buttonStyle(
                                CustomButtonStyle(
                                    backgroundShape: .roundedRectangle(4),
                                    backgroundColor: .red
                                )
                            )

                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    Picker(
                        selection: $selectedCategory,
                        content: {
                            ForEach(DetailCategory.allCases) { category in
                                Text(category.rawValue.localizedCapitalized)
                                    .tag(category)
                            }
                        },
                        label: {}
                    )
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
                ContentUnavailableView(
                    "Container Not Found",
                    systemImage: "cube.fill"
                )
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
            self.container = ContainerDisplayModel(
                try await ContainerService.getContainer(self.containerID)
            )
            self.applicationManager.showProgressView = false
        } catch (let error) {
            self.applicationManager.error = error
        }
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.headline)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

    }

    private func controlButtonImage(systemName: String) -> some View {
        Image(systemName: systemName)
            .padding(.all, 2)
            .frame(width: 20)
            .frame(maxHeight: .infinity)

    }

    @ContentBuilder private func containerInspectView(
        _ container: ContainerDisplayModel
    ) -> some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 16,
                content: {
                    let environments = KeyValueModel.fromContainerEnv(
                        container.container
                    )
                    let ports = KeyValueModel.fromContainerPorts(
                        container.container
                    )

                    Section {
                        KeyValuesDisplayView(
                            keyValues: environments,
                            emptyText: "No environments added",
                            leftColumnWidth: self.leftColumnWidth
                        )
                    } header: {
                        sectionHeader(
                            title: "Environment",
                            subtitle: "Key=Value"
                        )
                    }

                    Spacer()
                        .frame(height: 8)

                    Section {
                        KeyValuesDisplayView(
                            keyValues: ports,
                            emptyText: "No ports added",
                            leftColumnWidth: self.leftColumnWidth
                        )
                    } header: {
                        sectionHeader(
                            title: "Ports",
                            subtitle: "Host:Container[Protocol]"
                        )
                    }

                    Spacer()
                        .frame(height: 8)

                    Section {
                        //                    KeyValuesView(keyValues: ports, emptyText: "No ports added")
                        let volumeFSs = container.container.volumeFSs
                        if volumeFSs.isEmpty {
                            Text("No volume binded")
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                        }
                        ForEach(0..<volumeFSs.count, id: \.self) { index in
                            let fileSystem: Filesystem = volumeFSs[index]
                            if let name = fileSystem.volumeName {
                                HStack {
                                    Text(name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(
                                            width: self.leftColumnWidth,
                                            alignment: .leading
                                        )
                                        .foregroundStyle(.secondary)

                                    let fileURL = URL(
                                        filePath: fileSystem.source
                                    )

                                    HStack(spacing: 8) {
                                        Text(
                                            "\(fileSystem.source)\(fileSystem.destination)"
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 240)

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
                                .padding(.horizontal, 16)

                            }
                        }
                    } header: {
                        sectionHeader(title: "Volumes", subtitle: nil)
                    }

                    Spacer()
                        .frame(height: 8)

                    Section {
                        let networks = container.container.configuration
                            .networks
                        let attachments = container.container.networks
                        if networks.isEmpty {
                            Text("No network attached")
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                        }
                        ForEach(0..<networks.count, id: \.self) { index in
                            let network = networks[index]
                            HStack {
                                Text(network.network)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(
                                        width: self.leftColumnWidth,
                                        alignment: .leading
                                    )
                                    .foregroundStyle(.secondary)

                                if let attachment = attachments.first(where: {
                                    $0.network == network.network
                                }) {
                                    Text(
                                        "\(attachment.ipv4Address) (\(attachment.hostname))"
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                } else {
                                    Text("(Not attached)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    } header: {
                        sectionHeader(
                            title: "Networks",
                            subtitle: "IPv4-Address (Hostname)"
                        )
                    }
                }
            )
            .scrollTargetLayout()
            .padding(.all, 8)
            .padding(.bottom, 16)
        }
    }

    private func openFile(_ url: URL) {
        let _ = NSWorkspace.shared.selectFile(
            url.absolutePath,
            inFileViewerRootedAtPath: url.parentDirectory.absolutePath
        )
    }
}

private struct ContainerLogsView: View {
    var containerID: ContainerSnapshotID

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager

    @State private var logs: String = ""

    var body: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView(
                    "No Logs Available",
                    systemImage: "text.document"
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .center
                )
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(
                        .secondary.opacity(0.2)
                    )
                )

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
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(.black).stroke(
                        .secondary,
                        style: .init(lineWidth: 1)
                    )
                )
            }
        }
        .task {
            await self.getLogs()
        }
    }

    private func getLogs() async {
        do {
            self.applicationManager.showProgressView = true
            self.logs = try await ContainerService.getContainerLog(
                containerID,
                boot: false
            )
            self.applicationManager.showProgressView = false
        } catch (let error) {
            self.applicationManager.error = error
        }
    }
}

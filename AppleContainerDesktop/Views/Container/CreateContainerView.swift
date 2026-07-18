//
//  CreateContainerView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import ContainerAPIClient
import ContainerResource
import ContainerizationExtras
internal import ContainerizationOCI
import SwiftUI

private struct PortsConfiguration: Identifiable {
    let id: UUID = UUID()
    var host: Int = 0
    var container: Int = 0
    var publishProtocol: PublishProtocol = .tcp

    var publishedPort: PublishPort {
        get throws {
            return try .init(
                hostAddress: IPAddress.v4(try IPv4Address("127.0.0.1")),
                hostPort: UInt16(self.host),
                containerPort: UInt16(self.container),
                proto: self.publishProtocol,
                count: 1
            )
        }
    }
}

private struct VolumeConfigurationTemp: Identifiable {
    let id: UUID = UUID()
    var name: String = ""
    var path: String = ""
}

private struct NetworkConfigurationTemp: Identifiable {
    let id: UUID = UUID()
    var name: String = ""
}

struct CreateContainerView: View {

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State var imageReference: String

    @SwiftUI.State private var process: ContainerProcess = .init()

    @SwiftUI.State private var management: ContainerManagement = .init()
    @SwiftUI.State private var volumes: [VolumeConfigurationTemp] = []
    @SwiftUI.State private var ports: [PortsConfiguration] = []
    @SwiftUI.State private var environments: [KeyValueModel] = []

    @SwiftUI.State private var resource: ContainerConfiguration.Resources =
        .init()
    @SwiftUI.State private var registryScheme: String = RequestScheme.auto
        .rawValue

    @SwiftUI.State private var errorMessage: String?

    // use a different one then applicationManager.showProgressView to show the progress view over this sheet
    @SwiftUI.State private var showProgressView: Bool = false

    @SwiftUI.State private var showAdditionalSettings: Bool = false

    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var localImages: [ClientImage] = []

    @SwiftUI.State private var showPickVolume: Bool = false
    @SwiftUI.State private var availableVolumes: [VolumeConfiguration] = []
    @SwiftUI.State private var volumeInitialized: Bool = false

    @SwiftUI.State private var networks: [NetworkConfigurationTemp] = []
    @SwiftUI.State private var showPickNetwork: Bool = false
    @SwiftUI.State private var availableNetworks: [NetworkResource] = []
    @SwiftUI.State private var networkInitialized: Bool = false

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
                        TextField(
                            text: $imageReference,
                            prompt: Text("Ex: alpine:latest"),
                            label: {}
                        )
                        .frame(maxHeight: .infinity)
                        Button(
                            action: {
                                Task {
                                    do {
                                        self.showProgressView = true
                                        self.localImages =
                                            try await ImageService.listImages()
                                        self.showProgressView = false
                                        self.showPickLocalImage = true
                                    } catch (let error) {
                                        self.errorMessage = "\(error)"
                                    }
                                }
                            },
                            label: {
                                Image(systemName: "ellipsis")
                                    .padding(.horizontal, 2)
                                    .frame(maxHeight: .infinity)
                            }
                        )
                        .buttonStyle(
                            CustomButtonStyle(
                                backgroundShape: .roundedRectangle(4),
                                backgroundColor: .secondary
                            )
                        )
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Button(
                    action: {
                        showAdditionalSettings.toggle()
                    },
                    label: {
                        HStack {
                            Text("Optional Settings")
                            Spacer()
                            Image(
                                systemName: showAdditionalSettings
                                    ? "chevron.up" : "chevron.down"
                            )
                            .padding(.trailing, 4)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                )
                .buttonStyle(.plain)

                if showAdditionalSettings {
                    self.additionalSettings
                }

                Divider()

                HStack(spacing: 16) {
                    Button(
                        action: {
                            self.dismiss()
                        },
                        label: {
                            Text("Cancel")
                                .padding(.horizontal, 2)
                        }
                    )
                    .buttonStyle(
                        CustomButtonStyle(
                            backgroundShape: .roundedRectangle(4),
                            backgroundColor: .secondary
                        )
                    )

                    Button(
                        action: {
                            let trimmedReference =
                                imageReference.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            guard !trimmedReference.isEmpty else {
                                self.errorMessage = "Image is not specified."
                                return
                            }
                            Task {
                                self.showProgressView = true

                                do {
                                    var validVolumeFSs: [Filesystem] = []
                                    let mountOptions: [String] = []

                                    for volumeConfig in self.volumes {
                                        var volume: VolumeConfiguration
                                        if let first = self.availableVolumes
                                            .first(where: {
                                                $0.name == volumeConfig.name
                                            })
                                        {
                                            volume = first
                                        } else {
                                            var trimmedName = volumeConfig.name
                                                .trimmingCharacters(
                                                    in: .whitespacesAndNewlines
                                                )
                                            var labels: [KeyValueModel] = []

                                            if trimmedName.isEmpty {
                                                trimmedName =
                                                    VolumeStorage
                                                    .generateAnonymousVolumeName()
                                                labels.append(
                                                    .init(
                                                        key: VolumeConfiguration
                                                            .anonymousLabel
                                                    )
                                                )
                                            }

                                            volume =
                                                try await VolumeService
                                                .createVolume(
                                                    name: trimmedName,
                                                    labels: labels.dictRepresentation,
                                                    options: [:],
                                                    size: nil,
                                                    messageStreamContinuation:
                                                        self.applicationManager
                                                        .messageStreamContinuation
                                                )
                                        }

                                        let fs = Filesystem.volume(
                                            name: volume.name,
                                            format: volume.format,
                                            source: volume.source,
                                            destination: volumeConfig.path,
                                            options: mountOptions
                                        )

                                        validVolumeFSs.append(fs)
                                    }

                                    self.management.volumes = validVolumeFSs

                                    self.management.networks = self.networks
                                        .map({
                                            $0.name.trimmingCharacters(
                                                in: .whitespacesAndNewlines
                                            )
                                        })
                                        .filter({ !$0.isEmpty })

                                    let validPorts = self.ports.filter({
                                        $0.host > 0 && $0.container > 0
                                    })
                                    self.management.publishPorts =
                                        try validPorts.map {
                                            try $0.publishedPort
                                        }

                                    let validEnvironments = self.environments
                                        .filter({
                                            !$0.key.trimmingCharacters(
                                                in: .whitespacesAndNewlines
                                            ).isEmpty
                                        })
                                    self.process.environments =
                                        validEnvironments.map(
                                            \.stringRepresentation
                                        )

                                    try await ContainerService.createContainer(
                                        imageReference: trimmedReference,
                                        arguments: [],
                                        process: self.process,
                                        management: self.management,
                                        resource: self.resource,
                                        registryScheme: self.registryScheme,
                                        messageStreamContinuation: self
                                            .applicationManager
                                            .messageStreamContinuation
                                    )

                                    self.dismiss()

                                } catch (let error) {
                                    self.errorMessage = "\(error)"
                                }

                                self.showProgressView = false
                            }
                        },
                        label: {
                            Text("Create")
                                .padding(.horizontal, 2)
                        }
                    )
                    .buttonStyle(
                        CustomButtonStyle(
                            backgroundShape: .roundedRectangle(4),
                            backgroundColor: .blue
                        )
                    )
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
        .sheet(
            isPresented: $showProgressView,
            content: {
                CustomProgressView()
                    .environment(self.applicationManager)
            }
        )
        .sheet(
            isPresented: $showPickLocalImage,
            content: {
                LocalImagePickingView(
                    images: self.localImages,
                    onImageSelect: { self.imageReference = $0 }
                )
            }
        )
        .animation(.default, value: self.ports.count)
        .animation(.default, value: self.environments.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }

    // TODO: add more optional settings
    @ContentBuilder
    private var additionalSettings: some View {
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

            Text(
                "⭑ Anything with port `0` will be removed when creating. \n⭑ Host-ip default to `127.0.0.1`."
            )
            .lineLimit(1)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if ports.isEmpty {
                Button(
                    action: {
                        self.ports.append(.init())

                    },
                    label: {
                        Text("Add Port")
                            .padding(.horizontal, 2)
                    }
                )
                .buttonStyle(
                    CustomButtonStyle(
                        backgroundShape: .roundedRectangle(4),
                        backgroundColor: .blue
                    )
                )
            }

            ForEach(
                $ports,
                content: { $port in

                    AddableRow(
                        content: {
                            TextField("", value: $port.host, format: .number)
                            Text(":")
                            TextField(
                                "",
                                value: $port.container,
                                format: .number
                            )

                            Picker(
                                selection: $port.publishProtocol,
                                content: {
                                    Text(
                                        PublishProtocol.tcp.rawValue
                                            .localizedUppercase
                                    )
                                    .tag(PublishProtocol.tcp)
                                    Text(
                                        PublishProtocol.udp.rawValue
                                            .localizedUppercase
                                    )
                                    .tag(PublishProtocol.udp)

                                },
                                label: {}
                            )

                        },
                        onAdd: {
                            self.ports.append(.init())
                        },
                        onDelete: {
                            self.ports.removeAll(where: { $0.id == port.id })
                        }
                    )

                }
            )

        }

        KeyValuesEditView(
            keyValues: $environments,
            title: "Environment Variables"
        )

        VStack(alignment: .leading, spacing: 8) {

            HStack(alignment: .lastTextBaseline) {
                Text("Volumes")
                Text("Anonymous: /path or Named: <name>:/path")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(
                "⭑ If volume name is empty or not found, a new volume will be created."
            )
            .lineLimit(1)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if self.volumes.isEmpty {
                Button(
                    action: {
                        self.volumes.append(.init())
                    },
                    label: {
                        Text("Add Volume")
                            .padding(.horizontal, 2)
                    }
                )
                .buttonStyle(
                    CustomButtonStyle(
                        backgroundShape: .roundedRectangle(4),
                        backgroundColor: .blue
                    )
                )
            }

            ForEach(
                $volumes,
                content: { $volume in

                    AddableRow(
                        content: {
                            VolumeRow(
                                volumeName: $volume.name,
                                path: $volume.path,
                                showPickVolume: $showPickVolume,
                                availableVolumes: $availableVolumes,
                                showAvailableVolume: {
                                    guard !self.volumeInitialized else {
                                        self.showPickVolume = true
                                        return
                                    }
                                    Task {
                                        do {
                                            self.showProgressView = true
                                            self.availableVolumes =
                                                try await VolumeService
                                                .listVolumes()
                                            self.showProgressView = false
                                            self.volumeInitialized = true
                                            self.showPickVolume = true
                                        } catch (let error) {
                                            self.errorMessage = "\(error)"
                                        }
                                    }
                                }
                            )
                        },
                        onAdd: {
                            self.volumes.append(.init())
                        },
                        onDelete: {
                            self.volumes.removeAll(where: { $0.id == volume.id }
                            )
                        }
                    )
                }
            )

        }

        VStack(alignment: .leading, spacing: 8) {

            HStack(alignment: .lastTextBaseline) {
                Text("Networks")
                Text("Name of the network to attach")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(
                "⭑ If empty, the container will be attached to the default network."
            )
            .lineLimit(1)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if self.networks.isEmpty {
                Button(
                    action: {
                        self.networks.append(.init())
                    },
                    label: {
                        Text("Add Network")
                            .padding(.horizontal, 2)
                    }
                )
                .buttonStyle(
                    CustomButtonStyle(
                        backgroundShape: .roundedRectangle(4),
                        backgroundColor: .blue
                    )
                )
            }

            ForEach(
                $networks,
                content: { $network in

                    AddableRow(
                        content: {
                            NetworkRow(
                                networkName: $network.name,
                                showPickNetwork: $showPickNetwork,
                                availableNetworks: $availableNetworks,
                                showAvailableNetwork: {
                                    guard !self.networkInitialized else {
                                        self.showPickNetwork = true
                                        return
                                    }
                                    Task {
                                        do {
                                            self.showProgressView = true
                                            self.availableNetworks =
                                                try await NetworkService
                                                .listNetworks()
                                            self.showProgressView = false
                                            self.networkInitialized = true
                                            self.showPickNetwork = true
                                        } catch (let error) {
                                            self.errorMessage = "\(error)"
                                        }
                                    }
                                }
                            )
                        },
                        onAdd: {
                            self.networks.append(.init())
                        },
                        onDelete: {
                            self.networks.removeAll(where: {
                                $0.id == network.id
                            })
                        }
                    )
                }
            )

        }
    }
}

private struct NetworkRow: View {
    @Binding var networkName: String
    @Binding var showPickNetwork: Bool
    @Binding var availableNetworks: [NetworkResource]

    var showAvailableNetwork: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("Name")
                .frame(maxHeight: .infinity)

            TextField(text: $networkName, prompt: Text(""), label: {})
                .frame(maxHeight: .infinity)

            Button(
                action: {
                    self.showAvailableNetwork()
                },
                label: {
                    Image(systemName: "ellipsis")
                        .padding(.horizontal, 2)
                        .frame(maxHeight: .infinity)
                }
            )
            .buttonStyle(
                CustomButtonStyle(
                    backgroundShape: .roundedRectangle(4),
                    backgroundColor: .secondary
                )
            )

        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(
            isPresented: $showPickNetwork,
            content: {
                NetworkPickingView(
                    networks: self.availableNetworks,
                    onNetworkSelect: {
                        self.networkName = $0
                    }
                )
            }
        )

    }
}

private struct VolumeRow: View {
    @Binding var volumeName: String
    @Binding var path: String
    @Binding var showPickVolume: Bool
    @Binding var availableVolumes: [VolumeConfiguration]

    var showAvailableVolume: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 16) {
                Text("Name")
                    .frame(maxHeight: .infinity)

                TextField(text: $volumeName, prompt: Text(""), label: {})
                    .frame(maxHeight: .infinity)

                Button(
                    action: {
                        self.showAvailableVolume()
                    },
                    label: {
                        Image(systemName: "ellipsis")
                            .padding(.horizontal, 2)
                            .frame(maxHeight: .infinity)
                    }
                )
                .buttonStyle(
                    CustomButtonStyle(
                        backgroundShape: .roundedRectangle(4),
                        backgroundColor: .secondary
                    )
                )

            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity)

            HStack(spacing: 16) {
                Text("Path")
                    .frame(maxHeight: .infinity)

                TextField(text: $path, prompt: Text("Ex: /data"), label: {})
                    .frame(maxHeight: .infinity)

            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(
            isPresented: $showPickVolume,
            content: {
                VolumePickingView(
                    volumes: self.availableVolumes,
                    onVolumeSelect: {
                        self.volumeName = $0
                    }
                )
            }
        )

    }
}

//
//  NetworkListView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import ContainerResource
import SwiftUI

struct NetworkListView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager

    @State private var searchText: String = ""

    @State private var networks: [NetworkDisplayModel] = []
    @State private var lastUpdated: Date? = nil

    @State private var selections = Set<NetworkDisplayModel.ID>()

    @State private var showLabelForNetwork: NetworkDisplayModel?
    @State private var showOptionForNetwork: NetworkDisplayModel?

    @State private var showInUseContainerForNetwork: NetworkDisplayModel?

    @State private var showCreateNetworkView: Bool = false

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredNetworks: [NetworkDisplayModel] {
        if trimmedText.isEmpty {
            return networks
        }
        let filtered = self.networks.filter({
            $0.name.contains(trimmedText)
        })

        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .lastTextBaseline) {
                HStack {
                    Text("Networks")
                        .font(.title2)
                        .fontWeight(.bold)

                    Button(
                        action: {
                            showCreateNetworkView = true
                        },
                        label: {
                            Image(systemName: "plus")
                                .font(.subheadline)
                        }
                    )
                    .buttonStyle(
                        CustomButtonStyle(
                            backgroundShape: .circle,
                            backgroundColor: .blue
                        )
                    )

                }

                Spacer()

                if let lastUpdated {
                    HStack {
                        Text(
                            String(
                                "Last updated \(lastUpdated.formatted(date: .omitted, time: .standard))"
                            )
                        )

                        Button(
                            action: {
                                Task {
                                    await self.listNetworks()
                                }
                            },
                            label: {
                                Image(
                                    systemName:
                                        "arrow.trianglehead.clockwise.rotate.90"
                                )
                            }
                        )
                    }

                }
            }

            HStack(spacing: 36) {
                SearchBox(text: $searchText)
                    .frame(width: 280)

                Spacer()

                if !selections.isEmpty {
                    let selectedNetworks = self.networks.filter({
                        self.selections.contains($0.id)
                    })
                    let allDeletable = !selectedNetworks.contains(where: {
                        $0.inUse || $0.isBuiltin
                    })

                    Button(
                        action: {
                            Task {
                                self.applicationManager.showProgressView =
                                    selectedNetworks.count > 1
                                do {
                                    try await NetworkService.deleteNetworks(
                                        selectedNetworks.map(\.network),
                                        messageStreamContinuation:
                                            applicationManager
                                            .messageStreamContinuation
                                    )
                                    await self.listNetworks()
                                    self.applicationManager.showProgressView =
                                        false
                                } catch (let error) {
                                    applicationManager.error = error
                                }
                            }
                        },
                        label: {
                            Text("Delete")
                                .padding(.horizontal, 2)
                        }
                    )
                    .disabled(!allDeletable)
                    .buttonStyle(
                        CustomButtonStyle(
                            backgroundShape: .roundedRectangle(4),
                            backgroundColor: .red,
                            disabled: !allDeletable
                        )
                    )

                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Table(
                of: NetworkDisplayModel.self,
                selection: $selections,
                columns: {

                    TableColumn(TableHelper.columnHeader("Name")) { network in
                        Text(network.name)
                            .font(.headline)
                            .lineLimit(1)
                            .frame(height: 48)
                    }
                    .width(min: 80, ideal: 80)

                    TableColumn(TableHelper.columnHeader("Mode")) { network in
                        Text(network.mode.rawValue)
                    }
                    .width(80)

                    TableColumn(TableHelper.columnHeader("State")) { network in
                        Group {
                            if network.inUse {
                                Button(
                                    action: {
                                        showInUseContainerForNetwork = network
                                    },
                                    label: {
                                        Text("In use")
                                            .lineLimit(1)
                                            .underline()

                                    }
                                )
                                .buttonStyle(.link)
                            } else {
                                Text("Unused")
                            }
                        }
                        .lineLimit(1)

                    }
                    .width(64)

                    TableColumn(TableHelper.columnHeader("IPv4 Subnet")) {
                        network in
                        Text(network.ipv4Subnet)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 100, max: 160)

                    TableColumn(TableHelper.columnHeader("IPv4 Gateway")) {
                        network in
                        Text(network.ipv4Gateway)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 100, max: 160)

                    TableColumn(TableHelper.columnHeader("IPv6 Subnet")) {
                        network in
                        if let ipv6Subnet = network.ipv6Subnet {
                            Text(ipv6Subnet)
                                .lineLimit(1)
                        } else {
                            Text("(Not Specified)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 100, ideal: 100, max: 160)

                    TableColumn(TableHelper.columnHeader("Created")) {
                        network in
                        Text(network.created)
                    }
                    .width(min: 80, ideal: 80, max: 160)

                    TableColumn(TableHelper.columnHeader("Plugin")) {
                        network in
                        Text(network.plugin)
                            .lineLimit(1)
                    }
                    .width(min: 80, ideal: 120, max: 180)

                    TableColumn(TableHelper.columnHeader("Label & Option")) {
                        network in
                        let labels = network.labels
                        let options = network.options
                        VStack(alignment: .leading, spacing: 8) {
                            Button(
                                action: {
                                    self.showLabelForNetwork = network
                                },
                                label: {
                                    Text("- Labels")
                                }
                            )
                            .disabled(labels.isEmpty)
                            Button(
                                action: {
                                    self.showOptionForNetwork = network
                                },
                                label: {
                                    Text("- Options")
                                }
                            )
                            .disabled(options.isEmpty)
                        }
                        .buttonStyle(.link)
                    }
                    .width(120)

                    TableColumn(TableHelper.columnHeader("Actions")) {
                        network in

                        let deleteDisabled = network.inUse || network.isBuiltin
                        HStack(spacing: 12) {
                            Button(
                                action: {
                                    Task {
                                        self.applicationManager
                                            .showProgressView = true
                                        do {
                                            try await NetworkService
                                                .deleteNetworks(
                                                    [network.network],
                                                    messageStreamContinuation:
                                                        applicationManager
                                                        .messageStreamContinuation
                                                )
                                            await self.listNetworks()
                                            self.applicationManager
                                                .showProgressView = false
                                        } catch (let error) {
                                            applicationManager.error = error
                                        }
                                    }
                                },
                                label: {
                                    TableHelper.actionImage(
                                        systemName: "trash.fill"
                                    )
                                }
                            )
                            .disabled(deleteDisabled)
                            .buttonStyle(
                                CustomButtonStyle(
                                    backgroundShape: .circle,
                                    backgroundColor: .red,
                                    disabled: deleteDisabled
                                )
                            )
                        }
                        .padding(.horizontal, 8)
                    }
                    .width(80)

                },
                rows: {
                    ForEach(filteredNetworks)
                }
            )
            .alternatingRowBackgrounds(.disabled)
            .overlay(
                alignment: .center,
                content: {
                    if !self.applicationManager.isSystemRunning {
                        SystemStoppedView()
                    } else if filteredNetworks.isEmpty {
                        ContentUnavailableView(
                            trimmedText.isEmpty
                                ? "No Networks Found" : "No Matching Networks",
                            systemImage: "network"
                        )
                    }
                }
            )

        }
        .onChange(
            of: self.applicationManager.isSystemRunning,
            initial: true,
            {
                guard self.applicationManager.isSystemRunning else {
                    self.networks = []
                    self.lastUpdated = nil
                    return
                }
                Task {
                    guard self.lastUpdated == nil else {
                        return
                    }
                    await self.listNetworks()
                }
            }
        )
        .sheet(
            isPresented: $showCreateNetworkView,
            onDismiss: {
                Task {
                    await self.listNetworks()
                }
            },
            content: {
                CreateNetworkView()
            }
        )
        .sheet(
            item: $showInUseContainerForNetwork,
            onDismiss: {
                Task {
                    await self.listNetworks()
                }
            },
            content: { network in

                InUseContainersView(
                    containers: network.inUseContainers.map({
                        ContainerDisplayModel($0)
                    }),
                    updateContainer: { id in

                        let container = try await ContainerService.getContainer(
                            id
                        )
                        guard
                            let index = self.showInUseContainerForNetwork?
                                .inUseContainers.firstIndex(where: {
                                    $0.id == id
                                })
                        else {
                            return
                        }
                        self.showInUseContainerForNetwork?.inUseContainers[
                            index
                        ] = container

                    },
                    deleteContainer: { id in
                        self.showInUseContainerForNetwork?.inUseContainers
                            .removeAll(where: { $0.id == id })
                    }
                )
            }
        )
        .sheet(
            item: $showLabelForNetwork,
            content: { network in
                NetworkDetailOptionView(
                    dictionary: network.labels,
                    title: "Metadata",
                    emptyText: "No Metadata Specified."
                )
            }
        )
        .sheet(
            item: $showOptionForNetwork,
            content: { network in
                NetworkDetailOptionView(
                    dictionary: network.options,
                    title: "Network Options",
                    emptyText: "No Options Specified."
                )
            }
        )

    }

    private func listNetworks() async {
        do {
            let containers = try await ContainerService.listContainers()
            let networks = try await NetworkService.listNetworks()
            let displayModels: [NetworkDisplayModel] = networks.map({
                NetworkDisplayModel($0, containers: containers)
            })

            self.networks = displayModels
            self.lastUpdated = Date()

        } catch (let error) {
            applicationManager.error = error
        }
    }

}

private struct NetworkDetailOptionView: View {
    var dictionary: [String: String]
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

            KeyValuesDisplayView(
                keyValues: keyValueModels,
                emptyText: emptyText,
                leftColumnWidth: 120
            )

        }
        .padding(.all, 24)
        .frame(width: 320, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(
            alignment: .topTrailing,
            content: {
                Button(
                    action: {
                        self.dismiss()
                    },
                    label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                    }
                )
                .buttonStyle(
                    CustomButtonStyle(
                        backgroundShape: .circle,
                        backgroundColor: .secondary
                    )
                )
                .padding(.all, 24)
            }
        )
        .interactiveDismissDisabled(false)

    }

}

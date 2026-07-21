//
//  InUseContainersView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import ContainerResource
import ContainerizationError
import SwiftUI

struct InUseContainersView: View {
    var containers: [ContainerDisplayModel]
    var updateContainer: (ContainerSnapshotID) async throws -> Void
    var deleteContainer: (ContainerSnapshotID) -> Void

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var showProgressView: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(DisplayCategory.container.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                if let errorMessage = self.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }

            InUseContainersTable(
                containers: containers,
                updateContainer: updateContainer,
                deleteContainer: deleteContainer,
                showProgressView: $showProgressView,
                errorMessage: $errorMessage
            )

            Button(
                action: {
                    self.dismiss()
                },
                label: {
                    Text("Close")
                        .padding(.horizontal, 2)
                }
            )
            .buttonStyle(
                CustomButtonStyle(
                    backgroundShape: .roundedRectangle(4),
                    backgroundColor: .secondary
                )
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

        }
        .padding(.all, 24)
        .frame(width: 560, height: 440)
        .interactiveDismissDisabled()
        .sheet(
            isPresented: $showProgressView,
            content: {
                CustomProgressView()
                    .environment(self.applicationManager)
            }
        )
        .onDisappear {
            self.showProgressView = false
        }
    }
}

struct InUseContainersTable: View {
    var containers: [ContainerDisplayModel]
    var updateContainer: (ContainerSnapshotID) async throws -> Void
    var deleteContainer: (ContainerSnapshotID) -> Void
    var showComposeLink: Bool = true

    @Binding var showProgressView: Bool
    @Binding var errorMessage: String?

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Table(
            of: ContainerDisplayModel.self,
            columns: {
                TableColumn(TableHelper.columnHeader("Name")) { container in
                    Button(
                        action: {
                            self.dismiss()
                            applicationManager.selectedContainerID =
                                container.id
                        },
                        label: {
                            Text(container.name)
                                .font(.headline)
                                .lineLimit(1)
                                .underline()

                        }
                    )
                    .buttonStyle(.link)
                    .frame(height: 48)  // to set minimum row height
                }
                .width(min: 80, ideal: 80)

                TableColumn(TableHelper.columnHeader("State")) {
                    container in
                    Text(container.state)
                }
                .width(64)

                TableColumn(TableHelper.columnHeader("Actions")) {
                    container in

                    let compose = ComposeService.runningByCompose(
                        containerName: container.name
                    )
                    HStack(spacing: 12) {
                        if let compose, showComposeLink {
                            Button(
                                action: {
                                    self.dismiss()
                                    applicationManager.pendingComposeAction =
                                        .init(
                                            compose: compose,
                                            actionCategory: .inspect
                                        )
                                },
                                label: {
                                    Text("Compose resource")
                                }
                            )
                            .buttonStyle(.link)
                        } else {
                            self.actionView(container)
                                .disabled(compose != nil)
                                .opacity(compose != nil ? 0.5 : 1.0)
                        }
                    }
                    .padding(.horizontal, 8)

                }
                .width(92)

            },
            rows: {
                ForEach(containers.sorted(by: { $0.name > $1.name }))
            }
        )
        .alternatingRowBackgrounds(.disabled)
        .overlay(
            alignment: .center,
            content: {
                if containers.isEmpty {
                    ContentUnavailableView(
                        "No Containers",
                        systemImage: DisplayCategory.image.icon
                    )
                }
            }
        )
    }

    @ContentBuilder
    private func actionView(_ container: ContainerDisplayModel) -> some View {
        switch container.status {
        case .running:
            Button(
                action: {
                    Task {
                        self.errorMessage = nil
                        self.showProgressView = true
                        defer {
                            self.showProgressView = false
                        }

                        do {
                            try await ContainerService
                                .stopContainers(
                                    [
                                        container.id
                                    ],
                                    stopTimeoutSeconds:
                                        userSettingsManager
                                        .stopContainerTimeoutSeconds,
                                    messageStreamContinuation:
                                        applicationManager
                                        .messageStreamContinuation
                                )
                            try await self.updateContainer(
                                container.id
                            )

                        } catch (let error) {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                },
                label: {
                    TableHelper.actionImage(
                        systemName: "stop.fill"
                    )
                }
            )
            .buttonStyle(
                CustomButtonStyle(
                    backgroundShape: .circle,
                    backgroundColor: .gray
                )
            )

        case .stopped:
            Button(
                action: {
                    Task {
                        self.errorMessage = nil
                        self.showProgressView = true
                        defer {
                            self.showProgressView = false
                        }

                        do {
                            let container =
                                try await ContainerService
                                .getContainer(
                                    container.id
                                )
                            try await ContainerService
                                .startContainer(
                                    container,
                                    attachContainerStdout:
                                        false,
                                    attachContainerStdIn:
                                        false,
                                    messageStreamContinuation:
                                        applicationManager
                                        .messageStreamContinuation
                                )

                            try await self.updateContainer(
                                container.id
                            )

                        } catch {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                },
                label: {
                    TableHelper.actionImage(
                        systemName: "play.fill"
                    )
                }
            )
            .buttonStyle(
                CustomButtonStyle(
                    backgroundShape: .circle,
                    backgroundColor: .blue
                )
            )

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

        Button(
            action: {
                Task {
                    self.errorMessage = nil
                    self.showProgressView = true
                    defer {
                        self.showProgressView = false
                    }

                    do {
                        try await ContainerService
                            .deleteContainers(
                                [container.id],
                                force: true,
                                messageStreamContinuation:
                                    applicationManager
                                    .messageStreamContinuation
                            )
                        self.deleteContainer(container.id)
                    } catch (let error) {
                        self.errorMessage = error.localizedDescription
                    }
                }
            },
            label: {
                TableHelper.actionImage(
                    systemName: "trash.fill"
                )
            }
        )
        .buttonStyle(
            CustomButtonStyle(
                backgroundShape: .circle,
                backgroundColor: .red
            )
        )

    }
}

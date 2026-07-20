//
//  ComposeListView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import ContainerResource
import SwiftUI

// TODO: handle application manager selected resource id change

private struct ShowContainerViewParameter: Identifiable {
    var id: String {
        "\(compose.name)_\(serviceName)"
    }
    var compose: ComposeResource
    var serviceName: String

    var containerIds: [ContainerSnapshotID] {
        compose.runningContainers[serviceName] ?? []
    }
}

struct ComposeListView: View {
    @Environment(ApplicationManager.self) private var applicationManager

    @State private var searchText: String = ""

    @State private var composes: [ComposeResource] = []
    @State private var lastUpdated: Date? = nil

    @State private var selections = Set<ComposeResource.ID>()

    @State private var showEditComposeResourceView: ComposeResource? = nil
    @State private var showAddComposeResourceView: Bool = false
    @State private var showComposeActionView: ComposeAction?

    @State private var showContainersForService: ShowContainerViewParameter?

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredComposes: [ComposeResource] {
        if trimmedText.isEmpty {
            return composes
        }
        let filtered = self.composes.filter({
            $0.name.localizedCaseInsensitiveContains(trimmedText)
        })

        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            HStack(alignment: .lastTextBaseline) {
                HStack {
                    Text("Composes")
                        .font(.title2)
                        .fontWeight(.bold)

                    Button(
                        action: {
                            showAddComposeResourceView = true
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
                                self.listComposes(refreshContainerStatus: true)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Table(
                of: ComposeResource.self,
                selection: $selections,
                columns: {
                    TableColumn(TableHelper.columnHeader("Name")) { compose in

                        HStack {
                            Text(compose.name)
                                .font(.headline)
                                .lineLimit(1)
                                .frame(height: 48)
                            if let error = compose.parsingError {
                                Image(systemName: "exclamationmark.circle")
                                    .fontWeight(.medium)
                                    .foregroundStyle(.red)
                                    .contentShape(.circle)
                                    .toolTip {
                                        Text(error.localizedCapitalized)
                                            .font(.subheadline)
                                            .foregroundStyle(.red)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize()
                                            .padding(.all, 4)
                                            .background(
                                                RoundedRectangle(
                                                    cornerRadius: 4
                                                ).fill(.background)
                                            )
                                            .offset(x: 120)
                                            .offset(y: -20)
                                            .zIndex(.greatestFiniteMagnitude)
                                    }
                            }
                        }
                    }
                    .width(min: 80, ideal: 80)

                    TableColumn(TableHelper.columnHeader("Base Compose")) {
                        compose in
                        HStack {
                            Text(compose.baseCompose.absolutePath)
                                .lineLimit(1)
                                .truncationMode(.head)

                            Button {
                                self.openFile(compose.baseCompose)
                            } label: {
                                Image(systemName: "arrow.right")
                                    .contentShape(Rectangle())
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .width(min: 160, ideal: 160, max: 240)

                    TableColumn(TableHelper.columnHeader("Project Directory")) {
                        compose in
                        HStack {
                            if let directory = compose.projectDirectory {
                                Text(directory.absolutePath)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            } else {
                                Text("Default (`.`)")
                            }

                            Button {
                                self.openDirectory(
                                    compose.projectDirectory
                                        ?? compose.baseCompose.parentDirectory
                                )
                            } label: {
                                Image(systemName: "arrow.right")
                                    .contentShape(Rectangle())
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .width(min: 160, ideal: 160, max: 240)

                    TableColumn(
                        TableHelper.columnHeader("Additional Compose")
                    ) { compose in
                        if compose.additionalComposes.isEmpty {
                            Text("None")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(
                                compose.additionalComposes.map(\.absolutePath)
                                    .joined(separator: "\n")
                            )
                            .lineLimit(nil)
                            .truncationMode(.head)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .width(min: 160, ideal: 160, max: 240)

                    TableColumn(
                        TableHelper.columnHeader("Env Files")
                    ) { compose in
                        if compose.additionalComposes.isEmpty {
                            Text("Default (`.env`)")
                        } else {
                            Text(
                                compose.additionalComposes.map(\.absolutePath)
                                    .joined(separator: "\n")
                            )
                            .lineLimit(nil)
                            .truncationMode(.head)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .width(min: 160, ideal: 160, max: 240)

                    TableColumn(TableHelper.columnHeader("Running Services")) {
                        compose in

                        if compose.runningContainers.isEmpty {
                            Text("None")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(
                                    Array(
                                        compose.runningContainers.keys.sorted()
                                    ),
                                    id: \.self
                                ) { serviceName in
                                    let count =
                                        compose.runningContainers[serviceName]?
                                        .count ?? 0
                                    if count > 0 {
                                        Button(
                                            action: {
                                                self.showContainersForService =
                                                    .init(
                                                        compose: compose,
                                                        serviceName: serviceName
                                                    )
                                            },
                                            label: {
                                                Text(
                                                    "- \(serviceName)\(count <= 1 ? "" : " ( x\(count) )")"
                                                )
                                            }
                                        )
                                    }

                                }
                            }
                            .buttonStyle(.link)
                        }

                    }
                    .width(min: 120, ideal: 120, max: 160)

                    TableColumn(TableHelper.columnHeader("Actions")) {
                        compose in

                        HStack(spacing: 12) {
                            Button(
                                action: {
                                    showComposeActionView = .init(
                                        compose: compose,
                                        actionCategory: .up
                                    )
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

                            Button(
                                action: {
                                    showComposeActionView = .init(
                                        compose: compose,
                                        actionCategory: .down
                                    )
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

                            Divider()
                                .padding(.vertical, 12)

                            Button(
                                action: {
                                    showEditComposeResourceView = compose
                                },
                                label: {
                                    TableHelper.actionImage(
                                        systemName: "pencil"
                                    )
                                    .fontWeight(.heavy)
                                }
                            )
                            .buttonStyle(
                                CustomButtonStyle(
                                    backgroundShape: .circle,
                                    backgroundColor: .gray
                                )
                            )

                            Button(
                                action: {
                                    Task {
                                        self.applicationManager
                                            .showProgressView = true

                                        do {
                                            try await ComposeService
                                                .removeComposeResources(
                                                    composes: [compose],
                                                    messageStreamContinuation:
                                                        applicationManager
                                                        .messageStreamContinuation
                                                )
                                            self.listComposes(
                                                refreshContainerStatus: false
                                            )
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
                            .buttonStyle(
                                CustomButtonStyle(
                                    backgroundShape: .circle,
                                    backgroundColor: .red
                                )
                            )

                        }
                        .padding(.horizontal, 8)
                    }
                    .width(160)

                },
                rows: {
                    ForEach(filteredComposes)
                }
            )
            .alternatingRowBackgrounds(.disabled)
            .overlay(
                alignment: .center,
                content: {
                    if !self.applicationManager.isSystemRunning {
                        SystemStoppedView()
                    } else if filteredComposes.isEmpty {
                        ContentUnavailableView(
                            trimmedText.isEmpty
                                ? "No Composes Found" : "No Matching Composes",
                            systemImage: "square.stack.3d.up.fill"
                        )
                    }
                }
            )
        }
        .onChange(
            of: self.applicationManager.pendingComposeAction,
            initial: true
        ) {
            guard let action = self.applicationManager.pendingComposeAction
            else {
                return
            }

            switch action.actionCategory {
            case .up, .down:
                self.showComposeActionView = action
            case .inspect:
                self.searchText = action.compose.name
            }

            self.applicationManager.pendingComposeAction = nil
        }
        .sheet(
            item: $showContainersForService,
            onDismiss: {
                self.showContainersForService = nil
                self.listComposes(refreshContainerStatus: false)
            },
            content: { param in
                ServiceContainersView(
                    serviceName: param.serviceName,
                    containerIDs: param.containerIds,
                    downService: {
                        try await self.handleAction(
                            param.compose,
                            service: param.serviceName,
                            action: .down
                        )
                    },
                    removeService: {
                        try await self.handleAction(
                            param.compose,
                            service: param.serviceName,
                            action: .remove
                        )
                    }
                )
            }
        )
        .sheet(
            isPresented: $showAddComposeResourceView,
            onDismiss: {
                self.listComposes(refreshContainerStatus: false)
            },
            content: {
                EditComposeResourceView()
            }
        )
        .sheet(
            item: $showEditComposeResourceView,
            onDismiss: {
                self.listComposes(refreshContainerStatus: false)
            },
            content: { resource in
                EditComposeResourceView(composeResource: resource)
            }
        )
        .sheet(
            item: $showComposeActionView,
            onDismiss: {
                self.listComposes(refreshContainerStatus: false)
            },
            content: { action in
                ComposeActionView(
                    action: action
                )
            }
        )
        .onChange(
            of: self.applicationManager.isSystemRunning,
            initial: true,
            {
                guard self.applicationManager.isSystemRunning else {
                    self.composes = []
                    self.lastUpdated = nil
                    return
                }

                Task {
                    guard self.lastUpdated == nil else {
                        return
                    }
                    self.listComposes(refreshContainerStatus: true)
                }
            }
        )
    }

    private func listComposes(refreshContainerStatus: Bool) {
        self.composes = (ComposeService.listComposeResources()).sorted(by: {
            $0.name > $1.name
        })

        self.lastUpdated = Date()
        if refreshContainerStatus {
            for compose in composes {
                compose.refreshServiceStatus(onRunningChanged: {
                    Task { @MainActor in
                        if let index = self.composes.firstIndex(where: {
                            $0.name == compose.name
                        }) {
                            // has to remove the row entirely to force view update
                            self.composes.remove(at: index)
                            try? await Task.sleep(for: .milliseconds(10))
                            self.composes.insert(compose, at: index)
                        }
                    }
                })
            }
        }
    }

    private func openFile(_ url: URL) {
        let _ = NSWorkspace.shared.selectFile(
            url.absolutePath,
            inFileViewerRootedAtPath: url.parentDirectory.absolutePath
        )
    }

    private func openDirectory(_ url: URL) {
        let _ = NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: url.absolutePath
        )
    }

    private func handleAction(
        _ compose: ComposeResource,
        service: String,
        action: ComposeSubactionType
    ) async throws {
        switch action {
        case .up:
            return
        case .build:
            return
        case .down:
            try await self.downCompose(compose, service: service)
        case .remove:
            try await self.removeCompose(
                compose,
                service: service
            )
        }
        try ComposeService.saveComposeResources([compose])
    }

    private func downCompose(_ compose: ComposeResource, service: String)
        async throws
    {
        let removedServices = try await ComposeService.downCompose(
            compose.baseCompose,
            additionalComposes: compose.additionalComposes,
            // envs for parsing vars in the compose files
            envFiles: compose.envFiles,
            projectDirectory: compose.projectDirectory,
            nameOverride: compose.nameOverride,
            // Services to build (builds all if omitted)
            // Explicitly targeting a service by name is an absolute override.
            // and always bypasses profile restrictions
            requestedServices: [service],
            // Specify a profile to enable. Can be repeated.
            // Services without a 'profiles' key are always enabled;
            // profiled services are enabled only when one of their profiles is active.
            requestedProfiles: [],
            startedContainers: compose.runningContainers,
            messageStreamContinuation: applicationManager
                .messageStreamContinuation
        )

        compose.onDown(downedServices: removedServices)
        return
    }

    private func removeCompose(_ compose: ComposeResource, service: String)
        async throws
    {
        let removedServices = try await ComposeService.removeCompose(
            compose.baseCompose,
            additionalComposes: compose.additionalComposes,
            // envs for parsing vars in the compose files
            envFiles: compose.envFiles,
            projectDirectory: compose.projectDirectory,
            nameOverride: compose.nameOverride,
            // Services to build (builds all if omitted)
            // Explicitly targeting a service by name is an absolute override.
            // and always bypasses profile restrictions
            requestedServices: [service],
            // Specify a profile to enable. Can be repeated.
            // Services without a 'profiles' key are always enabled;
            // profiled services are enabled only when one of their profiles is active.
            requestedProfiles: [],
            startedContainers: compose.runningContainers,
            messageStreamContinuation: applicationManager
                .messageStreamContinuation
        )
        compose.onRemove(removedServices: removedServices)
        return
    }
}

private struct ServiceContainersView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager
    @Environment(\.dismiss) private var dismiss

    var serviceName: String
    var containerIDs: [ContainerSnapshotID]
    @State private var containers: [ContainerSnapshot] = []

    var downService: () async throws -> Void
    var removeService: () async throws -> Void

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
                containers: containers.map({ ContainerDisplayModel($0) }),
                // all actions will be disabled since the containers are used in compose
                // therefore, no need to handle anything here.
                updateContainer: { _ in },
                deleteContainer: { _ in },
                showComposeLink: false,
                showProgressView: $showProgressView,
                errorMessage: $errorMessage
            )

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
                        Task {
                            self.showProgressView = true
                            self.errorMessage = nil
                            defer {
                                self.showProgressView = false
                            }
                            do {
                                try await self.downService()
                                self.dismiss()
                            } catch {
                                self.errorMessage = error.localizedDescription
                            }
                        }
                    },
                    label: {
                        Text("\(ComposeSubactionType.down.actionTitle) Service")
                            .padding(.horizontal, 2)
                    }
                )
                .buttonStyle(
                    CustomButtonStyle(
                        backgroundShape: .roundedRectangle(4),
                        backgroundColor: .blue
                    )
                )

                Button(
                    action: {
                        Task {
                            self.showProgressView = true
                            self.errorMessage = nil
                            defer {
                                self.showProgressView = false
                            }
                            do {
                                try await self.removeService()
                                self.dismiss()
                            } catch {
                                self.errorMessage = error.localizedDescription
                            }
                        }
                    },
                    label: {
                        Text(
                            "\(ComposeSubactionType.remove.actionTitle) Service"
                        )
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
        .task {
            await listContainers()
        }
    }

    private func listContainers() async {
        self.showProgressView = true
        defer {
            self.showProgressView = false
        }
        do {
            self.containers = (try await ContainerService.listContainers())
                .filter({ self.containerIDs.contains($0.id) })
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

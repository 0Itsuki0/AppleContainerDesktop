//
//  ComposeActionView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import ContainerResource
import SwiftUI

struct ComposeAction: Hashable, Equatable, Identifiable {
    var compose: ComposeResource
    var actionCategory: ComposeActionCategory

    var id: String {
        "\(compose.name)_\(actionCategory.rawValue)"
    }
}

enum ComposeActionCategory: String {
    case up
    case down
    case inspect

    var actionTypes: [ComposeSubactionType] {
        switch self {
        case .up:
            [.build, .up]
        case .down:
            [.down, .remove]
        case .inspect:
            []
        }
    }

    var title: String {
        switch self {
        case .up:
            "Compose Up"
        case .down:
            "Compose Down"
        case .inspect:
            "Compose"
        }
    }

}

enum ComposeSubactionType: String, Identifiable {
    case up
    case build

    case down
    case remove

    var id: String {
        self.rawValue
    }

    var actionTitle: String {
        switch self {
        case .up:
            "Up"
        case .down:
            "Down"
        case .build:
            "Build Only"
        case .remove:
            "Down & Remove"
        }
    }
}

struct ComposeActionView: View {
    init(action: ComposeAction) {
        self.compose = action.compose
        self.category = action.actionCategory
    }

    @State private var compose: ComposeResource
    private var category: ComposeActionCategory

    private var allServices: [String] {
        compose.parsedCompose?.allServiceNames ?? []
    }
    private var allProfiles: [String] {
        compose.parsedCompose?.allProfiles ?? []
    }

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var errorMessage: String?

    // use a different one then applicationManager.showProgressView to show the progress view over this sheet
    @SwiftUI.State private var showProgressView: Bool = false

    // Services to build (builds all if omitted)
    // Explicitly targeting a service by name is an absolute override.
    // and always bypasses profile restrictions
    @SwiftUI.State private var requestedServices: [String] = []
    // Specify a profile to enable. Can be repeated.
    // Services without a 'profiles' key are always enabled;
    // profiled services are enabled only when one of their profiles is active.
    @SwiftUI.State private var requestedProfiles: [String] = []

    // only effect image
    @SwiftUI.State private var forceRebuild: Bool = false
    // effect volume and network
    @SwiftUI.State private var forceRecreate: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(self.category.title)
                            .font(.headline)

                        if compose.parsingError != nil {
                            Button(
                                action: {
                                    self.compose.parseCompose()
                                },
                                label: {
                                    Image(
                                        systemName:
                                            "arrow.trianglehead.clockwise.rotate.90"
                                    )
                                    .font(.subheadline)
                                    .contentShape(.circle)
                                }
                            )
                            .buttonStyle(.link)
                        }
                    }

                    if let errorMessage = self.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                self.stringListSection(
                    title: "Services",
                    subtitle:
                        """
                        ⭑ If empty, all services will be included.
                        ⭑ Explicitly targeting a service by name always bypasses profile restrictions.
                        ⭑ \(self.category == .down ? "Services that depend on the selected ones will also be included." : "Services that the selected ones depend on will also be included.")
                        """,
                    values: $requestedServices,
                    allValues: self.allServices
                )

                Divider()

                self.stringListSection(
                    title: "Profiles",
                    subtitle:
                        """
                        ⭑ Services without a `profiles` key are always enabled. 
                        ⭑ Profiled services are enabled only when one of their profiles is active. 
                        ⭑ \(self.category == .down ? "Services that depend on the selected ones will also be included." : "Services that the selected ones depend on will also be included.")
                        """,
                    values: $requestedProfiles,
                    allValues: self.allProfiles
                )

                Divider()

                if category == .up {
                    Toggle(
                        isOn: $forceRebuild,
                        label: {
                            Text("Force rebuild (image only)")
                        }
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        isOn: $forceRecreate,
                        label: {
                            Text("Force recreate (volume and network)")
                        }
                    )
                    .toggleStyle(.checkbox)

                    Divider()
                }

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

                    ForEach(self.category.actionTypes) { type in
                        Button(
                            action: {
                                self.handleAction(type)
                            },
                            label: {
                                Text(type.actionTitle)
                                    .padding(.horizontal, 2)
                            }
                        )
                        .buttonStyle(
                            CustomButtonStyle(
                                backgroundShape: .roundedRectangle(4),
                                backgroundColor: .blue
                            )
                        )
                        .disabled(self.compose.parsingError != nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

            }
            .multilineTextAlignment(.leading)
            .padding(.all, 24)
            .scrollTargetLayout()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: false)
        .frame(maxHeight: 440)
        .onChange(of: self.compose.parsingError, initial: true) {
            if let parsingError = self.compose.parsingError {
                self.errorMessage = parsingError
            } else {
                self.errorMessage = nil
            }
        }
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
        .interactiveDismissDisabled()

    }

    private func stringListSection(
        title: String,
        subtitle: String? = nil,
        values: Binding<[String]>,
        allValues: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineHeight(.loose)
            }

            if allValues.isEmpty {
                Text("( No \(title) found )")
                    .foregroundStyle(.secondary)
            }

            ForEach(allValues, id: \.self) { value in
                Toggle(
                    isOn: .init(
                        get: {
                            values.wrappedValue.contains(value)
                        },
                        set: { isOn in
                            if isOn {
                                values.wrappedValue.append(value)
                            } else {
                                values.wrappedValue.removeAll(where: {
                                    $0 == value
                                })
                            }
                        }
                    ),
                    label: {
                        Text(value)
                    }
                )
                .toggleStyle(.checkbox)
            }
        }
    }

    private func handleAction(_ type: ComposeSubactionType) {
        Task {
            self.showProgressView = true
            defer {
                self.showProgressView = false
            }
            do {
                switch type {
                case .up:
                    try await self.upCompose()
                case .build:
                    try await self.buildCompose()
                case .down:
                    try await self.downCompose()
                case .remove:
                    try await self.removeCompose()
                }
                try ComposeService.saveComposeResources([self.compose])
                self.dismiss()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func upCompose() async throws {
        let startedContainers = try await ComposeService.upCompose(
            compose.baseCompose,
            additionalComposes: compose.additionalComposes,
            // envs for parsing vars in the compose files
            envFiles: compose.envFiles,
            projectDirectory: compose.projectDirectory,
            nameOverride: compose.nameOverride,
            // Services to build (builds all if omitted)
            // Explicitly targeting a service by name is an absolute override.
            // and always bypasses profile restrictions
            requestedServices: requestedServices,
            // Specify a profile to enable. Can be repeated.
            // Services without a 'profiles' key are always enabled;
            // profiled services are enabled only when one of their profiles is active.
            requestedProfiles: requestedProfiles,
            // only effect image
            forceRebuild: forceRebuild,
            // effect volume and network
            forceRecreate: forceRecreate,
            messageStreamContinuation: applicationManager
                .messageStreamContinuation
        )
        self.compose.onUp(
            newContainers: startedContainers.mapValues({ $0.map(\.id) })
        )
    }

    private func buildCompose() async throws {
        try await ComposeService.buildCompose(
            compose.baseCompose,
            additionalComposes: compose.additionalComposes,
            // envs for parsing vars in the compose files
            envFiles: compose.envFiles,
            projectDirectory: compose.projectDirectory,
            nameOverride: compose.nameOverride,
            // Services to build (builds all if omitted)
            // Explicitly targeting a service by name is an absolute override.
            // and always bypasses profile restrictions
            requestedServices: requestedServices,
            // Specify a profile to enable. Can be repeated.
            // Services without a 'profiles' key are always enabled;
            // profiled services are enabled only when one of their profiles is active.
            requestedProfiles: requestedProfiles,
            // only effect image
            shouldRebuild: forceRebuild,
            messageStreamContinuation: applicationManager
                .messageStreamContinuation
        )
    }

    private func downCompose() async throws {
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
            requestedServices: requestedServices,
            // Specify a profile to enable. Can be repeated.
            // Services without a 'profiles' key are always enabled;
            // profiled services are enabled only when one of their profiles is active.
            requestedProfiles: requestedProfiles,
            startedContainers: self.compose.runningContainers,
            messageStreamContinuation: applicationManager
                .messageStreamContinuation
        )

        compose.onDown(downedServices: removedServices)
    }

    private func removeCompose() async throws {
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
            requestedServices: requestedServices,
            // Specify a profile to enable. Can be repeated.
            // Services without a 'profiles' key are always enabled;
            // profiled services are enabled only when one of their profiles is active.
            requestedProfiles: requestedProfiles,
            startedContainers: self.compose.runningContainers,
            messageStreamContinuation: applicationManager
                .messageStreamContinuation
        )
        compose.onRemove(removedServices: removedServices)
    }
}

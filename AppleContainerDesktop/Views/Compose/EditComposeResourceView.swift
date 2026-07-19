//
//  EditComposeResourceView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import SwiftUI
import UniformTypeIdentifiers

struct EditComposeResourceView: View {

    init(composeResource: ComposeResource) {
        self.isNew = false
        self.existingCompose = composeResource
    }

    init() {
        self.isNew = true
        self.existingCompose = nil
    }

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool
    private var existingCompose: ComposeResource?

    @SwiftUI.State private var errorMessage: String?

    @SwiftUI.State private var showAdditionalSettings: Bool = false

    @SwiftUI.State private var baseCompose: URL?
    @SwiftUI.State private var additionalComposes: [URL] = []
    // envs for parsing vars in the compose files
    @SwiftUI.State private var envFiles: [URL] = []
    @SwiftUI.State private var projectDirectory: URL?
    @SwiftUI.State private var nameOverride: String = ""

    @SwiftUI.State private var conflictingName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isNew ? "Add Compose" : "Edit Compose")
                        .font(.headline)

                    if let errorMessage = self.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Base Compose File")
                    FileSelectView(
                        fileURL: $baseCompose,
                        errorMessage: $errorMessage,
                        allowedContentTypes: [.yaml]
                    )
                    .onChange(
                        of: baseCompose,
                        {
                            self.additionalComposes.removeAll(where: {
                                $0 == baseCompose
                            })
                        }
                    )
                }

                Divider()

                Button(
                    action: {
                        showAdditionalSettings.toggle()
                    },
                    label: {
                        HStack {
                            Text("Additional Settings")
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional Compose Files")
                        MultiFileSelectView(
                            fileURLs: $additionalComposes,
                            errorMessage: $errorMessage,
                            allowedContentTypes: [.yaml]
                        )
                        .onChange(of: additionalComposes) {
                            if let baseCompose,
                                additionalComposes.contains(baseCompose)
                            {
                                self.errorMessage =
                                    "\(baseCompose) is already used as the base compose."
                                additionalComposes.removeAll(where: {
                                    $0 == baseCompose
                                })
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment Files")
                        Text(
                            "⭑ If empty, `.env` will be used if exists in the project directory."
                        )
                        .lineLimit(1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        MultiFileSelectView(
                            fileURLs: $envFiles,
                            errorMessage: $errorMessage,
                            allowedContentTypes: [.text]
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Directory")
                        Text(
                            "⭑ If empty, the base compose file's directory will be used."
                        )
                        .lineLimit(1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        FileSelectView(
                            fileURL: $projectDirectory,
                            errorMessage: $errorMessage,
                            allowedContentTypes: [.directory]
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Name Override")

                        TextField(
                            text: $nameOverride,
                            prompt: Text("Ex: my-project"),
                            label: {}
                        )
                    }

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
                        action: { self.handleSave() },
                        label: {
                            Text("Save")
                                .padding(.horizontal, 2)
                        }
                    )
                    .buttonStyle(
                        CustomButtonStyle(
                            backgroundShape: .roundedRectangle(4),
                            backgroundColor: .blue
                        )
                    )
                    .disabled(self.baseCompose == nil)
                }

                .frame(maxWidth: .infinity, alignment: .trailing)

            }
            .multilineTextAlignment(.leading)
            .padding(.all, 24)
            .scrollTargetLayout()
        }
        .confirmationDialog(
            "Name Conflict",
            item: $conflictingName,
            actions: { name in
                // override (cancel action is provided by default)
                Button(
                    "Override",
                    action: {
                        self.handleSave(override: true)
                    }
                )
            },
            message: { name in
                Text("Compose with name '\(name)' already exists.")
            }
        )
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: !self.showAdditionalSettings)
        .frame(maxHeight: 440)
        .onChange(of: self.existingCompose, initial: true) {
            if let composeResource = existingCompose {
                self.baseCompose = composeResource.baseCompose
                self.additionalComposes = composeResource.additionalComposes
                self.envFiles = composeResource.envFiles
                self.projectDirectory = composeResource.projectDirectory
                self.nameOverride = composeResource.nameOverride ?? ""
            } else {
                self.baseCompose = nil
                self.additionalComposes = []
                self.envFiles = []
                self.projectDirectory = nil
                self.nameOverride = ""
            }
        }
        .animation(.default, value: self.additionalComposes.count)
        .animation(.default, value: self.envFiles.count)
        .interactiveDismissDisabled()
    }

    private func handleSave(override: Bool = false) {
        guard let baseCompose else {
            self.errorMessage =
                "Base compose file is required."
            return
        }

        let nameOverride =
            self.nameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            ? nil
            : self.nameOverride.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let compose = ComposeResource(
                baseCompose: baseCompose,
                projectDirectory: projectDirectory,
                additionalComposes: additionalComposes,
                envFiles: envFiles,
                nameOverride: nameOverride
            )

            if !override,
                ComposeService.composeResourceExist(name: compose.name),
                compose.name != existingCompose?.name
            {
                self.conflictingName = compose.name
                return
            }

            try ComposeService.addComposeResources([compose])
            self.dismiss()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

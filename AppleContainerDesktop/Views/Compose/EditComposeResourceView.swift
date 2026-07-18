//
//  EditComposeResourceView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import SwiftUI
import UniformTypeIdentifiers

struct EditComposeResourceView: View {

    //    init(composeResource: ComposeResource ) {
    //        self.baseCompose = composeResource.baseCompose
    //        self.additionalComposes
    //    }

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    var isNew: Bool = true

    @SwiftUI.State private var errorMessage: String?

    // use a different one then applicationManager.showProgressView to show the progress view over this sheet
    @SwiftUI.State private var showProgressView: Bool = false

    @SwiftUI.State private var showAdditionalSettings: Bool = false

    @SwiftUI.State private var baseCompose: URL?
    @SwiftUI.State private var additionalComposes: [URL] = []
    // envs for parsing vars in the compose files
    @SwiftUI.State private var envFiles: [URL] = []
    @SwiftUI.State private var projectDirectory: URL?
    @SwiftUI.State private var nameOverride: String = ""

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
                        allowedContentTypes: [.item]
                    )
                    .onChange(
                        of: baseCompose,
                        {
                            guard let url = baseCompose,
                                projectDirectory == nil
                            else {
                                return
                            }
                            projectDirectory = url.parentDirectory
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
                            // TODO: check duplication with main compose
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment Files")
                        MultiFileSelectView(
                            fileURLs: $envFiles,
                            errorMessage: $errorMessage,
                            allowedContentTypes: [.fileURL]
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
                        action: {
                            guard self.baseCompose != nil else {
                                self.errorMessage =
                                    "Base compose file is required."
                                return
                            }

                            // TODO: hook up compose resource logic
                        },
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
        .animation(.default, value: self.additionalComposes.count)
        .animation(.default, value: self.envFiles.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }

}
//
//struct FileListSelection: View {
//    var title: String
//    var addButtonTitle: String
//    var files:
//    var contentTypes: [UTType]
//    var errorMessage: String
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 8) {
//
//            MultiFileSelectView(fileURLs: files, errorMessage: .constant(nil), allowedContentTypes: <#T##[UTType]#>)
//
//            FileSelectView(
//                fileURL: $file.url,
//                errorMessage: $errorMessage,
//                allowedContentTypes:contentTypes
//            )
//        }
//
//    }
//}

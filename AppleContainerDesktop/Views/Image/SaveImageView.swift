//
//  SaveImageView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/10/03.
//

import ContainerAPIClient
internal import ContainerizationOCI
import SwiftUI
import UniformTypeIdentifiers

struct SaveImageView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    var images: [ClientImage]

    @Binding var imageReferences: String

    @SwiftUI.State private var errorMessage: String?

    @SwiftUI.State private var showProgressView: Bool = false

    @SwiftUI.State private var showPickLocalImage: Bool = false

    @SwiftUI.State private var showAdditionalSettings: Bool = false

    @SwiftUI.State private var platformString: String = Platform.current
        .description
    @SwiftUI.State private var outputDirectory: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            VStack(alignment: .leading, spacing: 8) {
                Text("Save Images")
                    .font(.headline)

                Text("Save images as an OCI compatible tar archive.")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.secondary)

                if let errorMessage = self.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Local Image References")

                HStack(spacing: 16) {
                    TextField("", text: $imageReferences)
                        .frame(maxHeight: .infinity)
                    Button(
                        action: {
                            self.showPickLocalImage = true
                        },
                        label: {
                            Text("Add")
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Output Directory")
                FileSelectView(
                    fileURL: $outputDirectory,
                    errorMessage: $errorMessage,
                    allowedContentTypes: [.directory]
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
                    Text("Platform")
                    Text(
                        "⭑ The value takes the form of os/arch or os/arch/variant. \n    ex: `linux/amd64` or `linux/arm/v7`."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    TextField(text: $platformString, label: {})
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
                        let referencesArray: [String] = self.imageReferences
                            .split(separator: ",").map({
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            })
                        guard !referencesArray.isEmpty else {
                            self.errorMessage =
                                "Image references cannot be empty."
                            return
                        }
                        let selectedImages: [ClientImage] = self.images.filter({
                            referencesArray.contains($0.reference)
                        })
                        let difference = Set(referencesArray).subtracting(
                            Set(selectedImages.map(\.reference))
                        )
                        if !difference.isEmpty {
                            self.errorMessage =
                                "Failed to get images for the following references: \(Array(difference).joined(separator: ","))"
                            return
                        }

                        guard let outputDirectory else {
                            self.errorMessage = "Output Directory is required."
                            return
                        }

                        Task {
                            self.showProgressView = true

                            do {
                                let platform = try Platform(
                                    from: self.platformString
                                )

                                try await ImageService.saveImages(
                                    selectedImages,
                                    platform: platform,
                                    outputDirectory: outputDirectory,
                                    messageStreamContinuation: self
                                        .applicationManager
                                        .messageStreamContinuation
                                )
                                let _ = NSWorkspace.shared.open(outputDirectory)

                                self.dismiss()

                            } catch (let error) {
                                self.errorMessage = "\(error)"
                            }

                            self.showProgressView = false
                        }
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
        .padding(.all, 24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
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
                let referencesArray: [String] = self.imageReferences.split(
                    separator: ","
                ).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                // filter out the selected
                let availableImages: [ClientImage] = self.images.filter({
                    !referencesArray.contains($0.reference)
                })

                LocalImagePickingView(
                    images: availableImages,
                    onImageSelect: { reference in
                        self.imageReferences = referencesArray.joined(
                            separator: ","
                        )
                        if self.imageReferences.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty {
                            self.imageReferences = reference
                        } else {
                            self.imageReferences.append(", \(reference)")
                        }
                    }
                )
            }
        )
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }

}

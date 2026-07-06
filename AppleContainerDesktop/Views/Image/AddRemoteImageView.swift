//
//  AddRemoteImageView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import ContainerAPIClient
import ContainerAPIService
import ContainerPersistence
import ContainerPlugin
import ContainerResource
import Containerization
internal import ContainerizationOCI
import SwiftUI

struct AddRemoteImageView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var imageReference: String = ""
    @SwiftUI.State private var errorMessage: String?

    @SwiftUI.State private var showProgressView: Bool = false

    @SwiftUI.State private var showAdditionalSettings: Bool = false

    @SwiftUI.State private var platformString: String = Platform.current
        .description
    @SwiftUI.State private var requestScheme: RequestScheme = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pull Remote Image")
                    .font(.headline)

                if let errorMessage = self.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)

                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Image Reference")
                Text(
                    "Ex: `alpine:latest` or `docker.io/exampleuser/demo:latest`"
                )
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                TextField("", text: $imageReference)
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

                    TextField(
                        text: $platformString,
                        prompt: Text("Ex: linux/amd64"),
                        label: {}
                    )
                }

                HStack(alignment: .lastTextBaseline) {
                    Text("Request Scheme")
                    Picker(
                        selection: $requestScheme,
                        content: {
                            let schemes: [RequestScheme] = [
                                .auto, .http, .https,
                            ]
                            ForEach(schemes, id: \.self) { scheme in
                                Text(scheme.rawValue)
                                    .tag(scheme)
                            }
                        },
                        label: {}
                    )
                    .labelsHidden()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                        let trimmedReference =
                            imageReference.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        guard !trimmedReference.isEmpty else {
                            self.errorMessage =
                                "Image reference cannot be empty."
                            return
                        }

                        Task {
                            self.showProgressView = true

                            do {
                                let platform = try Platform(
                                    from: self.platformString
                                )

                                try await ImageService.pullImage(
                                    reference: trimmedReference,
                                    platform: platform,
                                    scheme: self.requestScheme,
                                    messageStreamContinuation:
                                        self.applicationManager
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
                        Text("Pull")
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
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }

}

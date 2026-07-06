//
//  LoadImageView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/10/04.
//

import SwiftUI
import UniformTypeIdentifiers

struct LoadImageView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?

    @State private var showProgressView: Bool = false

    @State private var tarFile: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            VStack(alignment: .leading, spacing: 8) {
                Text("Load Images")
                    .font(.headline)

                Text("Load images from an OCI compatible tar archive.")
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
                Text("Tar URL")
                FileSelectView(
                    fileURL: $tarFile,
                    errorMessage: $errorMessage,
                    allowedContentTypes: [.tarArchive]
                )
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

                Button(
                    action: {

                        guard let tarFile else {
                            self.errorMessage = "Tar file is required."
                            return
                        }

                        Task {
                            self.showProgressView = true

                            do {

                                try await ImageService.loadImages(
                                    tar: tarFile,
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
                        Text("Load")
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

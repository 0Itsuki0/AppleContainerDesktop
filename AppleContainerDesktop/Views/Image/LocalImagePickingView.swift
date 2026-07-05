//
//  LocalImagePickingView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/10/03.
//

import ContainerAPIClient
internal import ContainerizationOCI
import SwiftUI

struct LocalImagePickingView: View {
    var images: [ClientImage]
    var onImageSelect: (String) -> Void

    @SwiftUI.State private var searchText: String = ""

    @Environment(\.dismiss) private var dismiss

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredImages: [ClientImage] {
        if trimmedText.isEmpty {
            return images
        }
        let filtered = self.images.filter({
            $0.reference.contains(trimmedText)
                || $0.description.name.contains(trimmedText)
        })

        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SearchBox(text: $searchText)

            List {
                ForEach(filteredImages, id: \.digest) { image in
                    Button(
                        action: {
                            self.onImageSelect(image.reference)
                            self.dismiss()
                        },
                        label: {
                            Text(image.reference)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    )

                }
            }
            .buttonStyle(.plain)
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(
                RoundedRectangle(cornerRadius: 4).fill(.clear).stroke(
                    .secondary,
                    style: .init(lineWidth: 1)
                )
            )

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
            .frame(maxWidth: .infinity, alignment: .trailing)

        }
        .multilineTextAlignment(.leading)
        .padding(.all, 24)
        .frame(width: 440, height: 400)
        .interactiveDismissDisabled(false)

    }
}

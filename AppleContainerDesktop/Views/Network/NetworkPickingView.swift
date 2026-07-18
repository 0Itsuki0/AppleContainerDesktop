//
//  NetworkPickingView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import ContainerResource
import SwiftUI

struct NetworkPickingView: View {
    var networks: [NetworkResource]
    var onNetworkSelect: (String) -> Void

    @SwiftUI.State private var searchText: String = ""

    @Environment(\.dismiss) private var dismiss

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredNetworks: [NetworkResource] {
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
            SearchBox(text: $searchText)

            List {
                ForEach(filteredNetworks, id: \.id) { network in
                    Button(
                        action: {
                            self.onNetworkSelect(network.name)
                            self.dismiss()
                        },
                        label: {
                            Text(network.name)
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

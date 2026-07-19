//
//  CreateNetworkView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import ContainerizationExtras
import SwiftUI

struct CreateNetworkView: View {

    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var name: String = ""
    @SwiftUI.State private var hostOnly: Bool = false
    @SwiftUI.State private var ipv4Subnet: String = ""
    @SwiftUI.State private var ipv6Subnet: String = ""
    @SwiftUI.State private var options: [KeyValueModel] = []
    @SwiftUI.State private var labels: [KeyValueModel] = []

    @SwiftUI.State private var showAdditionalSettings: Bool = false

    @SwiftUI.State private var errorMessage: String?

    // use a different one then applicationManager.showProgressView to show the progress view over this sheet
    @SwiftUI.State private var showProgressView: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Create New Network")
                        .font(.headline)

                    if let errorMessage = self.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)

                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Name")

                    TextField(
                        text: $name,
                        prompt: Text("Ex: network-1"),
                        label: {}
                    )
                }

                Divider()

                Button(
                    action: {
                        showAdditionalSettings.toggle()
                    },
                    label: {
                        HStack {
                            Text("Optional Settings")
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
                    Toggle(
                        isOn: $hostOnly,
                        label: {
                            Text("Restrict to host-only network")
                        }
                    )
                    .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("IPv4 Subnet (CIDR format)")

                        TextField(
                            text: $ipv4Subnet,
                            prompt: Text("Ex: 192.168.100.0/24"),
                            label: {}
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("IPv6 Subnet (CIDR format)")

                        TextField(
                            text: $ipv6Subnet,
                            prompt: Text("Ex: fd00:1234::/64"),
                            label: {}
                        )
                    }

                    KeyValuesEditView(
                        keyValues: $labels,
                        title: "Network Metadata (Label)"
                    )
                    KeyValuesEditView(
                        keyValues: $options,
                        title: "Network Options"
                    )

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
                            let name = self.name.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            guard !name.isEmpty else {
                                self.errorMessage = "Name is not specified."
                                return
                            }

                            let ipv4SubnetString = self.ipv4Subnet
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let ipv6SubnetString = self.ipv6Subnet
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            let ipv4Subnet: CIDRv4?
                            let ipv6Subnet: CIDRv6?
                            do {
                                ipv4Subnet =
                                    ipv4SubnetString.isEmpty
                                    ? nil : try CIDRv4(ipv4SubnetString)
                                ipv6Subnet =
                                    ipv6SubnetString.isEmpty
                                    ? nil : try CIDRv6(ipv6SubnetString)
                            } catch (let error) {
                                self.errorMessage = "\(error)"
                                return
                            }

                            Task {
                                self.showProgressView = true

                                do {
                                    let validLabels = self.labels.filter({
                                        !$0.key.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty
                                    })
                                    let validOptions = self.options.filter({
                                        !$0.key.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty
                                    })

                                    try await NetworkService.createNetwork(
                                        name: name,
                                        internal: self.hostOnly,
                                        labels: validLabels,
                                        options: validOptions,
                                        ipv4Subnet: ipv4Subnet,
                                        ipv6Subnet: ipv6Subnet,
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
                            Text("Create")
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
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: !self.showAdditionalSettings)
        .frame(maxHeight: 440)
        .sheet(
            isPresented: $showProgressView,
            content: {
                CustomProgressView()
                    .environment(self.applicationManager)
            }
        )
        .animation(.default, value: self.labels.count)
        .animation(.default, value: self.options.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }
}

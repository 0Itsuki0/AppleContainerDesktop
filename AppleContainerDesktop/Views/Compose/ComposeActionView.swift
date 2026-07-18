//
//  ComposeActionView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import SwiftUI

enum ComposeActionType: String, Identifiable {
    case up
    case down
    case build

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .up:
            "Compose Up"
        case .down:
            "Compose Down"
        case .build:
            "Compose Build"
        }
    }

    var actionTitle: String {
        switch self {
        case .up:
            "Up"
        case .down:
            "Down"
        case .build:
            "Build"
        }
    }
}

struct ComposeActionView: View {

    var type: ComposeActionType

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

    @SwiftUI.State private var allServices: [String] = []
    @SwiftUI.State private var allProfiles: [String] = []

    // only effect image
    @SwiftUI.State private var forceRebuild: Bool = false
    // effect volume and network
    @SwiftUI.State private var forceRecreate: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(self.type.title)
                        .font(.headline)

                    if let errorMessage = self.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)

                    }
                }

                self.stringListSection(
                    title: "Services",
                    subtitle:
                        "⭑ If empty, all services will be included. \n⭑ Explicitly targeting a service by name always bypasses profile restrictions.",
                    values: $requestedServices,
                    allValues: self.allServices
                )

                self.stringListSection(
                    title: "Profiles",
                    subtitle:
                        "⭑ Services without a `profiles` key are always enabled; \n    profiled services are enabled only when one of their profiles is active.",
                    values: $requestedProfiles,
                    allValues: self.allProfiles
                )

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
                            // TODO: hook up compose action logic
                        },
                        label: {
                            Text(self.type.actionTitle)
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: 440)
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
}

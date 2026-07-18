//
//  ComposeListView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import SwiftUI

struct ComposeListView: View {
    @Environment(ApplicationManager.self) private var applicationManager

    @State private var searchText: String = ""

    @State private var composes: [ComposeResource] = []
    @State private var lastUpdated: Date? = nil

    @State private var selections = Set<ComposeResource.ID>()

    @State private var showEditComposeResourceView: Bool = false
    @State private var showComposeActionViewForType: ComposeActionType?

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredComposes: [ComposeResource] {
        if trimmedText.isEmpty {
            return composes
        }
        let filtered = self.composes.filter({
            $0.name.contains(trimmedText)
        })

        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .lastTextBaseline) {
                HStack {
                    Text("Composes")
                        .font(.title2)
                        .fontWeight(.bold)

                    Button(
                        action: {
                            showEditComposeResourceView = true
                        },
                        label: {
                            Image(systemName: "plus")
                                .font(.subheadline)
                        }
                    )
                    .buttonStyle(
                        CustomButtonStyle(
                            backgroundShape: .circle,
                            backgroundColor: .blue
                        )
                    )

                }

                Spacer()

                if let lastUpdated {
                    HStack {
                        Text(
                            String(
                                "Last updated \(lastUpdated.formatted(date: .omitted, time: .standard))"
                            )
                        )

                        Button(
                            action: {
                                // TODO: refresh compose list
                            },
                            label: {
                                Image(
                                    systemName:
                                        "arrow.trianglehead.clockwise.rotate.90"
                                )
                            }
                        )
                    }

                }
            }

            HStack(spacing: 36) {
                SearchBox(text: $searchText)
                    .frame(width: 280)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Table(
                of: ComposeResource.self,
                selection: $selections,
                columns: {

                    TableColumn(TableHelper.columnHeader("Name")) { compose in
                        Text(compose.name)
                            .font(.headline)
                            .lineLimit(1)
                            .frame(height: 48)
                    }
                    .width(min: 80, ideal: 80)

                    TableColumn(TableHelper.columnHeader("Compose Path")) {
                        compose in
                        Text(compose.baseCompose.absolutePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .width(min: 160, ideal: 160, max: 240)

                    TableColumn(
                        TableHelper.columnHeader("Additional Compose")
                    ) { compose in
                        if compose.additionalCompose.isEmpty {
                            Text("(None)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(
                                compose.additionalCompose.map(\.absolutePath)
                                    .joined(separator: "\n")
                            )
                            .lineLimit(nil)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .width(min: 160, ideal: 160, max: 240)

                    TableColumn(TableHelper.columnHeader("Running Services")) {
                        compose in
                        let runningServices = compose.createdContainers.keys
                            .sorted()
                        if runningServices.isEmpty {
                            Text("(None)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(
                                runningServices.joined(separator: "\n")
                            )
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .width(min: 120, ideal: 120, max: 160)

                    TableColumn(TableHelper.columnHeader("Actions")) {
                        compose in

                        HStack(spacing: 12) {
                            Button(
                                action: {
                                    showComposeActionViewForType = .up
                                },
                                label: {
                                    TableHelper.actionImage(
                                        systemName: "play.fill"
                                    )
                                }
                            )
                            .buttonStyle(
                                CustomButtonStyle(
                                    backgroundShape: .circle,
                                    backgroundColor: .blue
                                )
                            )

                            Button(
                                action: {
                                    showComposeActionViewForType = .down
                                },
                                label: {
                                    TableHelper.actionImage(
                                        systemName: "stop.fill"
                                    )
                                }
                            )
                            .buttonStyle(
                                CustomButtonStyle(
                                    backgroundShape: .circle,
                                    backgroundColor: .gray
                                )
                            )

                            Divider()
                                .padding(.vertical, 12)

                            Button(
                                action: {
                                    // TODO: delete compose
                                },
                                label: {
                                    TableHelper.actionImage(
                                        systemName: "trash.fill"
                                    )
                                }
                            )
                            .buttonStyle(
                                CustomButtonStyle(
                                    backgroundShape: .circle,
                                    backgroundColor: .red
                                )
                            )
                        }
                        .padding(.horizontal, 8)
                    }
                    .width(120)

                },
                rows: {
                    ForEach(filteredComposes)
                }
            )
            .alternatingRowBackgrounds(.disabled)
            .overlay(
                alignment: .center,
                content: {
                    if !self.applicationManager.isSystemRunning {
                        SystemStoppedView()
                    } else if filteredComposes.isEmpty {
                        ContentUnavailableView(
                            trimmedText.isEmpty
                                ? "No Composes Found" : "No Matching Composes",
                            systemImage: "square.stack.3d.up.fill"
                        )
                    }
                }
            )

        }
        .sheet(
            isPresented: $showEditComposeResourceView,
            content: {
                EditComposeResourceView()
            }
        )
        .sheet(
            item: $showComposeActionViewForType,
            content: { type in
                ComposeActionView(type: type)
            }
        )
    }
}

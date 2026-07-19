//
//  ContainerDisplayModel.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/07.
//

import ContainerResource
internal import ContainerizationOCI
import Foundation

// ID for ContainerSnapshot
typealias ContainerSnapshotID = String

struct ContainerDisplayModel: Identifiable {
    // Unique name of the container if included.
    // If excluded will be a generated UUID
    var name: String {
        return self.container.id
    }
    // same as container.id
    var id: ContainerSnapshotID {
        return self.container.id
    }
    var imageDescription: ImageDescription
    var imageName: String {
        return self.imageDescription.name
    }
    var ports: String
    var os: String
    var arch: String
    var status: RuntimeStatus

    var state: String {
        self.status.rawValue.localizedCapitalized
    }

    var container: ContainerSnapshot

    init(_ container: ContainerSnapshot) {
        self.imageDescription = container.configuration.image
        self.ports = container.portsString
        self.os = container.configuration.platform.os.localizedCapitalized
        self.arch =
            container.configuration.platform.architecture.localizedCapitalized
        self.status = container.status
        self.container = container
    }
}

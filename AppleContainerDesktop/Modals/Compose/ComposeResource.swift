//
//  ComposeResource.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import DockerComposeParser
import Foundation

struct ComposeResource: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String {
        return name
    }
    // what the user passed in
    var baseCompose: URL
    var projectDirectory: URL
    var additionalCompose: [URL]
    var envFiles: [URL]

    // name override > compose.name > project directory
    var name: String

    // service name: containers created
    var createdContainers: [String: [ContainerSnapshotID]]
}


extension ComposeResource {
    
}

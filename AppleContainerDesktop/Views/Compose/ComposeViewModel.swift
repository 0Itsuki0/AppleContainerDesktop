//
//  ComposeViewModel.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/11.
//

import DockerComposeParser
import SwiftUI

struct ComposeResource: Codable {
    // what the user passed in
    var baseCompose: URL
    var projectDirectory: URL
    var additionalCompose: [URL]
    var envFiles: [URL]
    var ssh: [String]
    var secrets: [String]

    // what is resolved
    var compose: DockerCompose
    // name override > compose.name > project directory
    var name: String

    // what is built
    var imageIds: [String]
    // [image:[containers]]
    var containerIds: [String: [String]]
    var networks: [String]
    var volumes: [String]
}

@Observable
class ComposeViewModel {

}

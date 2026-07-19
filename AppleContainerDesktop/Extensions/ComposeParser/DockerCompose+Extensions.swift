//
//  DockerCompose+Extensions.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/19.
//

import DockerComposeParser

extension DockerCompose {
    var allProfiles: [String] {
        services.flatMap({$0.value?.profiles ?? []})
    }

    var allServiceNames: [String] {
        services.map({$0.key})
    }
}

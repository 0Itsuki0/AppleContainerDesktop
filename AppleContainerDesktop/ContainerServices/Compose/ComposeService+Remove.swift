//
//  ComposeService+Remove.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/17.
//

import ContainerAPIClient
import ContainerResource
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import ContainerizationOS
import DockerComposeParser
import Foundation

extension ComposeService {

    // startedContainers and createdImages passed in in case compose.yaml is different from the previous up
    // returning: removed services
    static func removeCompose(
        _ baseCompose: URL,
        additionalComposes: [URL] = [],
        // envs for parsing vars in the compose files
        envFiles: [URL] = [],
        projectDirectory: URL? = nil,
        nameOverride: String? = nil,
        // Services to build (builds all if omitted)
        // Explicitly targeting a service by name is an absolute override.
        // and always bypasses profile restrictions
        requestedServices: [String] = [],
        // Specify a profile to enable. Can be repeated.
        // Services without a 'profiles' key are always enabled;
        // profiled services are enabled only when one of their profiles is active.
        requestedProfiles: [String] = [],
        // Service name: container name (or id, same thing)
        startedContainers: [String: [ContainerSnapshotID]],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> [String] {

        return try await downCompose(
            baseCompose,
            additionalComposes: additionalComposes,
            // envs for parsing vars in the compose files
            envFiles: envFiles,
            projectDirectory: projectDirectory,
            nameOverride: nameOverride,
            // Services to build (builds all if omitted)
            // Explicitly targeting a service by name is an absolute override.
            // and always bypasses profile restrictions
            requestedServices: requestedServices,
            // Specify a profile to enable. Can be repeated.
            // Services without a 'profiles' key are always enabled;
            // profiled services are enabled only when one of their profiles is active.
            requestedProfiles: requestedProfiles,
            // Service name: container name (or id, same thing)
            startedContainers: startedContainers,
            shouldRemove: true,
            messageStreamContinuation: messageStreamContinuation
        )
    }

}

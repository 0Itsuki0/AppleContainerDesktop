//
//  ComposeService+Down.swift
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
    static func downCompose(
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
        startedContainers: [String: [ContainerSnapshotID]] = [:],
        shouldRemove: Bool = false,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {

        let projectDirectory =
            projectDirectory ?? baseCompose.deletingLastPathComponent()

        // all relative file path as well as any variables used in the YAML will be resolved
        let compose = try ComposeParser.loadComposes(
            baseCompose,
            otherComposes: additionalComposes,
            envFiles: envFiles,
            projectDirectory: projectDirectory,
            nameOverride: nameOverride
        )

        let projectName = resolveProjectName(
            projectDirectory: projectDirectory,
            compose: compose,
            nameOverride: nameOverride
        )

        messageStreamContinuation?.yield(
            "Downing compose: \(projectName)..."
        )

        let selectedServices = try selectServices(
            compose: compose,
            requestedServices: requestedServices,
            requestedProfiles: requestedProfiles,
        )

        try await self.downServices(
            projectName: projectName,
            selectedServices: selectedServices,
            containersCreated: startedContainers,
            shouldDelete: shouldRemove,
            messageStreamContinuation: messageStreamContinuation
        )

        let leftovers = startedContainers.filter({ serviceName, _ in
            compose.services[serviceName] == nil
        }).flatMap({ $0.value })

        do {
            try await ContainerService.stopContainers(
                leftovers,
                stopTimeoutSeconds: 5,
                messageStreamContinuation: nil
            )

            if shouldRemove {
                try await deleteContainers(Array(leftovers))
            }
        } catch {
            // not throwing here as it is just a clean up (not requested by the user)
            print("Error removing leftover containers: \(error).")
        }

        messageStreamContinuation?.yield(
            "\(selectedServices.map(\.serviceName).joined(separator: ", ")) are \(shouldRemove ? "removed" : "stopped")."
        )
    }

    // stopping containers in the opposite order as they have started,
    // ie: reversed topo order
    static func downServices(
        projectName: String,
        selectedServices: [(serviceName: String, service: Service)],
        containersCreated: [String: [ContainerSnapshotID]],
        shouldDelete: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let reversedStages = try topoSortConfiguredServices(selectedServices)
            .reversed()

        for stage in reversedStages {
            // NOTE: not use task group here as the services have to be stopped in the reverse order
            for (serviceName, service, _) in stage {
                messageStreamContinuation?.yield(
                    "\(shouldDelete ? "Removing" : "Stopping") service: \(serviceName)..."
                )
                let count = service.deploy?.replicas ?? 1
                let containerNames: [String] = (1..<1 + count).map({ index in
                    containerName(
                        explicit: service.container_name,
                        projectName: projectName,
                        serviceName: serviceName,
                        index: index,
                        total: count
                    )
                })
                let allContainerNames = Array(
                    Set(containerNames).union(
                        Set(containersCreated[serviceName] ?? [])
                    )
                )
                try await ContainerService.stopContainers(
                    allContainerNames,
                    stopTimeoutSeconds: 5,
                    messageStreamContinuation: nil
                )

                try await waitForStop(allContainerNames)

                if shouldDelete {
                    try await deleteContainers(allContainerNames)
                    messageStreamContinuation?.yield(
                        "service: \(serviceName) removed."
                    )
                }
            }
        }
    }

    private static func waitForStop(
        _ containerId: [ContainerSnapshotID],
        timeoutMs: TimeInterval = 10_000,
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for containerId in containerId {
                group.addTask {
                    try await waitForStop(containerId, timeoutMs: timeoutMs)
                }
            }
            try await group.waitForAll()
        }
    }

    private static func waitForStop(
        _ containerId: ContainerSnapshotID,
        timeoutMs: TimeInterval = 10_000,
    ) async throws {
        var elapsed: TimeInterval = 0
        let waitInterval: TimeInterval = 10
        while true {
            try await Task.sleep(for: .milliseconds(waitInterval))
            do {
                let container = try await ContainerService.getContainer(
                    containerId
                )
                if container.status == .stopped {
                    return
                }
            } catch {
                // not throwing here as we are still waiting.
            }

            if elapsed > timeoutMs {
                throw ContainerizationError(
                    .timeout,
                    message:
                        "Time out waiting for container \(containerId) to stop."
                )
            }
            elapsed += waitInterval
            continue
        }
    }

    private static func deleteContainers(_ containers: [String]) async throws {
        let containers = try await ContainerService.listContainers().filter({
            containers.contains($0.id)
        })

        let networks = containers.flatMap({ $0.networks }).map({ $0.network })

        let volumes = containers.flatMap({ $0.volumeNames })

        let images = containers.map({ $0.imageName })

        try await ContainerService.deleteContainers(
            containers,
            force: true,
            messageStreamContinuation: nil
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await VolumeService.deleteVolumes(
                    volumes,
                    messageStreamContinuation: nil
                )
            }

            group.addTask {
                try await ImageService.deleteImages(
                    images,
                    messageStreamContinuation: nil
                )
            }

            group.addTask {
                try await NetworkService.deleteNetworks(
                    networks,
                    messageStreamContinuation: nil
                )
            }

            try await group.waitForAll()
        }

        return
    }
}

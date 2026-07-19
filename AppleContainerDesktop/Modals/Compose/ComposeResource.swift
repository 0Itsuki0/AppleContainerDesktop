//
//  ComposeResource.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import ContainerResource
import DockerComposeParser
import Foundation

struct ComposeResourceStruct: Equatable, Hashable {
    var id: String { name }
    var name: String

    var baseCompose: URL
    // using optional here to distinguish between explicitly set URL and default
    var projectDirectory: URL?
    var additionalComposes: [URL]
    var envFiles: [URL]
    var parsingError: String?
    var parsedCompose: DockerCompose?

    var nameOverride: String?

    // service name: containers created
    var runningContainers: [String: [ContainerSnapshotID]]
    var stoppedContainers: [String: [ContainerSnapshotID]]

    init(resource: ComposeResource) {
        self.name = resource.name
        self.baseCompose = resource.baseCompose
        self.projectDirectory = resource.projectDirectory
        self.additionalComposes = resource.additionalComposes
        self.envFiles = resource.envFiles
        self.parsingError = resource.parsingError
        self.parsedCompose = resource.parsedCompose
        self.nameOverride = resource.nameOverride
        self.runningContainers = resource.runningContainers
        self.stoppedContainers = resource.stoppedContainers
    }
}

extension ComposeResource: Hashable, Equatable {
    func hash(into hasher: inout Hasher) {
        let resourceStruct = ComposeResourceStruct(resource: self)
        hasher.combine(resourceStruct)
    }

    static func == (lhs: ComposeResource, rhs: ComposeResource) -> Bool {
        let lhsStruct = ComposeResourceStruct(resource: lhs)
        let rhsStruct = ComposeResourceStruct(resource: rhs)
        return lhsStruct == rhsStruct
    }
}

@Observable
nonisolated
    final class ComposeResource: Identifiable, Codable, @unchecked Sendable
{

    var id: String { name }

    var containInvalidPath: Bool {
        !self.invalidFilePaths.isEmpty
    }

    var invalidFilePaths: [URL] {
        let all = [baseCompose] + additionalComposes + envFiles
        return all.filter({
            !FileManager.default.fileExists(atPath: $0.path())
        })
    }

    // what the user passed in
    var baseCompose: URL
    // using optional here to distinguish between explicitly set URL and default
    var projectDirectory: URL?
    var additionalComposes: [URL]
    var envFiles: [URL]

    // name override > compose.name > project directory
    var name: String {
        let projectDirectory = projectDirectory ?? baseCompose.parentDirectory
        return ComposeService.resolveProjectName(
            projectDirectory: projectDirectory,
            compose: parsedCompose,
            nameOverride: nameOverride
        )
    }

    var parsingError: String?
    var parsedCompose: DockerCompose?

    var nameOverride: String?

    // service name: containers created
    var runningContainers: [String: [ContainerSnapshotID]]
    var stoppedContainers: [String: [ContainerSnapshotID]]

    init(
        baseCompose: URL,
        projectDirectory: URL?,
        additionalComposes: [URL],
        envFiles: [URL],
        nameOverride: String?
    ) {
        self.baseCompose = baseCompose
        self.projectDirectory = projectDirectory
        self.additionalComposes = additionalComposes
        self.envFiles = envFiles
        self.nameOverride =
            nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == true
            ? nil
            : nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.runningContainers = [:]
        self.stoppedContainers = [:]
        self.parseCompose()
    }

    func parseCompose() {
        let projectDirectory =
            projectDirectory ?? baseCompose.parentDirectory

        do {
            self.parsedCompose = try ComposeParser.loadComposes(
                baseCompose,
                otherComposes: additionalComposes,
                envFiles: envFiles,
                projectDirectory: projectDirectory,
                nameOverride: nameOverride
            )
            self.refreshServiceStatus()
            self.parsingError = nil
        } catch (let error) {
            print(error)
            self.parsingError = error.localizedDescription
        }
    }

    enum CodingKeys: String, CodingKey {
        case baseCompose
        case projectDirectory
        case additionalComposes
        case envFiles
        case name
        case nameOverride
        case runningContainers
        case stoppedContainers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseCompose = try container.decode(URL.self, forKey: .baseCompose)
        self.projectDirectory = try container.decodeIfPresent(
            URL.self,
            forKey: .projectDirectory
        )
        self.additionalComposes = try container.decode(
            [URL].self,
            forKey: .additionalComposes
        )
        self.envFiles = try container.decode([URL].self, forKey: .envFiles)
        self.nameOverride = try container.decodeIfPresent(
            String.self,
            forKey: .nameOverride
        )
        self.runningContainers = try container.decode(
            [String: [ContainerSnapshotID]].self,
            forKey: .runningContainers
        ).filter({ !$0.value.isEmpty })

        self.stoppedContainers = try container.decode(
            [String: [ContainerSnapshotID]].self,
            forKey: .stoppedContainers
        ).filter({ !$0.value.isEmpty })

        self.parseCompose()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseCompose, forKey: .baseCompose)
        try container.encode(projectDirectory, forKey: .projectDirectory)
        try container.encode(additionalComposes, forKey: .additionalComposes)
        try container.encode(envFiles, forKey: .envFiles)
        try container.encodeIfPresent(nameOverride, forKey: .nameOverride)
        try container.encode(runningContainers, forKey: .runningContainers)
        try container.encode(stoppedContainers, forKey: .stoppedContainers)
    }
}

extension ComposeResource {
    // compose up: additive
    // ie: if service A was started, and then B starts,
    // both A and B will be running
    func onUp(newContainers: [String: [ContainerSnapshotID]]) {
        var finalRunning = runningContainers
        var finalStopped = stoppedContainers
        var pendingRemoval: Set<String> = []

        for (key, value) in newContainers {
            // containers to be removed
            let oldRunning = finalRunning[key] ?? []
            let diffRunning = Set(oldRunning).subtracting(Set(value))

            let oldStopped = finalStopped[key] ?? []
            let diffStopped = Set(oldStopped).subtracting(Set(value))

            pendingRemoval = pendingRemoval.union(diffRunning).union(
                diffStopped
            )

            finalRunning[key] = value
            finalStopped.removeValue(forKey: key)
        }

        self.runningContainers = finalRunning.filter({ !$0.value.isEmpty })

        // remove staled containers
        // for example, user previous started 3 replica, and changed to 2 -> 1 staled container
        // not throwing here as it is not an error that user necessarily needs to know
        // Also, no need for stopping in topo order since they will be removed anyway
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.removeStaledContainers(Array(pendingRemoval))
        }
    }

    func onRemove(removedServices: [String]) {
        var finalRunning = runningContainers
        var finalStopped = stoppedContainers

        for key in removedServices {
            finalRunning.removeValue(forKey: key)
            finalStopped.removeValue(forKey: key)
        }
        self.runningContainers = finalRunning.filter({ !$0.value.isEmpty })
        self.stoppedContainers = finalStopped.filter({ !$0.value.isEmpty })
    }

    func onDown(downedServices: [String]) {
        var finalRunning = runningContainers
        var finalStopped = stoppedContainers

        for key in downedServices {
            let containers = finalRunning[key]
            finalRunning.removeValue(forKey: key)
            if let containers {
                finalStopped[key] = containers
            }
        }
        self.runningContainers = finalRunning.filter({ !$0.value.isEmpty })
        self.stoppedContainers = finalStopped.filter({ !$0.value.isEmpty })
    }

    // 1. refresh container status (running, stopped, removed) on init
    // 2. check if any services defined in running/stopped container is not contained in the newly parsed docker compose anymore.
    nonisolated
        private func refreshServiceStatus()
    {
        guard let compose = parsedCompose else { return }
        guard !self.runningContainers.isEmpty || !self.stoppedContainers.isEmpty
        else { return }
        var finalRunning = self.runningContainers
        var finalStopped = self.stoppedContainers

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Step 1: remove any services that are not declared in the new compose any more.
            let runningServices = Set(finalRunning.keys)
            let stoppedServices = Set(finalStopped.keys)
            let allServices = Set(runningServices.union(stoppedServices))
            let removedServices = allServices.subtracting(compose.services.keys)

            removedServices.forEach { service in
                finalRunning.removeValue(forKey: service)
                finalStopped.removeValue(forKey: service)
            }

            let containersToRemove =
                finalRunning.filter({
                    removedServices.contains($0.key)
                }).flatMap({ $0.value })
                + finalStopped.filter({
                    removedServices.contains($0.key)
                }).flatMap({ $0.value })

            await removeStaledContainers(containersToRemove)

            await refreshContainerStatus(
                runningContainers: &finalRunning,
                stoppedContainers: &finalStopped
            )

            await MainActor.run {
                self.runningContainers = finalRunning.filter({ !$0.value.isEmpty })
                self.stoppedContainers = finalStopped.filter({ !$0.value.isEmpty })
            }
        }
    }

    @concurrent
    nonisolated private func removeStaledContainers(_ containers: [String])
        async
    {
        do {
            // use optional here to try delete anyway.
            try await ContainerService.stopContainers(
                containers,
                stopTimeoutSeconds: 5,
                messageStreamContinuation: nil
            )
        } catch {
            print("Error stopping old containers: ", error)
        }
        // separate do-catch to try delete anyway.
        do {
            // use ContainerService instead of ComposeService here to avoid removing images and networks that are possibility still in use.
            try await ContainerService.deleteContainers(
                containers,
                force: true,
                messageStreamContinuation: nil
            )
        } catch {
            print("Error deleting old containers: ", error)
        }
    }

    @concurrent
    nonisolated private func refreshContainerStatus(
        runningContainers: inout [String: [String]],
        stoppedContainers: inout [String: [String]]
    ) async {
        do {
            let containers = try await ContainerService.listContainers()

            // step 1: check if container is stopped or removed for current running ones
            for (serviceName, running) in runningContainers {
                for container in running {
                    if let first = containers.first(where: {
                        $0.id == container
                    }) {
                        if first.status != .running {
                            // container stopped
                            runningContainers[serviceName]?.removeAll(where: {
                                $0 == container
                            })
                            stoppedContainers[serviceName, default: []].append(
                                container
                            )
                        }
                    } else {
                        // container deleted else where
                        runningContainers[serviceName]?.removeAll(where: {
                            $0 == container
                        })
                    }
                }
            }

            // step 2: check if container is restarted or removed for current stopped ones
            for (serviceName, stopped) in stoppedContainers {
                for container in stopped {
                    if let first = containers.first(where: {
                        $0.id == container
                    }) {
                        if first.status == .running {
                            // container restarted
                            stoppedContainers[serviceName]?.removeAll(where: {
                                $0 == container
                            })
                            runningContainers[serviceName, default: []].append(
                                container
                            )
                        }
                    } else {
                        // container deleted else where
                        stoppedContainers[serviceName]?.removeAll(where: {
                            $0 == container
                        })
                    }
                }
            }
        } catch {
            print("Error refreshing service status:", error)
        }
    }
}

//
//  ComposeService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/06.
//

import ContainerAPIClient
import ContainerResource
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import ContainerizationOS
import DockerComposeParser
import Foundation

// MARK: - Known limitations
// 1. Disable ipV4 and ipV6 not supported (as of current implementation of Container)
// 2. Remote OCI not supported (as of current implementation of DockerComposeParser)
// 3. build.network not supported when building an image from dockerfile (as of current implementation of Container)
// 4. service.develop, configs, hooks, volumes_from not supported
// 6. network alias not supported  (as of current implementation of Container)
// 7. replica not supported for named volumes (as of current implementation of Container)
// 8. auto recreate on images/volumes/networks when configuration changed

enum ComposeService {
    private static let userDefaults = UserDefaults.standard
    private static let userDefaultsKey = "com.apple.container.desktop.compose"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func listComposeResources() -> [ComposeResource] {
        if let data = userDefaults.data(forKey: userDefaultsKey) {
            return (try? decoder.decode([ComposeResource].self, from: data))
                ?? []
        }
        return []
    }

    // called when there might be a name change to a saved compose resource
    static func updateComposeResource(oldName: String?, new: ComposeResource)
        throws
    {
        var allComposes = listComposeResources()
        allComposes.removeAll(where: { oldName == $0.name })
        // not deleting resources such as containers, as it meant for a name change (update), not removal
        allComposes.append(new)
        try saveComposeToUserDefaults(allComposes)
    }

    static func saveComposeResources(_ composes: [ComposeResource]) throws {
        try self.addComposeResources(composes)
    }

    static func addComposeResources(_ composes: [ComposeResource]) throws {
        var allComposes = listComposeResources()
        allComposes.removeAll(where: { current in
            composes.contains(where: { $0.name == current.name })
        })
        allComposes = allComposes + composes
        try saveComposeToUserDefaults(allComposes)
    }

    static func composeResourceExist(name: String) -> Bool {
        listComposeResources().contains(where: { $0.name == name })
    }

    static func runningByCompose(containerName: String) -> ComposeResource? {
        return listComposeResources().first(where: {
            $0.runningContainers.contains(where: {
                $0.value.contains(containerName)
            })
                || $0.stoppedContainers.contains(where: {
                    $0.value.contains(containerName)
                })
        })
    }

    static func removeComposeResources(
        composes: [ComposeResource],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        guard !composes.isEmpty else { return }

        messageStreamContinuation?.yield(
            "Removing composes: \(composes.map(\.name).joined(separator: ", "))..."
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for compose in composes {
                group.addTask {
                    let _ = try await removeCompose(
                        compose.baseCompose,
                        additionalComposes: compose.additionalComposes,
                        // envs for parsing vars in the compose files
                        envFiles: compose.envFiles,
                        projectDirectory: compose.projectDirectory,
                        nameOverride: compose.nameOverride,
                        startedContainers: compose.runningContainers,
                        messageStreamContinuation: messageStreamContinuation
                    )

                    if let parsedCompose = compose.parsedCompose {
                        try await cleanUpStaledContainers(
                            compose: parsedCompose,
                            startedContainers: compose.runningContainers
                        )
                    }
                }
            }
            try await group.waitForAll()
        }

        let names = composes.map(\.name)
        var allComposes = listComposeResources()
        allComposes.removeAll(where: { names.contains($0.name) })

        try saveComposeToUserDefaults(allComposes)

        messageStreamContinuation?.yield(
            "Composes removed!"
        )
    }

    private static func saveComposeToUserDefaults(_ composes: [ComposeResource])
        throws
    {
        let data = try encoder.encode(composes)
        userDefaults.set(data, forKey: userDefaultsKey)
    }

    static func resolveActiveProfiles(_ profile: [String]) -> Set<
        String
    > {
        var result = Set(profile)
        if let envProfiles = ProcessInfo.processInfo.environment[
            "COMPOSE_PROFILES"
        ] {
            result.formUnion(
                envProfiles.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
            )
        }
        return result
    }

    // helper function to clean up containers for services that are removed from dockerCompose
    static func cleanUpStaledContainers(
        compose: DockerCompose,
        startedContainers: [String: [ContainerSnapshotID]]
    ) async throws {
        let leftovers = startedContainers.filter({ serviceName, _ in
            compose.services[serviceName] == nil
        }).flatMap({ $0.value })

        try await ContainerService.stopContainers(
            leftovers,
            stopTimeoutSeconds: 5,
            messageStreamContinuation: nil
        )
        try await deleteContainers(Array(leftovers))
    }

    // additionalComposes doesn't matter in terms of project name
    nonisolated static func resolveProjectName(
        baseCompose: URL,
        projectDirectory: URL?,
        envFiles: [URL],
        nameOverride: String?
    ) -> String {
        let projectDirectory =
            projectDirectory ?? baseCompose.parentDirectory
        let compose = try? ComposeParser.loadComposes(
            baseCompose,
            otherComposes: [],
            envFiles: envFiles,
            projectDirectory: projectDirectory,
            nameOverride: nameOverride
        )
        return resolveProjectName(
            projectDirectory: projectDirectory,
            composeName: compose?.name,
            nameOverride: nameOverride
        )
    }

    // name override > compose.name > project directory
    nonisolated
        static func resolveProjectName(
            projectDirectory: URL,
            composeName: String?,
            nameOverride: String?
        ) -> String
    {
        if let nameOverride {
            return nameOverride
        }
        return composeName ?? deriveProjectName(url: projectDirectory)
    }

    nonisolated
        static func deriveProjectName(url: URL) -> String
    {
        let url = !url.isDirectory ? url.parentDirectory : url
        // replace '.' with _ because it is not supported in the container name
        let projectName = url.lastPathComponent
            .replacingOccurrences(of: ".", with: "_")
        return projectName
    }

    /// Selects the services `up`, `build` should act on by default,
    /// applying both explicit service-name filtering and Compose `profiles` gating.
    ///
    /// Per the Compose spec, `profiles` gating is bypassed in two cases:
    ///   - a service named explicitly in `requestedServices`
    ///   - a service reached only as a `depends_on` dependency of an eligible
    ///     service (its own `profiles` are ignored)
    /// When `requestedServices` is empty, the seed set is every service that
    /// is profile-eligible for `activeProfiles` (unprofiled, or one of its
    /// profiles is active); dependencies of that seed are then pulled in
    /// regardless of their own profile.
    static func selectServicesForUpBuild(
        compose: DockerCompose,
        requestedServices: [String],
        requestedProfiles: [String]
    ) throws -> [(serviceName: String, service: Service)] {
        let activeProfiles = resolveActiveProfiles(requestedProfiles)

        // Route both the explicit-service-name and default cases through the same
        // selection `up`/`down` use: an explicit name (or the default profile-eligible
        // set) pulls in its `depends_on` graph regardless of that dependency's own
        // build/profile status. Without this, a dependency only reachable via
        // `depends_on` — whether profile-gated or just not named explicitly — would
        // be started by `up` but never get built here.
        let allServices: [(serviceName: String, service: Service)] =
            compose.services.compactMap { name, service in
                guard let service else { return nil }
                return (name, service)
            }

        let servicesByName = Dictionary(
            uniqueKeysWithValues: allServices.map {
                ($0.serviceName, $0.service)
            }
        )

        let seedNames: [String]
        if !requestedServices.isEmpty {
            seedNames = requestedServices
        } else {
            if !requestedProfiles.isEmpty {
                seedNames =
                    allServices
                    .filter {
                        isProfileEligible(
                            serviceProfiles: $0.service.profiles,
                            activeProfiles: activeProfiles
                        )
                    }
                    .map(\.serviceName)
            } else {
                seedNames = allServices.map(\.serviceName)
            }
        }

        var selected = Set<String>()

        func include(_ serviceName: String) throws {
            guard let service = servicesByName[serviceName] else {
                throw ContainerizationError(
                    .invalidArgument,
                    message: "Service \(serviceName) does not exist."
                )
            }
            guard selected.insert(serviceName).inserted else {
                return
            }

            for dependency in service.depends_on ?? [:] {
                try include(dependency.key)
            }
        }

        for serviceName in seedNames {
            try include(serviceName)
        }

        return allServices.filter { selected.contains($0.serviceName) }
    }

    /// Opposite of `selectServicesForUpBuild`, for `down` and `rm`:
    /// - returns the requested (or profile-eligible default) services plus everything that transitively
    /// depends on them — not their dependencies.
    ///
    /// NOTE:
    /// 1. Output order is arbitrary because compose.services is a Swift Dictionary. That's fine as long as you feed the result through topoSortConfiguredServices and reverse the stages for down, as its own doc comment already says — don't stop containers in this array's raw order.
    /// 2. Real docker compose down <service> doesn't cascade to dependents — it stops only the named services.
    /// However, this behavior of down/removing services depend on them as well is stricter and safer, but it deviates from the docker CLI.
    static func selectServicesForDownRemove(
        compose: DockerCompose,
        requestedServices: [String],
        requestedProfiles: [String]
    ) throws -> [(serviceName: String, service: Service)] {
        let activeProfiles = resolveActiveProfiles(requestedProfiles)

        var servicesByName: [String: Service] = [:]
        var dependents: [String: [String]] = [:]
        var orderedNames: [String] = []

        for (name, service) in compose.services {
            guard let service else { continue }
            servicesByName[name] = service
            orderedNames.append(name)
            for (depName, _) in service.depends_on ?? [:] {
                dependents[depName, default: []].append(name)
            }
        }

        var seedNames = requestedServices
        if seedNames.isEmpty {
            if activeProfiles.isEmpty {
                // nothing requested at all -> tear down everything
                seedNames = orderedNames
            } else {
                seedNames = orderedNames.filter { name in
                    isProfileEligible(
                        serviceProfiles: servicesByName[name]?.profiles,
                        activeProfiles: activeProfiles
                    )
                }
            }
        }

        var selected = Set<String>()
        var queue = seedNames
        while let name = queue.popLast() {
            guard servicesByName[name] != nil else {
                throw ContainerizationError(
                    .invalidArgument,
                    message: "Service \(name) does not exist."
                )
            }
            if selected.insert(name).inserted {
                queue.append(contentsOf: dependents[name] ?? [])
            }
        }

        return orderedNames.compactMap { name in
            selected.contains(name) ? (name, servicesByName[name]!) : nil
        }
    }

    static func isProfileEligible(
        serviceProfiles: [String]?,
        activeProfiles: Set<String>
    ) -> Bool {
        guard let serviceProfiles, !serviceProfiles.isEmpty else { return true }
        return !Set(serviceProfiles).isDisjoint(with: activeProfiles)
    }

    typealias StagedService = (
        serviceName: String,
        service: Service,
        // when nil, nothing depends on it
        condition: Service.DependencyCondition?
    )

    /// Returns the services in topological order based on `depends_on` relationships.
    /// Ordering semantics:
    /// Dependencies appear before dependents, which is what we want for up (start order). For down just reverse the result.
    /// Returns the services in topological order based on `depends_on` relationships.
    /// Dependencies are ordered before the services that depend on them.
    static func topoSortConfiguredServices(
        _ services: [(serviceName: String, service: Service)]
    ) throws -> [[StagedService]] {
        var serviceByName: [String: Service] = [:]
        var inputOrder: [String: Int] = [:]
        for (i, entry) in services.enumerated()
        where serviceByName[entry.serviceName] == nil {
            serviceByName[entry.serviceName] = entry.service
            inputOrder[entry.serviceName] = i
        }

        var dependents: [String: [String]] = [:]
        var inDegree: [String: Int] = [:]
        var strongest: [String: Service.DependencyCondition] = [:]

        for (name, service) in services {
            inDegree[name, default: 0] += 0
            for (depName, dependency) in service.depends_on ?? [:] {
                guard let dependency else { continue }
                guard serviceByName[depName] != nil else { continue }
                dependents[depName, default: []].append(name)
                inDegree[name, default: 0] += 1

                let condition = dependency.condition
                if let existing = strongest[depName] {
                    if condition.severity > existing.severity {
                        strongest[depName] = condition
                    }
                } else {
                    strongest[depName] = condition
                }
            }
        }

        var currentLevel = inDegree.filter { $0.value == 0 }.map(\.key)
        var stages: [[StagedService]] = []
        var placed = 0

        while !currentLevel.isEmpty {
            currentLevel.sort { inputOrder[$0]! < inputOrder[$1]! }

            stages.append(
                currentLevel.map { name in
                    (
                        serviceName: name,
                        service: serviceByName[name]!,
                        condition: strongest[name]
                    )
                }
            )
            placed += currentLevel.count

            var nextLevel: [String] = []
            for name in currentLevel {
                for dependent in dependents[name] ?? [] {
                    inDegree[dependent]! -= 1
                    if inDegree[dependent] == 0 {
                        nextLevel.append(dependent)
                    }
                }
            }
            currentLevel = nextLevel
        }

        guard placed == services.count else {
            let stuck = inDegree.filter { $0.value > 0 }.keys.sorted()
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Failed to resolve dependency for services: \(stuck)"
            )
        }

        return stages
    }

    static func containerName(
        explicit: String?,
        projectName: String,
        serviceName: String,
        index: Int,
        total: Int
    ) -> String {
        if let explicit {
            return explicit
        }
        if total == 1 {
            return "\(projectName)_\(serviceName)"
        }
        return "\(projectName)_\(serviceName)_\(index)"
    }

}

extension Dictionary {
    func removeNilValue<V>(_ valueType: V.Type = V.self) -> [Key: V]
    where Value == V? {
        return self.filter({ $0.value != nil }).mapValues({ $0! })
    }
}

extension Array {
    func removeNilValue<V>(_ valueType: V.Type = V.self) -> [V]
    where Element == V? {
        return self.filter({ $0 != nil }).map({ $0! })
    }
}

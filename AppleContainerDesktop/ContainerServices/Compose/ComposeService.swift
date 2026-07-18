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

// MARK: - warn the user on the following if encountered
// 1. explicit ipV4 and ipV6 has to be set (as of current implementation of Container)
// 2. Remote OCI not supported (as of current implementation of DockerComposeParser)
// 3. build.network not supported when building an image from dockerfile (as of current implementation of Container)
// 4. service.develop, configs, hooks not supported
// 6. network alias not supported  (as of current implementation of Container)

enum ComposeService {
    private static let userDefaults = UserDefaults.standard
    private static let userDefaultsKey = "com.apple.container.desktop.compose"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func listComposes() -> [ComposeResource] {
        if let data = userDefaults.data(forKey: userDefaultsKey) {
            return (try? decoder.decode([ComposeResource].self, from: data))
                ?? []
        }
        return []
    }

    static func saveComposes(_ composes: [ComposeResource]) throws {
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

    static func resolveProjectName(
        projectDirectory: URL,
        compose: DockerCompose,
        nameOverride: String?
    ) -> String {
        if let nameOverride {
            return nameOverride
        }
        return compose.name ?? deriveProjectName(url: projectDirectory)
    }

    static func deriveProjectName(url: URL) -> String {
        let url = !url.isDirectory ? url.deletingLastPathComponent() : url
        // We need to replace '.' with _ because it is not supported in the container name
        let projectName = url.lastPathComponent
            .replacingOccurrences(of: ".", with: "_")
        return projectName
    }

    /// Selects the services `up`, `build`, and `down` should act on by default,
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
    static func selectServices(
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
            seedNames =
                allServices
                .filter {
                    isProfileEligible(
                        serviceProfiles: $0.service.profiles,
                        activeProfiles: activeProfiles
                    )
                }
                .map(\.serviceName)
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

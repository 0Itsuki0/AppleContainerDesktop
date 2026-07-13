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

// TODO: - warn the user on the following if encountered
// 1. explicit ipV4 and ipV6 has to be set (as of current implementation of Container)
// 2. Remote OCI not supported (as of current implementation of DockerComposeParser)
// 3. build.network not supported when building an image from dockerfile (as of current implementation of Container)
// 4. service.develop, configs, hooks not supported
// 6. network alias not supported  (as of current implementation of Container)

enum ComposeService {

    // Not deleting any container yet.
    // Refer to the comment of `upCompose` above.
    static func downCompose() async throws {

    }

    // delete all resources
    static func deleteCompose() async throws {

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
    ) -> [(serviceName: String, service: Service)] {
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
            uniqueKeysWithValues: allServices.map { ($0.serviceName, $0.service) }
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

        func include(_ serviceName: String) {
            guard let service = servicesByName[serviceName],
                selected.insert(serviceName).inserted
            else {
                return
            }

            for dependency in service.depends_on ?? [:] {
                include(dependency.key)
            }
        }

        for serviceName in seedNames {
            include(serviceName)
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

extension Service.Build.CacheEntry {
    // https://docs.docker.com/reference/compose-file/build/#cache_from
    var stringRepresentation: String? {
        guard !options.isEmpty else {
            return nil
        }
        let typeString = "type=\(type)"
        let optionStrings: [String] = options.map({
            AdditionalUtility.keyValueString(key: $0.key, value: $0.value)
        })
        return "\(typeString),\(optionStrings.joined(separator: ","))"
    }
}

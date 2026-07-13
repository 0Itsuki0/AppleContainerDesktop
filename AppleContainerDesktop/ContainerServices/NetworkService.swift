//
//  NetworkService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/06.
//

import ContainerAPIClient
import ContainerNetworkClient
import ContainerResource
import ContainerizationError
import ContainerizationExtras

enum NetworkService {
    @discardableResult
    static func createNetwork(
        name: String,
        // Restrict to host-only network
        internal: Bool = false,
        // metadata
        labels: [KeyValueModel],
        options: [KeyValueModel],
        plugin: String = "container-network-vmnet",
        // IPv4 subnet for a network (CIDR format, e.g., 192.168.100.0/24)
        ipv4Subnet: CIDRv4?,
        // Set the IPv6 prefix for a network (CIDR format, e.g., fd00:1234::/64)
        ipv6Subnet: CIDRv6?,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> NetworkResource {
        return try await self.createNetwork(
            name: name,
            internal: `internal`,
            labels: labels.dictRepresentation,
            options: options.dictRepresentation,
            plugin: plugin,
            ipv4Subnet: ipv4Subnet,
            ipv6Subnet: ipv6Subnet,
            messageStreamContinuation: messageStreamContinuation
        )
    }

    @discardableResult
    static func createNetwork(
        name: String,
        // Restrict to host-only network
        internal: Bool = false,
        // metadata
        labels: [String: String],
        options: [String: String],
        plugin: String = "container-network-vmnet",
        // IPv4 subnet for a network (CIDR format, e.g., 192.168.100.0/24)
        ipv4Subnet: CIDRv4?,
        // Set the IPv6 prefix for a network (CIDR format, e.g., fd00:1234::/64)
        ipv6Subnet: CIDRv6?,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> NetworkResource {
        messageStreamContinuation?.yield("Creating network: \(name)...")
        let parsedLabels = try ResourceLabels(labels)
        let mode: NetworkMode = `internal` ? .hostOnly : .nat

        let config = try NetworkConfiguration(
            name: name,
            mode: mode,
            ipv4Subnet: ipv4Subnet,
            ipv6Subnet: ipv6Subnet,
            labels: parsedLabels,
            plugin: plugin,
            options: options
        )
        let networkClient = NetworkClient()
        let network = try await networkClient.create(configuration: config)
        messageStreamContinuation?.yield("Network created: \(name)")
        return network
    }

    static func listNetworks() async throws -> [NetworkResource] {
        let networkClient = NetworkClient()
        return try await networkClient.list()
    }

    static func getNetwork(_ name: String) async throws -> NetworkResource {
        // for network, name and id are the same
        guard
            let item = try await listNetworks().first(where: { name == $0.name }
            )
        else {
            throw ContainerizationError(
                .notFound,
                message: "network not found: \(name)"
            )
        }
        return item
    }

    static func deleteNetwork(
        _ networks: [String],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let networks = try await self.listNetworks().filter({
            networks.contains($0.name)
        })
        guard !networks.isEmpty else {
            return
        }
        try await self.deleteNetwork(
            networks,
            messageStreamContinuation: messageStreamContinuation
        )
    }

    static func deleteNetwork(
        _ networks: [NetworkResource],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        messageStreamContinuation?.yield(
            "Deleting \(networks.count) networks(s)..."
        )

        let networkClient = NetworkClient()

        let networks = try networks.filter { network in
            guard !network.isBuiltin else {
                throw ContainerizationError(
                    .invalidArgument,
                    message: "cannot delete a builtin network: \(network.id)"
                )
            }
            return true
        }

        var failed: [(String, Error)] = []
        await withTaskGroup(of: (String, Error)?.self) { group in
            for network in networks {
                group.addTask {
                    do {
                        // Delete atomically disables the IP allocator, then deletes
                        // the allocator. The disable fails if any IPs are still in use.
                        try await networkClient.delete(id: network.id)
                        messageStreamContinuation?.yield(
                            "Network deleted: \(network.id)"
                        )
                        return nil
                    } catch (let error) {
                        messageStreamContinuation?.yield(
                            "failed to delete network \(network.id): \(error)"
                        )
                        return (network.id, error)
                    }
                }
            }

            for await result in group {
                guard let result else {
                    continue
                }
                failed.append((result.0, result.1))
            }
        }

        if failed.count > 0 {
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to delete one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"

            )
        }
    }
}

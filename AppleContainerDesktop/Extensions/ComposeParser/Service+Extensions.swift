//
//  Service+Extensions.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import ContainerResource
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import DockerComposeParser

extension Service {
    // The network with the highest gw_priority is selected as the default gateway for the service container.
    // If unspecified, the default value is 0.
    var defaultNetwork: (String, Network?)? {
        guard let networks = self.networks else {
            return nil
        }
        let sorted = networks.map({ ($0.key, $0.value) }).sorted(by: {
            ($0.1?.gw_priority ?? 0) > ($1.1?.gw_priority ?? 0)
        })
        return sorted.first
    }

    var virtualization: Bool {
        guard
            let device = self.deploy?.resources?.reservations?.devices?.first(
                where: { $0.options?["virtualization"] != nil })
        else {
            return false
        }

        guard let virtualization = device.options?["virtualization"],
            let virtualization
        else {
            return false
        }

        return Bool(virtualization) ?? false
    }
}

extension Service.Port {
    var publishPort: PublishPort? {
        // published: Host port or range, e.g. "8080" or "8080-8090". Nil = Docker picks a random host port.
        guard let parsedPort = self.parsedPort else { return nil }
        guard let ipV4 = try? IPv4Address(self.host_ip ?? "0.0.0.0") else {
            return nil
        }

        // HOST is [IP:](port | range) (optional). If it is not set, it binds to all network interfaces (0.0.0.0).
        // PROTOCOL restricts ports to a specified protocol either tcp or udp(optional). Default is tcp.
        return try? PublishPort(
            hostAddress: IPAddress.v4(ipV4),
            hostPort: parsedPort.hostPort,
            containerPort: parsedPort.containerPort,
            proto: self.protocol?.publishProtocol ?? .tcp,
            count: parsedPort.count
        )

    }

    var parsedPort: (hostPort: UInt16, containerPort: UInt16, count: UInt16)? {
        func parseRange(_ s: String) -> (UInt16, UInt16)? {
            if let dash = s.firstIndex(of: "-") {
                guard let start = UInt16(s[s.startIndex..<dash]),
                    let end = UInt16(s[s.index(after: dash)...]),
                    end >= start
                else { return nil }
                return (start, UInt16(end - start + 1))
            } else {
                guard let p = UInt16(s) else { return nil }
                return (p, 1)
            }
        }

        guard let (containerPort, containerCount) = parseRange(target) else {
            return nil
        }

        guard let published = published else {
            // No published port specified — Docker assigns a random host port.
            return (0, containerPort, containerCount)
        }

        guard let (hostPort, hostCount) = parseRange(published),
            hostCount == containerCount
        else { return nil }

        return (hostPort, containerPort, hostCount)
    }
}

extension Service.PortProtocol {
    var publishProtocol: PublishProtocol {
        switch self {
        case .tcp:
            return .tcp
        case .udp:
            return .udp
        }
    }
}

extension Service.Platform {
    var containerPlatform: ContainerizationOCI.Platform {
        Platform(
            arch: self.arch ?? "",
            os: self.os,
            variant: self.variant
        )
    }
}

extension Service.DependencyCondition {
    /// Severity for barrier purposes. Higher = stricter gate.
    /// completed_successfully implies the container ran and exited 0, which
    /// subsumes started; we also rank it above healthy by convention.
    var severity: Int {
        switch self {
        case .service_started: 0
        case .service_healthy: 1
        case .service_completed_successfully: 2
        }
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

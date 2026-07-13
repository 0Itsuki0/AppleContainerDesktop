//
//  KeyValueModel.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import ContainerResource
import Foundation

nonisolated
    struct KeyValueModel: Identifiable
{
    let id: UUID = UUID()
    var key: String = ""
    var value: String = ""

    var stringRepresentation: String {
        return AdditionalUtility.keyValueString(
            key: self.key.trimmingCharacters(in: .whitespacesAndNewlines),
            value: self.value
        )
    }

    static func fromContainerEnv(_ container: ContainerSnapshot)
        -> [KeyValueModel]
    {
        let environments = container.configuration.initProcess.environment
        return environments.map({ Self.fromString($0) }).filter({ $0 != nil })
            .map({ $0! })
    }

    static func fromContainerPorts(_ container: ContainerSnapshot)
        -> [KeyValueModel]
    {
        let ports = container.configuration.publishedPorts
        return ports.map({ port in
            let host = "\(port.hostAddress):\(port.hostPort)"
            let container =
                "\(port.containerPort)[\(port.proto.rawValue.localizedUppercase)]"
            return KeyValueModel(key: host, value: container)
        })
    }

    static func fromString(_ string: String) -> KeyValueModel? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        let parts = trimmed.split(separator: "=", maxSplits: 2)
        if parts.count == 1 {
            return .init(key: String(parts[0]), value: "")
        }
        return .init(key: String(parts[0]), value: String(parts[1]))
    }

    static func fromDictionary(_ dict: [String: String]) -> [KeyValueModel] {
        return dict.map({
            KeyValueModel(key: $0.0, value: $0.1)
        })
    }
}

extension Array where Element == KeyValueModel {
    nonisolated
        var stringArray: [String]
    {
        return self.map(\.stringRepresentation)
    }

    nonisolated
        var dictRepresentation: [String: String]
    {
        Dictionary(
            self.map { ($0.key, $0.value) },
            uniquingKeysWith: { (first, second) in second }
        )
    }
}

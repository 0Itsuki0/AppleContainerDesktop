//
//  EnvConfiguration.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/10.
//

import Foundation
import ContainerClient

struct EnvConfiguration: Identifiable {
    let id: UUID = UUID()
    var key: String = ""
    var value: String = ""
    
    var envString: String {
        return "\(self.key.trimmingCharacters(in: .whitespacesAndNewlines))=\(self.value.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    
    static func fromContainer(_ container: ClientContainer) -> [EnvConfiguration] {
        let environments = container.configuration.initProcess.environment
        return environments.map({Self.fromString($0)}).filter({$0 != nil}).map({$0!})
    }
    
    static func fromString(_ string: String) -> EnvConfiguration? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        let parts = trimmed.split(separator: "=", maxSplits: 2)
        if parts.count == 1 {
            return nil
        }
        return .init(key: String(parts[0]), value: String(parts[1]))
    }
}

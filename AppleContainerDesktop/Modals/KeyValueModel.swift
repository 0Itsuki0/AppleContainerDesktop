//
//  KeyValueModel.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import Foundation
import ContainerClient

nonisolated
struct KeyValueModel: Identifiable {
    let id: UUID = UUID()
    var key: String = ""
    var value: String = ""
    
    var stringRepresentation: String {
        return Utility.keyValueString(key: self.key.trimmingCharacters(in: .whitespacesAndNewlines), value: self.value)
    }
    
    static func envFromContainer(_ container: ClientContainer) -> [KeyValueModel] {
        let environments = container.configuration.initProcess.environment
        return environments.map({Self.fromString($0)}).filter({$0 != nil}).map({$0!})
    }
    
    static func fromString(_ string: String) -> KeyValueModel? {
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


extension Array where Element == KeyValueModel {
    nonisolated
    var stringArray: [String] {
        return self.map(\.stringRepresentation)
    }
    
    nonisolated
    var dictRepresentation: [String: String] {
        Dictionary(self.map { ($0.key, $0.value) }, uniquingKeysWith: { (first, second) in second })
    }
}

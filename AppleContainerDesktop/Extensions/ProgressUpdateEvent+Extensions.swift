//
//  ProgressUpdateEvent+Extensions.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import TerminalProgress
import Foundation

extension ProgressUpdateEvent {
    
    // ignore small updates.
    var displayString: String {
        switch self {
            
        case .setDescription(let v):
            v
        case .setSubDescription(let v):
            v
        case .setItemsName(let v):
            "Set Items: \(v)"
        case .addTasks(_):
            ""
        case .setTasks(_):
            ""
        case .addTotalTasks(let v):
            "Add total \(v) tasks."
        case .setTotalTasks(let v):
            "Set total \(v) tasks."
        case .addItems(_):
            ""
        case .setItems(_):
            ""
        case .addTotalItems(let v):
            "Add total \(v) items."
        case .setTotalItems(let v):
            "Add total \(v) items."
        case .addSize(_):
            ""
        case .setSize(_):
            ""
        case .addTotalSize(let v):
            "Add total \(Formatter.byteCountFormatter.string(fromByteCount: Int64(v)))."
        case .setTotalSize(let v):
            "Set total \(Formatter.byteCountFormatter.string(fromByteCount: Int64(v)))."
        case .custom(let v):
            v
        }
    }
}

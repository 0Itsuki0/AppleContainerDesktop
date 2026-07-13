//
//  Formatter.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/07.
//

import Foundation

enum Formatter {
    static let byteCountFormatter = ByteCountFormatter()
    
    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

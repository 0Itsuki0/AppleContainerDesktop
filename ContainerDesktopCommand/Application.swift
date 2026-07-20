//
//  main.swift
//  ContainerDesktopCommand
//
//  Created by Itsuki on 2026/07/20.
//

import ArgumentParser
import Foundation

//'/Users/itsuki/Library/Developer/Xcode/DerivedData/AppleContainerDesktop-gyvksgzzwvunuxeicqqfiacsiwqn/Build/Products/Debug/ContainerDesktopCommand' --help
@main
public struct Main: AsyncParsableCommand {
    private static let commandName: String = "ContainerDesktopCommand"
    private static let version: String = "1.0.0"
    public static var versionString: String {
        "\(commandName) version \(version)"
    }
    public static let configuration: CommandConfiguration = .init(
        commandName: Self.commandName,
        abstract:
            "A paired tool with Apple Container desktop for easy access to specific resources.",
        version: Self.versionString,
        subcommands: [
            Compose.self
        ]
    )
    public init() {}
}

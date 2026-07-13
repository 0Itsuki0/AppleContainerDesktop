//
//  ContainerManager.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/04.
//

internal import Logging
import SwiftUI

enum DisplayCategory: String, Identifiable, Equatable {
    case container
    case image
    case volume

    var displayTitle: String {
        switch self {
        case .container:
            "Containers"
        case .image:
            "Images"
        case .volume:
            "Volumes"
        }
    }

    var icon: String {
        switch self {
        case .container:
            "cube.fill"
        case .image:
            "cloud.fill"
        case .volume:
            "internaldrive.fill"
        }
    }

    var id: String {
        self.rawValue
    }

    // for customizing order
    static let allCases: [DisplayCategory] = [.image, .container, .volume]
}

@Observable
class ApplicationManager {
    static let containerGithub: URL? = URL(
        string: "https://github.com/apple/container"
    )

    static var logger: Logger {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        var logger = Logger(label: "itsuki.enjoy.AppleContainerDesktop")
        #if DEBUG
            logger.logLevel = .info
        #else
            logger.logLevel = .error
        #endif

        return logger
    }

    var error: Error? {
        didSet {
            if let error = self.error {
                print(error)
                self.showError = true
                self.showProgressView = false
            }
        }
    }

    var showError: Bool = false {
        didSet {
            if !showError {
                self.error = nil
            }
        }
    }

    var isSystemRunning: Bool = false

    var selectedCategory: DisplayCategory = .image {
        didSet {
            self.selectedContainerID = nil
        }
    }

    var selectedContainerID: ContainerSnapshotID?
    var refreshContainerNeeded: Bool = false

    var showProgressView: Bool = false {
        didSet {
            if self.showProgressView {
                progressMessage = "Loading..."
            }
        }
    }
    var progressMessage: String = "Loading..."
    let messageStream: AsyncStream<String>
    let messageStreamContinuation: AsyncStream<String>.Continuation
    @ObservationIgnored private var messageTask: Task<Void, Error>?

    init() {
        (messageStream, messageStreamContinuation) = AsyncStream<String>
            .makeStream()
        self.messageTask = Task {
            for await message in messageStream {
                if !message.isEmpty {
                    self.progressMessage = message
                }
            }
        }
    }

    deinit {
        self.messageTask?.cancel()
        self.messageTask = nil

        Task {
            try? await SystemService.stopSystem(
                stopContainerTimeoutSeconds: UserSettingsManager
                    .defaultStopContainerTimeoutSeconds,
                shutdownTimeoutSeconds: UserSettingsManager
                    .defaultShutdownSystemTimeoutSeconds,
                messageStreamContinuation: nil
            )
        }
    }
}

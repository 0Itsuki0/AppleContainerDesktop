//
//  SystemStoppedView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import SwiftUI

struct SystemStoppedView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(UserSettingsManager.self) private var userSettingsManager
    
    var body: some View {
        ContentUnavailableView(label: {
            Label("System Is Stopped", systemImage: "exclamationmark.octagon.fill")
        },  actions: {
            Button(action: {
                Task {
                    do {
                        self.applicationManager.showProgressView = true
                        try await SystemService.startSystem(
                            appDataRootUrl: self.userSettingsManager.appRootUrl,
                            executablePathUrl: self.userSettingsManager.executablePathUrl,
                            timeoutSeconds: self.userSettingsManager.startSystemTimeoutSeconds,
                            messageStreamContinuation: self.applicationManager.messageStreamContinuation
                        )
                        self.applicationManager.showProgressView = false
                        self.applicationManager.isSystemRunning = true
                    } catch(let error) {
                        self.applicationManager.error = error
                    }

                }

            }, label: {
                Text("Start System")
            })

        })
    }
}

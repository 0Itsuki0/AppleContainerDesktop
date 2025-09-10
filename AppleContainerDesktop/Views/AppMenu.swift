//
//  AppMenu.swift
//  MacClipboardAIChat
//
//  Created by Itsuki on 2024/11/02.
//

import SwiftUI

struct AppMenu: View {
    @Environment(ApplicationManager.self) var applicationManager
    @Environment(UserSettingsManager.self) var userSettingsManager

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @State private var startingSystem: Bool = false
    @State private var stoppingSystem: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            Text(applicationManager.isSystemRunning ? "🟢 Apple Container is running." : "🔴 Apple Container is stopped.")
                .foregroundStyle(.secondary)

            
            Divider()
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
            
            Button(action: {
                NSApplication.shared.activate(ignoringOtherApps: true)
                self.openWindow(id: AppleContainerDesktopApp.dashboardWindowId)
            }, label: {
                Label("Dashboard", systemImage: "cube.fill")
            })
            
            Button(action: {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }, label: {
                Label("Settings", systemImage: "gearshape.fill")
            })
            
            Divider()
                .foregroundStyle(.primary)
                .padding(.vertical, 4)

            
            Button(action: {
                Task {
                    self.startingSystem = true

                    do {
                        try await SystemService.startSystem(
                            appDataRootUrl: self.userSettingsManager.appRootUrl,
                            executablePathUrl: self.userSettingsManager.executablePathUrl,
                            timeoutSeconds: self.userSettingsManager.startSystemTimeoutSeconds,
                            messageStreamContinuation: nil
                        )
                        self.applicationManager.isSystemRunning = true

                    } catch(let error) {
                        self.openWindow(id: AppleContainerDesktopApp.dashboardWindowId)
                        self.applicationManager.error = error
                    }
                    
                    self.startingSystem = false
                }
            }, label: {
                HStack {
                    Label("Start Container", systemImage: "play.fill")
                    if self.startingSystem {
                        ProgressView()
                            .controlSize(.mini)
                    }


                }
                .frame(maxWidth: .infinity, alignment: .leading)
            })
            .disabled(self.startingSystem || self.stoppingSystem)

            Button(action: {
                Task {
                    self.stoppingSystem = true

                    do {

                        try await SystemService.stopSystem(
                            stopContainerTimeoutSeconds: self.userSettingsManager.stopContainerTimeoutSeconds,
                            shutdownTimeoutSeconds: self.userSettingsManager.shutdownSystemTimeoutSeconds,
                            messageStreamContinuation: nil)
                        
                        self.applicationManager.isSystemRunning = false

                    } catch(let error) {
                        self.openWindow(id: AppleContainerDesktopApp.dashboardWindowId)
                        self.applicationManager.error = error
                    }
                    
                    self.stoppingSystem = false
                }
            }, label: {
                HStack {
                    Label("Stop Container", systemImage: "stop.fill")
                    if self.stoppingSystem {
                        ProgressView()
                            .controlSize(.mini)
                    }


                }
                .frame(maxWidth: .infinity, alignment: .leading)
            })
            .disabled(self.startingSystem || self.stoppingSystem)

            
            Button(action: {
                Task {
                    do {
                        try await SystemService.stopSystem(
                            stopContainerTimeoutSeconds: self.userSettingsManager.stopContainerTimeoutSeconds,
                            shutdownTimeoutSeconds: self.userSettingsManager.shutdownSystemTimeoutSeconds,
                            messageStreamContinuation: nil)
                        self.applicationManager.isSystemRunning = false
                    } catch(let error) {
                        print(error)
                    }
                    
                    NSApplication.shared.terminate(nil)
                }

            }, label: {
                Label("Terminate", systemImage: "power")

            })
            .disabled(self.startingSystem || self.stoppingSystem)

        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(width: 240)

    }
    
}

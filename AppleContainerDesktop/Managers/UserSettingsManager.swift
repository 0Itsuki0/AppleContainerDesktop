//
//  UserSettingsManager.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/09.
//


import SwiftUI


enum UserDefaultsKey: String {
    case executablePath
    case appRootPath
    case startSystemTimeoutSeconds
    case stopContainerTimeoutSeconds
    case shutdownSystemTimeoutSeconds
    
    static let userDefaults = UserDefaults.standard
    
    private var key: String {
        return self.rawValue
    }
    
    func setValue(value: Any?) {
        Self.userDefaults.setValue(value, forKey: self.key)
    }
    
    func getValue() -> Any? {
        return Self.userDefaults.object(forKey: self.key)
    }
}



@Observable
class UserSettingsManager {
    static let defaultExecutablePathString: String = "/usr/local/bin/container"
    static let defaultAppRootUrl = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!.appendingPathComponent("itsuki.enjoy.appleContainerDesktop")

    static let defaultStartSystemTimeoutSeconds: Int32 = 10
    // Seconds to wait before killing the container(s)
    static let defaultStopContainerTimeoutSeconds: Int32 = 5
    static let defaultShutdownSystemTimeoutSeconds: Int32 = 20

        
    private var executablePathString: String {
        didSet {
            UserDefaultsKey.executablePath.setValue(value: self.executablePathString)
        }
    }
    
    // Path URL
    var executablePathUrl: URL {
        get {
            if let url = URL(string: executablePathString), !url.isFileURL {
                return url
            }
            let fileURL = URL(filePath: executablePathString)
            return URL(string: fileURL.absolutePath) ?? URL(string: self.executablePathString)!
        }
        set(newValue) {
            self.executablePathString = newValue.absolutePath
        }
    }
    
    var executableExists: Bool {
        return FileManager.default.isExecutableFile(atPath: self.executablePathString)
    }
    
    private var appRootPathString: String {
        didSet {
            UserDefaultsKey.appRootPath.setValue(value: self.appRootPathString)
        }
    }
    
    // file scheme URL, ie: file://
    var appRootUrl: URL  {
        get {
            if let url = URL(string: appRootPathString), url.isFileURL {
                return url
            }
            return URL(filePath: appRootPathString)
        }
        set(newValue) {
            self.appRootPathString = newValue.absolutePath
        }
    }
   
    var startSystemTimeoutSeconds: Int32 = 10 {
        didSet {
            UserDefaultsKey.startSystemTimeoutSeconds.setValue(value: self.startSystemTimeoutSeconds)
        }
    }
    
    // Seconds to wait before killing the container(s)
    var stopContainerTimeoutSeconds: Int32 = 5 {
        didSet {
            UserDefaultsKey.stopContainerTimeoutSeconds.setValue(value: self.stopContainerTimeoutSeconds)
        }
    }
    
    var shutdownSystemTimeoutSeconds: Int32 = 20 {
        didSet {
            UserDefaultsKey.shutdownSystemTimeoutSeconds.setValue(value: self.shutdownSystemTimeoutSeconds)
        }
    }
    
    
    init() {
        self.executablePathString = UserDefaultsKey.executablePath.getValue() as? String ?? Self.defaultExecutablePathString
        self.appRootPathString = UserDefaultsKey.appRootPath.getValue() as? String ?? Self.defaultAppRootUrl.absolutePath
        self.startSystemTimeoutSeconds = UserDefaultsKey.appRootPath.getValue() as? Int32 ?? Self.defaultStartSystemTimeoutSeconds
        self.stopContainerTimeoutSeconds = UserDefaultsKey.appRootPath.getValue() as? Int32 ?? Self.defaultStopContainerTimeoutSeconds
        self.shutdownSystemTimeoutSeconds = UserDefaultsKey.appRootPath.getValue() as? Int32 ?? Self.defaultShutdownSystemTimeoutSeconds
    }

}

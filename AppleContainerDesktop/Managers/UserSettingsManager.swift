//
//  UserSettingsManager.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/09.
//


import SwiftUI


enum UserDefaultsKey: String {
    case executablePath
    case appRootURL
    case startSystemTimeoutSeconds
    case stopContainerTimeoutSeconds
    case shutdownSystemTimeoutSeconds
    
    static let userDefaults = UserDefaults.standard
    
    func setValue(value: Any?) {
        Self.userDefaults.setValue(value, forKey: self.rawValue)
    }
    
    func getValue() -> Any? {
        return Self.userDefaults.object(forKey: self.rawValue)
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
    
    var executablePathUrl: URL {
        get {
            return URL(string: self.executablePathString) ?? URL(string: self.executablePathString)!
        }
        set(newValue) {
            self.executablePathString = newValue.path(percentEncoded: true)
        }
    }
    
    var executableExists: Bool {
        return FileManager.default.isExecutableFile(atPath: self.executablePathString)
    }
    
    private var appRootUrlString: String {
        didSet {
            UserDefaultsKey.appRootURL.setValue(value: self.appRootUrlString)
        }
    }
    
    var appRootUrl: URL  {
        get {
            return URL(string: appRootUrlString) ?? Self.defaultAppRootUrl
        }
        set(newValue) {
            self.appRootUrlString = newValue.absoluteString
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
        self.appRootUrlString = UserDefaultsKey.appRootURL.getValue() as? String ?? Self.defaultAppRootUrl.absoluteString
        self.startSystemTimeoutSeconds = UserDefaultsKey.appRootURL.getValue() as? Int32 ?? Self.defaultStartSystemTimeoutSeconds
        self.stopContainerTimeoutSeconds = UserDefaultsKey.appRootURL.getValue() as? Int32 ?? Self.defaultStopContainerTimeoutSeconds
        self.shutdownSystemTimeoutSeconds = UserDefaultsKey.appRootURL.getValue() as? Int32 ?? Self.defaultShutdownSystemTimeoutSeconds
    }

}

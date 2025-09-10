//
//  ContainerProcess.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import Foundation

 struct ContainerProcess {
     // Current working directory for the container
     var workingDirectory: String?

     // environment variables. Key=value
     var environments: [String] = []

     // file of environment variables
     var envFile: [String] = []

     // "Keep Stdin open even if not attached")
     // var interactive = false

     // Open a terminal with the process
      var tty = false

     // uid for the process
     var uid: UInt32?

     // gid for the process
     var gid: UInt32?

     // user for the process
     var user: String?
}


# Apple Container Desktop: A GUI For Apple Container

A GUI for [Apple container](https://github.com/apple/container), 
a tool that we can use to create and run Linux containers as lightweight virtual machines on Mac.


## Perquisite
This app will not automatically download `container` so please make sure to install it either from the [GitHub](https://github.com/apple/container) or by running `brew install --cask container`.

## Installation
You can either download the entire repository and run/build it with Xcode or you can download the latest signed `dmg` for the app from the [GitHub release page](https://github.com/0Itsuki0/AppleContainerDesktop/releases).


## Basic Usage
After downloading both the `container` executable as well as this app, simply launch the app. 

By doing so, this app will try to find the `container` executable in the default location, ie: `/usr/local/bin/container`, and start the system. 
If the executable is not found, you will see the following prompting for setting a custom path and retry.

![](./ReadmeAssets/executableNotFound.png)

After system started correctly, we can then interact with the images and containers.

![](./ReadmeAssets/overview.gif)


## Current Features

### Images
- Pull Remote Image
- Build Image from Dockerfile
- Delete Image
- Inspect some basic Image information such as container using the image, OS, Arch, and etc.

#### Pull Remote
![](./ReadmeAssets/Image/pullImage.gif)  

#### Build From Dockerfile
![](./ReadmeAssets/Image/buildImage.png)  


### Containers
- Create new container 
    - From added image, or directly from remote references
    - Set custom name, add published ports and environment values
    
![](./ReadmeAssets/Container/createContainer.gif)  

- Start, stop, or delete containers
- Inspect container
    - Status, OS, Arch, published ports, environment variables, and logs.

![](./ReadmeAssets/Container/inspectContainer.gif)  


### Others

Set Custom values for 
- Path to `container` executable
- Application Data
- Time out time for starting and stopping the system, as well as stopping the container.

![](./ReadmeAssets/appSetting.png)


Interact with the container system through the menu if needed.

![](./ReadmeAssets/appMenu.png)



## Coming Soon

### Images
- Inspect Image with detail
- Add additional configurations for pulling / building images
- Tag and push images to remote repositories


### Containers
- More options when creating containers such as Adding mounts (file systems / volumes) to the container, specifying user, environment variables, and etc.
- Add more details when inspecting container
- Interact with (execute terminal command on) container

### Others
- Managing volumes
- Managing networks

If there is more you would like to see, please leave me a comment somewhere! Will be happy to know!


## Blogs
- [A Simple GUI For Apple Container. Like the Docker Desktop!](https://medium.com/@itsuki.enjoy/a-simple-gui-for-apple-container-like-the-docker-desktop-f16148c8bcc0)
- [Apple Container Usage In Details](https://medium.com/@itsuki.enjoy/apple-container-usage-in-details-ed3293aa8d3d)

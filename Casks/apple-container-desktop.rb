cask "apple-container-desktop" do
  version :latest
  sha256 :no_check

  url "https://github.com/0Itsuki0/AppleContainerDesktop/releases/latest/download/AppleContainerDesktop.dmg"
  name "Apple Container Desktop"
  desc "GUI for managing Apple Container workloads"
  homepage "https://github.com/0Itsuki0/AppleContainerDesktop"

  depends_on arch: [:arm64]
  depends_on macos: ">= :sequoia"
  depends_on cask: "homebrew/cask/container"

  app "AppleContainerDesktop.app"

  zap trash: [
    "~/Library/Application Support/AppleContainerDesktop",
    "~/Library/Preferences/itsuki.enjoy.AppleContainerDesktop.plist",
    "~/Library/Saved Application State/itsuki.enjoy.AppleContainerDesktop.savedState",
    "~/Library/Logs/AppleContainerDesktop",
  ]
end

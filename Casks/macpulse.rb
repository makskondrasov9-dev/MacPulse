cask "macpulse" do
  version "0.8.1"
  sha256 "ad7e1fd00a4a2a538f80ca41485c7b8fb913b272daf189568fa8b620cb0f574f"

  url "https://github.com/makskondrasov9-dev/MacPulse/releases/download/v#{version}/MacPulse.dmg"
  name "MacPulse"
  desc "Native system monitor, fan controller, cleaner and app uninstaller"
  homepage "https://github.com/makskondrasov9-dev/MacPulse"

  depends_on macos: :ventura

  app "MacPulse.app"

  uninstall quit: "local.iMacMonitor"
end

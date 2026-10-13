cask "macpulse" do
  version "0.9.0"
  sha256 "8b1e70eb555242125c5d473b781ab06959aec1505f365702937ffcb8233150de"

  url "https://github.com/makskondrasov9-dev/MacPulse/releases/download/v#{version}/MacPulse.dmg"
  name "MacPulse"
  desc "Native system monitor, fan controller, cleaner and app uninstaller"
  homepage "https://github.com/makskondrasov9-dev/MacPulse"

  depends_on macos: :ventura

  app "MacPulse.app"

  uninstall quit: "local.iMacMonitor"
end

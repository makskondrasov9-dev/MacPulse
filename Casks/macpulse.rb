cask "macpulse" do
  version "1.0.1"
  sha256 "8f5d66e0d0a1456b90a8f7ddeec371dfda650acbef8a5f9a05bc9204cc695e68"

  url "https://github.com/makskondrasov9-dev/MacPulse/releases/download/v#{version}/MacPulse.dmg"
  name "MacPulse"
  desc "Native Mac monitoring, desktop widgets, diagnostics and cleanup"
  homepage "https://github.com/makskondrasov9-dev/MacPulse"

  depends_on macos: :ventura

  app "MacPulse.app"

  uninstall quit: "local.iMacMonitor"
end

cask "macpulse" do
  version "1.0.0"
  sha256 "f7b638bcd3179db8467bb328118913023fda545b06ddff17c31cb0f0cb248235"

  url "https://github.com/makskondrasov9-dev/MacPulse/releases/download/v#{version}/MacPulse.dmg"
  name "MacPulse"
  desc "Native Mac monitoring, desktop widgets, diagnostics and cleanup"
  homepage "https://github.com/makskondrasov9-dev/MacPulse"

  depends_on macos: :ventura

  app "MacPulse.app"

  uninstall quit: "local.iMacMonitor"
end

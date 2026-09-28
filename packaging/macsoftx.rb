cask "macsoftx" do
  version "{{VERSION}}"
  sha256 "{{SHA256}}"
  url "https://github.com/<ORG>/macsoftx/releases/download/v#{version}/MacsoftX-#{version}.dmg"
  name "Macsoft X"
  desc "最好的用的 Mac 软件管理工具"
  homepage "https://github.com/<ORG>/macsoftx"
  app "Macsoft X.app"
end

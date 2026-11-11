#!/usr/bin/env python3
"""Package the built app and sign its update feed without exporting private keys."""
import hashlib
import html
import os
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = root / 'build/DeskNames.app'
out = root / 'dist'
out.mkdir(exist_ok=True)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version) or not build.isdigit():
    raise SystemExit('Release version/build must be numeric.')
public_key = (root / 'release/sparkle-public-key.txt').read_text().strip()
tools = root / '.build-deps/sparkle/bin'
if info['SUPublicEDKey'] != public_key:
    raise SystemExit('The app embeds a different update key than release/sparkle-public-key.txt; refusing release.')
# The Keychain key is read once, by generate_appcast. A different key is caught below, where both
# signatures are verified against release/sparkle-public-key.txt.
subprocess.run(['codesign', '--verify', '--deep', '--strict', app], check=True)
archive = out / f'DeskNames-{version}-arm64.zip'
if archive.exists():
    raise SystemExit(f'{archive} already exists; do not silently replace a release artifact.')
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive], check=True)
base = f'https://github.com/Kipung/DeskNames/releases/download/v{version}'
notes = out / f'DeskNames-{version}-arm64.html'
notes_file = os.environ.get('DESKNAMES_RELEASE_NOTES_FILE')
paragraphs = [p.strip() for p in Path(notes_file).read_text().split('\n\n') if p.strip()] if notes_file else [f'DeskNames {version}.']
notes.write_text(''.join(f'<p>{html.escape(p)}</p>' for p in paragraphs) +
                 '<p>This app is not notarized by Apple.</p>')
subprocess.run([tools/'generate_appcast', '--account', 'local.desknames.app', '--download-url-prefix', base+'/', '--link', 'https://github.com/Kipung/DeskNames', '--maximum-deltas', '0', '--embed-release-notes', out], check=True)
feed = out / 'appcast.xml'
sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
enclosure = ET.parse(feed).find('.//enclosure')
signature = enclosure.attrib.get(f'{{{sparkle}}}edSignature')
if not signature:
    raise SystemExit('Sparkle did not sign the archive: the private key does not match release/sparkle-public-key.txt.')
verifier = root / 'build/verify-update'
subprocess.run(['xcrun', 'swiftc', root/'scripts/verify-update.swift', '-o', verifier], check=True)
subprocess.run([verifier, root/'release/sparkle-public-key.txt', archive, signature], check=True)
subprocess.run([verifier, root/'release/sparkle-public-key.txt', feed], check=True)
(root/'release/appcast.xml').write_bytes(feed.read_bytes())
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
(out/'SHA256SUMS.txt').write_text(f'{sha}  {archive.name}\n')
cask = f'''cask "desknames" do
  version "{version}"
  sha256 "{sha}"

  url "https://github.com/Kipung/DeskNames/releases/download/v#{{version}}/DeskNames-#{{version}}-arm64.zip"
  name "DeskNames"
  desc "Named desktops, visual pane layouts, and window arrangement"
  homepage "https://github.com/Kipung/DeskNames"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "DeskNames.app"

  zap trash: [
    "~/Library/Application Support/DeskNames",
    "~/Library/Caches/local.desknames.app",
    "~/Library/Preferences/local.desknames.app.plist",
  ]

  caveats <<~EOS
    DeskNames is an unnotarized preview. macOS may require first-launch approval
    in System Settings > Privacy & Security. See the README before installing.
    Window management requires Accessibility permission, which carries over
    between updates. Uninstall preserves settings; --zap removes them.
  EOS
end
'''
(out/'desknames.rb').write_text(cask)
print(f'Packaged {archive.name}; SHA-256 {sha}. Feed and archive signatures verified.')

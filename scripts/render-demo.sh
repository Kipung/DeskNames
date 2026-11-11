#!/bin/zsh
set -eu
cd "${0:A:h}/.."
rm -rf build/marketing
mkdir -p build/marketing docs/media
build/DeskNames.app/Contents/MacOS/DeskNames --render-marketing "$PWD/build/marketing"
cp build/marketing/control-panel.png docs/media/control-panel.png
gifski --quiet --fps 24 --quality 90 -o docs/media/panes-demo.gif build/marketing/frame-*.png
ffmpeg -hide_banner -loglevel error -y -framerate 24 -i build/marketing/frame-%03d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart docs/media/panes-demo.mp4

#!/bin/zsh
set -eu
cd "${0:A:h}/.."
rm -rf build/marketing
mkdir -p build/marketing docs/media
build/DeskNames.app/Contents/MacOS/DeskNames --render-marketing "$PWD/build/marketing"
cp build/marketing/control-panel.png docs/media/control-panel.png
# One shared palette without dithering: frames differ only where content changes, so no
# faint trails are left behind (gifski's lossy frame reuse left visible ghosts).
ffmpeg -hide_banner -loglevel error -y -framerate 50 -i build/marketing/frame-%03d.png \
  -filter_complex '[0:v]split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle' \
  -loop 0 docs/media/panes-demo.gif
ffmpeg -hide_banner -loglevel error -y -framerate 50 -i build/marketing/frame-%03d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart docs/media/panes-demo.mp4

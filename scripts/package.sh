#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="dist/Transcriber.app/Contents"
mkdir -p "$out"/{MacOS,Helpers,Resources/Licenses} build/icon.iconset build/swift-cache
cp Resources/Info.plist "$out/"
cp Resources/Languages.txt Resources/Models.json "$out/Resources/"
swift -module-cache-path build/swift-cache scripts/icon.swift build/icon.iconset
python3 - "$out/Resources/Transcriber.icns" <<'PYICON'
from pathlib import Path
import struct, sys
chunks = []
for size, scale, kind in [(16,1,'icp4'),(32,1,'icp5'),(128,1,'ic07'),(256,1,'ic08'),(512,1,'ic09'),(16,2,'ic11'),(32,2,'ic12'),(128,2,'ic13'),(256,2,'ic14'),(512,2,'ic10')]:
    suffix = '@2x' if scale == 2 else ''
    png = Path(f'build/icon.iconset/icon_{size}x{size}{suffix}.png').read_bytes()
    chunks.append(struct.pack('>4sI', kind.encode(), len(png)+8) + png)
data = b''.join(chunks)
Path(sys.argv[1]).write_bytes(struct.pack('>4sI', b'icns', len(data)+8) + data)
PYICON
for arch in arm64 x86_64; do
    version=10.15
    [[ "$arch" == arm64 ]] && version=11.0
    swiftc -O -module-cache-path build/swift-cache -target "$arch-apple-macosx$version" src/*.swift -o "build/Transcriber-$arch"
done
lipo -create build/Transcriber-{arm64,x86_64} -output "$out/MacOS/Transcriber"
for tool in ffmpeg whisper-cli llama-cli; do
    cp "build/tools/$tool" "$out/Helpers/"
    codesign --force -s - "$out/Helpers/$tool"
done
cp build/vendor/whisper.cpp-1.7.5/LICENSE "$out/Resources/Licenses/whisper.cpp.txt"
cp build/vendor/llama.cpp-b4514/LICENSE "$out/Resources/Licenses/llama.cpp.txt"
cp build/vendor/ffmpeg-6.1.2/COPYING.LGPLv2.1 "$out/Resources/Licenses/ffmpeg.txt"
cp scripts/ffmpeg.sh "$out/Resources/Licenses/build-ffmpeg.sh"
codesign --force -s - dist/Transcriber.app
codesign --verify --deep --strict dist/Transcriber.app
ditto -c -k --sequesterRsrc --keepParent dist/Transcriber.app dist/Transcriber-Mac.zip

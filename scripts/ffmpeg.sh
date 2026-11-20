#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD/build"
mkdir -p "$root/vendor" "$root/tools"
archive="$root/vendor/ffmpeg.tar.xz"
[[ -f "$archive" ]] || curl -fL --retry 3 https://ffmpeg.org/releases/ffmpeg-6.1.2.tar.xz -o "$archive"
echo "3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b1442c63dca4e38  $archive" | shasum -a 256 -c -
src="$root/vendor/ffmpeg-6.1.2"
[[ -d "$src" ]] || tar xf "$archive" -C "$root/vendor"
for arch in x86_64 arm64; do
    mkdir -p "$root/ffmpeg-$arch"
    cd "$root/ffmpeg-$arch"
    target=10.15
    [[ "$arch" == arm64 ]] && target=11.0
    [[ -f config.h ]] || "$src/configure" --arch="$arch" --target-os=darwin --enable-cross-compile \
        --cc=clang --extra-cflags="-arch $arch -mmacosx-version-min=$target" --extra-ldflags="-arch $arch -mmacosx-version-min=$target" \
        --disable-everything --disable-autodetect --disable-network --disable-doc --disable-debug --disable-asm --disable-avdevice \
        --disable-videotoolbox --disable-audiotoolbox --disable-securetransport --disable-iconv --disable-ffplay --disable-ffprobe \
        --enable-ffmpeg --enable-protocol=file --enable-muxer=wav --enable-encoder=pcm_s16le \
        --enable-decoder='pcm_*,aac,alac,mp3*,flac,opus,vorbis,ac3,eac3,wmav2,wmav1' \
        --enable-demuxer='wav,aiff,mp3,mov,matroska,flac,ogg,aac,asf,caf,avi,mpegts,ac3' \
        --enable-parser='aac,ac3,flac,mpegaudio,opus,vorbis' --enable-filter='aresample,aformat,anull'
    make -j"${JOBS:-6}" ffmpeg
done
lipo -create "$root/ffmpeg-x86_64/ffmpeg" "$root/ffmpeg-arm64/ffmpeg" -output "$root/tools/ffmpeg"

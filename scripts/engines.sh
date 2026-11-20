#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
vendor="$PWD/build/vendor"
mkdir -p "$vendor" build/tools
fetch() {
    local name="$1" repo="$2" tag="$3" hash="$4"
    if [[ ! -f "$vendor/$name.tar.gz" ]]; then
        curl -fL --retry 3 "https://codeload.github.com/ggml-org/$repo/tar.gz/refs/tags/$tag" -o "$vendor/$name.partial"
        mv "$vendor/$name.partial" "$vendor/$name.tar.gz"
    fi
    echo "$hash  $vendor/$name.tar.gz" | shasum -a 256 -c -
    [[ -d "$vendor/$repo-${tag#v}" ]] || tar xzf "$vendor/$name.tar.gz" -C "$vendor"
}
fetch whisper whisper.cpp v1.7.5 2fda42b57b7b8427d724551bd041616d85401fb9382e42b0349132a28920a34f
fetch llama llama.cpp b4514 c7739973083314cd1e9528f34f75bab493120c2f001f9f8f8f2d7bc32537ddb2
if ! grep -q 'pcmf32.resize(frames_read)' "$vendor/whisper.cpp-1.7.5/examples/common-whisper.cpp"; then
    patch -d "$vendor/whisper.cpp-1.7.5" -p1 < scripts/whisper-stereo.patch
fi
for arch in x86_64 arm64; do
    target=10.15
    [[ "$arch" == arm64 ]] && target=11.0
    for tool in whisper-cli llama-cli; do
        dir="build/$tool-$arch"
        src="$vendor/whisper.cpp-1.7.5"
        [[ "$tool" == llama-cli ]] && src="$vendor/llama.cpp-b4514"
        cmake -S "$src" -B "$dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Darwin \
            -DCMAKE_SYSTEM_PROCESSOR="$arch" -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET="$target" \
            -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_METAL=OFF -DGGML_BLAS=OFF -DGGML_OPENMP=OFF \
            -DGGML_ACCELERATE=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF \
            -DGGML_LLAMAFILE=OFF -DGGML_CPU_ARM_ARCH=armv8-a -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DWHISPER_BUILD_TESTS=OFF
        cmake --build "$dir" --config Release --target "$tool" --parallel "${JOBS:-6}"
    done
done
for tool in whisper-cli llama-cli; do
    lipo -create "build/$tool-x86_64/bin/$tool" "build/$tool-arm64/bin/$tool" -output "build/tools/$tool"
done

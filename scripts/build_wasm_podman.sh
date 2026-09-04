#!/bin/bash
# Same steps as docker-compose.yml, for machines with podman instead of docker.
# --userns=keep-id keeps build output owned by the host user.
# SKIP_COMPAT=1 skips the wasm32/Asyncify (Safari) build, which doubles build time.
set -e

export EMSDK_IMAGE_TAG="4.0.20"
IMAGE="localhost/wllama-builder:${EMSDK_IMAGE_TAG}"

CURRENT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT="$(cd "$CURRENT_PATH/.." && pwd)"

if ! podman image exists "$IMAGE"; then
  podman build -t "$IMAGE" -f - "$ROOT" <<EOF
FROM docker.io/emscripten/emsdk:${EMSDK_IMAGE_TAG}
RUN apt update && apt install -y git
EOF
fi

podman run --rm --userns=keep-id \
  -v "$ROOT":/source:Z -w /source \
  -e SKIP_COMPAT="${SKIP_COMPAT:-}" -e WLLAMA_TEST_BACKEND="${WLLAMA_TEST_BACKEND:-}" \
  "$IMAGE" bash -c '
set -e
cd /source
mkdir -p build && cd build && mkdir -p emdawn
DAWN_TAG=v20260317.182325
EMDAWN_PKG="emdawnwebgpu_pkg-${DAWN_TAG}.zip"
EMDAWNWEBGPU_DIR="/source/build/emdawn/emdawnwebgpu_pkg"
if [ ! -d "$EMDAWNWEBGPU_DIR" ]; then
  echo "Downloading ${EMDAWN_PKG}"
  curl -sL -o emdawn.zip "https://github.com/google/dawn/releases/download/${DAWN_TAG}/${EMDAWN_PKG}"
  python3 -c "import zipfile; zf=zipfile.ZipFile(\"emdawn.zip\",\"r\"); zf.extractall(\"/source/build/emdawn\"); zf.close()"
fi

CMAKE_EXTRA_FLAGS="-DWLLAMA_TEST_BACKEND=OFF"
if [ -n "${WLLAMA_TEST_BACKEND}" ]; then
  CMAKE_EXTRA_FLAGS="-DWLLAMA_TEST_BACKEND=ON"
fi

emcmake cmake .. -DGGML_WEBGPU=ON -DGGML_WEBGPU_JSPI=ON -DEMDAWNWEBGPU_DIR="${EMDAWNWEBGPU_DIR}" ${CMAKE_EXTRA_FLAGS}
emmake make wllama -j$(nproc)
cd ..
mkdir -p src/wasm
cp build/wllama.js build/wllama.wasm src/wasm/

if [ -z "$SKIP_COMPAT" ]; then
  mkdir -p build-compat && cd build-compat
  emcmake cmake .. -DWLLAMA_COMPAT=ON -DLLAMA_WASM_MEM64=OFF -DGGML_WEBGPU=ON -DGGML_WEBGPU_JSPI=OFF -DEMDAWNWEBGPU_DIR="${EMDAWNWEBGPU_DIR}" ${CMAKE_EXTRA_FLAGS}
  emmake make wllama -j$(nproc)
  cd ..
  mkdir -p compat/wasm && cp build-compat/wllama.js build-compat/wllama.wasm compat/wasm/
fi

node scripts/build_source_map.js
ls -lh build/wllama.js build/wllama.wasm
'

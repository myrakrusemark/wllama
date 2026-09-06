#!/bin/bash
# Cut an engine release for Rankmark from a finished WASM build: bundle the
# worker and the ESM entry, gather the four assets, print their sha256s in the
# shape registry.json wants, and publish them as GitHub release engine-<sha>.
#
#   scripts/build_wasm_podman.sh      # first (SKIP_COMPAT=1 for the memory64 build only)
#   scripts/release_engine.sh         # then this; DRY=1 to stop before publishing
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then echo "working tree not clean; commit first" >&2; exit 1; fi
SHA="$(git rev-parse --short=7 HEAD)"
TAG="engine-${SHA}"
for f in src/wasm/wllama.wasm compat/wasm/wllama.js compat/wasm/wllama.wasm; do
  [ -f "$f" ] || { echo "missing $f: run the build first (without SKIP_COMPAT for the Safari build)" >&2; exit 1; }
done

npm run build:worker >/dev/null
npm run build:tsup >/dev/null

OUT="release/${TAG}"
rm -rf "$OUT" && mkdir -p "$OUT"
cp esm/index.js "$OUT/index.js"
cp src/wasm/wllama.wasm "$OUT/wllama.wasm"
cp compat/wasm/wllama.js "$OUT/compat-wllama.js"
cp compat/wasm/wllama.wasm "$OUT/compat-wllama.wasm"

echo "assets for registry.json (engine.commit: \"${SHA}\", release: .../releases/tag/${TAG}):"
python3 - "$OUT" <<'EOF'
import hashlib, json, os, sys
out = sys.argv[1]
paths = {"index.js": "wllama/index.js", "wllama.wasm": "wllama/wllama.wasm",
         "compat-wllama.js": "wllama-compat/wllama.js", "compat-wllama.wasm": "wllama-compat/wllama.wasm"}
assets = {}
for name, path in paths.items():
    h = hashlib.sha256(open(os.path.join(out, name), "rb").read()).hexdigest()
    assets[name] = {"path": path, "sha256": h}
    print(f"  {name:20s} {os.path.getsize(os.path.join(out, name)) / 1e6:6.1f} MB  {h}")
json.dump(assets, open(os.path.join(out, "assets.json"), "w"), indent=2)
EOF

if [ -n "$DRY" ]; then echo "DRY=1: not publishing"; exit 0; fi
gh release create "$TAG" "$OUT"/index.js "$OUT"/wllama.wasm "$OUT"/compat-wllama.js "$OUT"/compat-wllama.wasm \
  --repo myrakrusemark/wllama --title "$TAG" --notes "Rankmark engine build at ${SHA}: llama.cpp in WASM (memory64 and compat), with raw_eval, kv_shift, tokenize, detokenize and vocab actions."
echo "published ${TAG}"

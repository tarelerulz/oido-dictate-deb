#!/bin/sh
# Assemble the upstream payload (code + prebuilt binaries, NO model weights) from
# the working ~/oido-dictate into ./upstream/, ready for dpkg-buildpackage.
# Re-run whenever the worker or the GPU kit changes.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="${OIDO_SRC:-$HOME/oido-dictate}"
INJECT="${OIDO_INJECT:-$HOME/moonshine-v2/inject.py}"
UP="$HERE/upstream"

[ -f "$SRC/oido_worker.py" ] || { echo "no oido_worker.py under $SRC (set OIDO_SRC)"; exit 1; }

rm -rf "$UP"
mkdir -p "$UP/bin"

cp "$SRC/oido_worker.py"  "$UP/"
cp "$SRC/punct_server.py" "$UP/"
cp "$INJECT"              "$UP/inject.py"
# All CPU binaries in bin/ (tasr_cli_a72_static + tasr_lmdecode_static today; add
# tasr_cli_dotprod_static / tasr_lmdecode_dotprod_static for Pi 5 and they are
# packaged automatically and chosen at runtime by CPU feature).
cp "$SRC"/bin/tasr_cli_*_static "$SRC"/bin/tasr_lmdecode_*static "$UP/bin/" 2>/dev/null || true

# GPU kit, minus the large generated model blob (built on first run) and dev-only
# bulk. Keep tools/ binaries, shaders/, gpuport/, work/speech-app-shaders, etc.
cp -a "$SRC/gpu-port-kit" "$UP/gpu-port-kit"
rm -f  "$UP/gpu-port-kit/work/nemo8_kit.bin" "$UP/gpu-port-kit/work/nemo8_kit.json"
rm -rf "$UP/gpu-port-kit/.git" "$UP/gpu-port-kit/tests" "$UP/gpu-port-kit/patches"

chmod +x "$UP/bin/"* 2>/dev/null || true

echo "Assembled upstream payload in $UP"
du -sh "$UP" "$UP/gpu-port-kit" 2>/dev/null || true
echo "Model weights are intentionally excluded (fetched on first run)."

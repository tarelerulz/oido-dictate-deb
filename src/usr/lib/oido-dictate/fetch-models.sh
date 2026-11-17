#!/bin/sh
# Download the Oido models. Idempotent, checksum-verified, resumable.
#
#   fetch-models.sh cpu      # nemo8.tnm, nemo_lm.tlm, punctuation model (default)
#   fetch-models.sh gpu      # nothing extra (the GPU blob is built on first run)
#   fetch-models.sh check    # verify what is on disk; never touches the network
#
# Exit status: 0 = everything present and verified, 1 = something missing/failed.
# NEMO8_URL/NEMO_LM_URL point at lokutor-ai/oido-ctc-small-int8 (CC-BY-4.0,
# see debian/copyright). Override URLs with env vars to use a mirror; then also
# set the matching *_SHA256 (or OIDO_SKIP_SHA=1 to skip verification).
# OIDO_MODELS_DIR picks the destination.

WHICH="${1:-cpu}"

DEST="${OIDO_MODELS_DIR:-/var/lib/oido-dictate/models}"
if [ "$WHICH" = check ] && [ -d "$DEST" ]; then
  :   # check never writes: use the directory as is, even if read-only for this user
elif ! ( mkdir -p "$DEST" 2>/dev/null && [ -w "$DEST" ] ); then
  DEST="${XDG_CACHE_HOME:-$HOME/.cache}/oido-dictate/models"
  mkdir -p "$DEST" || { echo "fetch-models: cannot create $DEST" >&2; exit 1; }
fi

HF=https://huggingface.co/lokutor-ai/oido-ctc-small-int8/resolve/main
NEMO8_URL="${NEMO8_URL:-$HF/nemo8.tnm}"
NEMO8_SHA256="${NEMO8_SHA256:-452e332e21f46f161e383a1f26f36294785b2782cb3252928841dd7e6480c68b}"
NEMO_LM_URL="${NEMO_LM_URL:-$HF/nemo_lm.tlm}"
NEMO_LM_SHA256="${NEMO_LM_SHA256:-00f174f83ad70d865301304fd51897839c542d6f887f8e93e4e1b83938566a1f}"
PUNCT_URL="${PUNCT_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-online-punct-en-2024-08-06.tar.bz2}"
PUNCT_SHA256="${PUNCT_SHA256:-9f5e5a72c7d2829635bd074fce92b6bbd5b78da8a52e7ad8ed1be933f366b99d}"

FAILED=0
say()  { echo "fetch-models: $*"; }
warn() { echo "fetch-models: $*" >&2; }

sha_ok() {  # file expected
  [ "${OIDO_SKIP_SHA:-0}" = 1 ] && return 0
  [ -z "$2" ] && return 0
  got=$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)
  [ "$got" = "$2" ]
}

online() {
  if command -v curl >/dev/null 2>&1; then
    curl -sI --max-time 8 -o /dev/null https://huggingface.co
  else
    wget -q --spider --timeout=8 https://huggingface.co
  fi
}

download() {  # url out.part   (resumes a partial file)
  if command -v curl >/dev/null 2>&1; then
    if [ -t 2 ]; then q="--progress-bar"; else q="-sS"; fi
    curl -fL $q --retry 3 --retry-delay 2 --connect-timeout 15 -C - -o "$2" "$1"
  else
    wget -q -c -t 3 -T 15 -O "$2" "$1"
  fi
}

# fetch_file url out sha
fetch_file() {
  url="$1"; out="$2"; sha="$3"; name=$(basename "$out")
  if [ -s "$out" ]; then
    if sha_ok "$out" "$sha"; then return 0; fi
    warn "$name is on disk but its checksum is wrong; removing it and downloading again"
    rm -f "$out"
  fi
  [ "$WHICH" = check ] && { warn "MISSING: $name"; FAILED=1; return 0; }
  say "downloading $name"
  attempt=1
  while [ $attempt -le 2 ]; do
    if download "$url" "$out.part" && sha_ok "$out.part" "$sha"; then
      mv "$out.part" "$out"; say "$name OK (checksum verified)"; return 0
    fi
    # a resumed partial can be corrupt: second attempt starts from scratch
    rm -f "$out.part"
    attempt=$((attempt + 1))
  done
  if online; then
    warn "FAILED: could not download a valid $name from $url"
  else
    warn "FAILED: no internet connection. Connect, then run:  oido-fetch-models"
  fi
  FAILED=1
}

fetch_punct() {
  dir="$DEST/sherpa-onnx-online-punct-en"
  if [ -s "$dir/model.int8.onnx" ]; then return 0; fi
  [ "$WHICH" = check ] && { warn "MISSING: punctuation model (dictation still works without it)"; FAILED=1; return 0; }
  tmp="$DEST/punct.tar.bz2"
  say "downloading punctuation model"
  attempt=1; got=0
  while [ $attempt -le 2 ]; do
    if download "$PUNCT_URL" "$tmp.part" && sha_ok "$tmp.part" "$PUNCT_SHA256"; then got=1; break; fi
    rm -f "$tmp.part"; attempt=$((attempt + 1))
  done
  if [ $got != 1 ]; then
    if online; then warn "FAILED: punctuation model download invalid"; else warn "FAILED: no internet connection. Connect, then run:  oido-fetch-models"; fi
    FAILED=1; return 0
  fi
  mv "$tmp.part" "$tmp"
  if tar xjf "$tmp" -C "$DEST"; then
    d=$(find "$DEST" -maxdepth 1 -type d -name 'sherpa-onnx-online-punct-en-*' | head -1)
    [ -n "$d" ] && { rm -rf "$dir"; mv "$d" "$dir"; }
    say "punctuation model OK"
  else
    warn "FAILED: could not unpack the punctuation model"; FAILED=1
  fi
  rm -f "$tmp"
}

case "$WHICH" in
  cpu|check|all|gpu) ;;
  *) warn "usage: $0 [cpu|gpu|check]"; exit 2 ;;
esac

# The GPU blob (nemo8_kit.bin) is derived from nemo8.tnm and built on the first
# GPU run into GPUPORT_WORK, so the GPU mode needs the same CPU models.
fetch_file "$NEMO8_URL"   "$DEST/nemo8.tnm"   "$NEMO8_SHA256"
fetch_file "$NEMO_LM_URL" "$DEST/nemo_lm.tlm" "$NEMO_LM_SHA256"
fetch_punct

if [ $FAILED = 0 ]; then say "models OK in $DEST"; exit 0; fi
warn "some models are missing or invalid in $DEST (run 'oido-doctor' to see what works)"
exit 1

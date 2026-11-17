# Packaging oido-dictate (CPU base + GPU add-on)

> Debian packages for the [oido](https://github.com/lokutor-ai/oido) dictation engine on Raspberry Pi OS (arm64).
> Download the `.deb` files and `SHA256SUMS` from the Releases page, then `sha256sum -c SHA256SUMS`.
> Copy them to `/tmp` before `apt install` to avoid a harmless `_apt ... Permission denied` notice.

Two binary packages from one source tree:

| package | arch | what it is |
|---|---|---|
| `oido-dictate` | arm64 | Speak window + worker + punctuation + the **CPU** engine (static `tasr_cli` + LM). Runs on any arm64. |
| `oido-dictate-gpu` | arm64 | Add-on: the **V3D 4.2 GPU** engine (Pi 4 / 400 / CM4). `Depends: oido-dictate`. Enables `oido-gpu-lm`/`oido-gpu` and makes them the default. |

The GPU package only *adds* files; everything shared (window, worker, punctuation,
CPU fallback) lives in the base. The Speak window detects at launch whether the
GPU kit is installed and whether the board has a V3D 4.2 GPU (`oido-gpu-detect`),
and shows the right engines.

## Layout once installed

```
/opt/oido-dictate/        oido_worker.py, punct_server.py, inject.py, stt.py, bin/, venv/
/opt/oido-dictate/gpu-port-kit/   (gpu package only)
/usr/bin/oido-speak              launcher (sets paths, runs the venv python)
/usr/bin/oido-gpu-detect         "is this a V3D 4.2 GPU?" (exit 0/1)
/usr/lib/oido-dictate/fetch-models.sh
/var/lib/oido-dictate/models/    downloaded weights (or ~/.cache/oido-dictate/models)
~/.cache/oido-dictate/gpu-work/  generated GPU model cache (nemo8_kit.bin)
```

## Build

```sh
cd ~/oido-deb
./assemble-upstream.sh            # pulls code+binaries from ~/oido-dictate (no models)
dpkg-buildpackage -us -uc -b      # -> ../oido-dictate_0.1.0_arm64.deb
                                  #    ../oido-dictate-gpu_0.1.0_arm64.deb
```

Build host needs: `dpkg-dev debhelper` (`sudo apt install build-essential debhelper devscripts`).

## Install / use

```sh
sudo apt install ./oido-dictate_0.1.0_arm64.deb              # everyone
sudo apt install ./oido-dictate-gpu_0.1.0_arm64.deb          # Pi 4/400 only, for the GPU path
oido-speak                                                   # or the "Speak" app icon
```

## Known limitations

1. **Models are downloaded, not bundled.** `fetch-models.sh` pulls the Oido weights
   (`lokutor-ai/oido-ctc-small-int8` on Hugging Face) and the sherpa-onnx punctuation model,
   and checks SHA256. See `debian/copyright` for the model licenses.
2. **Internet at install.** `postinst` builds a venv and `pip install`s `sounddevice` and
   `sherpa-onnx`, and fetches models. Offline installs still succeed but print how to finish later.
3. **GPU engine is Pi 4 / 400 / CM4 only** (V3D 4.2). `oido-gpu-detect` gates it; on a Pi 5 or
   other arm64 board the CPU engine is used automatically. The Pi 5 build (dot-product
   `tasr_cli`) has only been run on an ARM phone VM, not on a Pi 5.
4. **GPU model blob** `nemo8_kit.bin` is generated from `nemo8.tnm` on the first GPU run. If that
   fails, the worker falls back to the CPU engine per phrase.
5. **Maintainer** in `debian/control` is a placeholder address.

## Helper commands

- `oido-fetch-models [cpu|check]` — downloads the weights with SHA256 verification, resumes partial
  downloads, replaces a corrupt file, and says clearly when there is no internet. `check` never uses
  the network. Exit status 0 only when everything is present and verified.
- `oido-doctor [--quick]` — reports board, CPU build chosen (dotprod/NEON), GPU support, models,
  python modules, microphone, typing tool, then runs a 2 s self-test of the engine. Exit 1 if
  dictation cannot work.

## Env knobs (all optional)

`SPEAK_DEFAULT`, `OIDO_MODEL`, `OIDO_LM`, `OIDO_KIT`, `OIDO_PUNCT`, `OIDO_PUNCT_MODEL`,
`OIDO_PUNCT_PY`, `OIDO_PARTIALS`, `OIDO_PARTIAL_EVERY`, `OIDO_AUTO_PERIOD`,
`GPUPORT_WORK`, `OIDO_MIC`, `OIDO_SILENCE`.

## Testing notes

Packages: `oido-dictate_0.1.0_arm64.deb` (CPU base) and `oido-dictate-gpu_0.1.0_arm64.deb` (GPU add-on).

```
dede2fa88c5180818d71d3150c149a92313ed42efcff11d582b2d244ec3ad58b  oido-dictate_0.1.0_arm64.deb
494672886f313ffb67c726b49cba458f1a60fe481ad37e8f5b7824a1b17f6b9c  oido-dictate-gpu_0.1.0_arm64.deb
```

### What was tested

Test machine: Raspberry Pi 400 (arm64), fresh Raspberry Pi OS install, packages copied over on a USB drive.

| Check | Result |
|---|---|
| `oido-dictate` installs on a clean system | Pass |
| Model files in `/var/lib/oido-dictate/models` match the checksums in `fetch-models.sh` | Pass |
| `oido-doctor` engine self-test (transcribes a built-in clip) | Pass (105 ms) |
| `oido-dictate-gpu` installs and the GPU engine runs | Pass (rebuilt debs, clean reinstall) |
| Contents of the final debs include both fixes below | Pass (unpacked and checked) |

### Bugs found by the clean-install test (fixed in 0.1.0)

- **False "checksum check not clean" warning.** `fetch-models.sh check` fell back to
  `~/.cache/oido-dictate/models` when run as a normal user, found nothing, and reported
  every model missing. Check mode now uses the system model directory if it exists.
- **GPU engine never started on a clean machine.** The GPU kit looked for `nemo_ref.py`
  in the author's `~/speech-app/port`. `oido_worker.py` now sets `GPUPORT_SPEECH_APP`
  to the kit's bundled `port/` directory.

### Not tested yet

- Dictation with a real microphone on the fresh install. The first test machine had no
  mic, so `oido-doctor` correctly reported `[FAIL] no microphone`.
- Removing and purging the packages (`apt remove` / `apt purge`).
- Raspberry Pi 5. The static dot-product build of `tasr_cli` was checked on an ARM
  phone VM only (same text output as the baseline, 1.2 to 2.0x less CPU time).
- Long-run GPU thermals and stability.
- GPU engine speed on the fresh install. Benchmarks come from the author's development
  Pi 400, not from this install.

### Harmless messages

- When installing a `.deb` from your home directory, apt prints
  `Download is performed unsandboxed as root ... _apt ... Permission denied`.
  This is only a notice. Copy the file to `/tmp` before installing to avoid it.
- `oido-doctor` warns `install oido-dictate-gpu` until the GPU package is installed.
  It is expected.

### Worker errors

GPU worker errors appear only in the Speak window status line. There is no log file yet.

## License

GPL-3.0-or-later (see `LICENSE`), the same license as [lokutor-ai/oido](https://github.com/lokutor-ai/oido), whose code the packaged binaries are built from. Model weights are not included and keep their own licenses (see `debian/copyright`).

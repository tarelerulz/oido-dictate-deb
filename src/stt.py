#!/usr/bin/env python3
"""Packaged "Speak" dictation window for oido-dictate.

Floating always-on-top toggle: click START, then click where you want text and
talk; each finished phrase is typed into the focused window. Which engines appear
depends on what is installed:

  * base (oido-dictate):        oido-cpu only
  * + GPU add-on on a Pi 4/400: oido-gpu-lm (default), oido-hybrid, oido-gpu, oido-cpu

Paths come from the package layout under /opt/oido-dictate and from the OIDO_*
environment set by the `oido-speak` launcher. Override the default engine with
SPEAK_DEFAULT.
"""
import os
import signal
import subprocess
import threading
import queue
import tkinter as tk
from tkinter import font as tkfont

PREFIX = os.environ.get("OIDO_PREFIX", "/opt/oido-dictate")
VENV_PY = os.path.join(PREFIX, "venv", "bin", "python")
if not os.path.exists(VENV_PY):
    import sys
    VENV_PY = sys.executable            # dev fallback
WORKER = os.path.join(PREFIX, "oido_worker.py")
WORKDIR = PREFIX
EXEC_HYBRID = os.path.join(PREFIX, "gpu-port-kit", "tools", "exec_hybrid")


def gpu_available():
    """True when the GPU add-on is installed AND this box has a V3D 4.2 GPU."""
    if not os.path.exists(EXEC_HYBRID):
        return False
    try:
        return subprocess.run(["oido-gpu-detect", "-q"]).returncode == 0
    except FileNotFoundError:
        return True                     # kit present but no detector: let it try


if gpu_available():
    MODELS = ["oido-gpu-lm", "oido-hybrid", "oido-gpu", "oido-cpu"]
    DEFAULT_MODEL = "oido-gpu-lm"
else:
    MODELS = ["oido-cpu"]
    DEFAULT_MODEL = "oido-cpu"
DEFAULT_MODEL = os.environ.get("SPEAK_DEFAULT", DEFAULT_MODEL)
if DEFAULT_MODEL not in MODELS:
    DEFAULT_MODEL = MODELS[0]

ENV = dict(os.environ)
ENV.setdefault("WAYLAND_DISPLAY", "wayland-0")
ENV.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())


class App:
    def __init__(self, root):
        self.root = root
        self.proc = None
        self.q = queue.Queue()
        self.model = tk.StringVar(value=DEFAULT_MODEL)

        root.title("Speak")
        root.geometry("260x118+1630+40")
        root.resizable(False, False)
        root.attributes("-topmost", True)
        root.configure(bg="#1e1e24")
        root.protocol("WM_DELETE_WINDOW", self.on_close)

        big = tkfont.Font(family="DejaVu Sans", size=15, weight="bold")

        self.btn = tk.Button(
            root, text="●  START", font=big, command=self.toggle,
            bg="#2d7d46", fg="white", activebackground="#2d7d46",
            activeforeground="white", relief="flat", bd=0, height=2,
        )
        self.btn.pack(fill="x", padx=8, pady=(8, 4))

        bar = tk.Frame(root, bg="#1e1e24")
        bar.pack(fill="x", padx=8)
        tk.Label(bar, text="engine", bg="#1e1e24", fg="#9aa0a6").pack(side="left")
        om = tk.OptionMenu(bar, self.model, *MODELS)
        om.configure(bg="#2a2a33", fg="white", highlightthickness=0,
                     activebackground="#2a2a33", relief="flat")
        om["menu"].configure(bg="#2a2a33", fg="white")
        om.pack(side="left", padx=4)

        self.status = tk.Label(
            root, text="off — click START, then click where you want text",
            bg="#1e1e24", fg="#9aa0a6", anchor="w", justify="left", wraplength=244,
        )
        self.status.pack(fill="x", padx=8, pady=(4, 8))

        self.root.after(120, self.drain)

    def toggle(self):
        if self.proc is None:
            self.start()
        else:
            self.stop()

    def start(self):
        try:
            self.proc = subprocess.Popen(
                [VENV_PY, WORKER, self.model.get()],
                cwd=WORKDIR, env=ENV,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1, start_new_session=True,
            )
        except Exception as e:
            self.set_status("could not start: %s" % e)
            return
        threading.Thread(target=self.reader, args=(self.proc,), daemon=True).start()
        self.btn.configure(text="■  STOP", bg="#b3261e", activebackground="#b3261e")
        self.set_status("loading model…")

    def stop(self):
        p, self.proc = self.proc, None
        if p and p.poll() is None:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGINT)
                p.wait(timeout=4)
            except Exception:
                try:
                    os.killpg(os.getpgid(p.pid), signal.SIGTERM)
                except Exception:
                    pass
        self.btn.configure(text="●  START", bg="#2d7d46", activebackground="#2d7d46")
        self.set_status("off — click START, then click where you want text")

    def reader(self, p):
        for line in p.stdout:
            self.q.put(line.rstrip("\n"))
        self.q.put("__EXIT__")

    def drain(self):
        try:
            while True:
                self.handle(self.q.get_nowait())
        except queue.Empty:
            pass
        self.root.after(120, self.drain)

    def handle(self, line):
        if line == "__EXIT__":
            if self.proc is None:
                return
            self.set_status("engine stopped unexpectedly")
            self.btn.configure(text="●  START", bg="#2d7d46", activebackground="#2d7d46")
            self.proc = None
            return
        tag, _, txt = line.partition("\t")
        if tag == "READY":
            self.set_status("listening — talk now", "#8ab4f8")
        elif tag == "PARTIAL":
            if txt:
                self.set_status("… " + txt[-80:], "#8ab4f8")
        elif tag == "FINAL":
            self.set_status("typed: " + txt[-80:], "#81c995")
        elif tag == "ERROR":
            self.set_status("error: " + txt[-120:], "#f28b82")

    def set_status(self, text, color="#9aa0a6"):
        self.status.configure(text=text, fg=color)

    def on_close(self):
        try:
            self.stop()
        except Exception:
            pass
        self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()

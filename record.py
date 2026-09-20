#!/usr/bin/env python3
"""
record.py - record one fishing cycle so you can find your pixels off a still

Fish a single cycle by hand with this running. It saves the frames and zips
them. Open the zip, scrub to the frame where the charge bar is perfect, and
read the coordinate and colour straight off it - much easier than trying to
hover the right pixel while the bar is moving.

    pip install mss numpy pillow pynput
    python record.py

    F8   start / stop recording
    ESC  quit

Frames are half size, sampled nearest-neighbour, so every colour in them is a
real captured colour and not a blend of its neighbours. Coordinates in a frame
are exactly half your screen coordinates - double them before you put them in
FishIt.ini.
"""

import os
import shutil
import sys
import time
import zipfile

import numpy as np
import mss
from PIL import Image
from pynput import keyboard

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "capture")
FPS = 4
MAX_SECONDS = 25

STATE = {"rec": False, "alive": True}


def on_press(key):
    if key == keyboard.Key.f8:
        STATE["rec"] = not STATE["rec"]
        print("\n>>> RECORDING" if STATE["rec"] else "\n>>> STOPPED")
    elif key == keyboard.Key.esc:
        STATE["rec"] = False
        STATE["alive"] = False
        return False


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)

    listener = keyboard.Listener(on_press=on_press)
    listener.start()

    print(__doc__)
    print("Ready. Click into the game.\n")
    print("  1. Press F8")
    print("  2. Cast and hold, let the bar charge, release")
    print("  3. Let the Click Fast prompt appear")
    print("  4. Click it manually until the fish is caught")
    print("  5. Press F8 again\n")

    n = 0
    interval = 1.0 / FPS

    with mss.mss() as sct:
        mon = sct.monitors[1]
        print(f"Screen: {mon['width']}x{mon['height']}\n")

        while STATE["alive"]:
            if not STATE["rec"]:
                time.sleep(0.05)
                continue

            t = time.time()
            raw = np.array(sct.grab(mon))[:, :, :3][:, :, ::-1]
            # nearest-neighbour halving keeps colours exact
            small = raw[::2, ::2]
            Image.fromarray(small).save(
                os.path.join(OUT, f"f{n:04d}.png"), compress_level=6)
            n += 1
            print(f"\r  {n} frames ({n/FPS:.1f}s)", end="", flush=True)

            if n >= FPS * MAX_SECONDS:
                STATE["rec"] = False
                print("\n>>> hit the time limit, stopped")

            time.sleep(max(0, interval - (time.time() - t)))

    listener.stop()

    if n == 0:
        print("\nNo frames captured.")
        return

    zpath = os.path.join(os.path.dirname(OUT), "capture.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(os.listdir(OUT)):
            z.write(os.path.join(OUT, f), f)

    mb = os.path.getsize(zpath) / 1e6
    print(f"\n\nSaved {n} frames -> {zpath}  ({mb:.1f} MB)")
    print("Open it and find the frame you want.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
fishbot.py - prompt-driven fishing macro

Instead of guessing how many clicks the prompt needs, this watches a small
region of the screen and clicks only while the prompt is actually visible.
The instant it disappears, clicking stops. That removes the stray clicks that
were re-casting your rod, and it handles a randomized click count for free.

Install:
    pip install mss numpy pynput pydirectinput

Usage:
    python fishbot.py calibrate    # teach it what the prompt looks like
    python fishbot.py test         # live detector readout - tune here first
    python fishbot.py run          # F2 start/stop, F4 quit

Run the game in BORDERLESS WINDOWED. Exclusive fullscreen usually captures
as a black frame and nothing will ever be detected.
"""

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass, asdict, field

import numpy as np
import mss
from pynput import keyboard
from pynput.mouse import Controller as MouseController, Button

# pydirectinput sends scancode-level input that most games accept.
# pynput's mouse events are ignored by some anti-cheat / input layers.
try:
    import pydirectinput
    pydirectinput.PAUSE = 0
    pydirectinput.FAILSAFE = False
    HAVE_DI = True
except ImportError:
    HAVE_DI = False

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fishbot_config.json")
_mouse = MouseController()


# --------------------------------------------------------------------------
# config
# --------------------------------------------------------------------------

@dataclass
class Config:
    # detection
    region: list = field(default_factory=lambda: [0, 0, 60, 60])  # left, top, w, h
    color: list = field(default_factory=lambda: [255, 255, 255])  # RGB of the prompt
    tolerance: int = 30          # per-channel match slack
    threshold: float = 0.10      # fraction of region pixels that must match

    # timing (ms)
    cast_hold_ms: int = 467      # your timed cast
    post_cast_grace_ms: int = 700   # ignore the screen right after casting
    prompt_timeout_ms: int = 9000   # give up waiting for a prompt
    click_interval_ms: int = 80     # 12.5 clicks/sec
    max_click_ms: int = 8000        # hard stop so a false positive can't spin
    confirm_frames: int = 2         # consecutive misses before "prompt gone"
    settle_ms: int = 1500           # after prompt clears, before next cast

    def save(self, path=CONFIG_PATH):
        with open(path, "w") as f:
            json.dump(asdict(self), f, indent=2)

    @classmethod
    def load(cls, path=CONFIG_PATH):
        if not os.path.exists(path):
            sys.exit("No config found. Run:  python fishbot.py calibrate")
        with open(path) as f:
            return cls(**json.load(f))


# --------------------------------------------------------------------------
# detection
# --------------------------------------------------------------------------

def grab(sct, region):
    left, top, w, h = region
    raw = sct.grab({"left": left, "top": top, "width": w, "height": h})
    # mss gives BGRA; drop alpha and flip to RGB
    return np.array(raw)[:, :, :3][:, :, ::-1].astype(np.int16)


def coverage(frame, color, tolerance):
    """Fraction of pixels within `tolerance` of `color` on every channel."""
    diff = np.abs(frame - np.array(color, dtype=np.int16))
    return float(np.mean(np.max(diff, axis=2) <= tolerance))


def prompt_visible(sct, cfg):
    return coverage(grab(sct, cfg.region), cfg.color, cfg.tolerance) >= cfg.threshold


# --------------------------------------------------------------------------
# input
# --------------------------------------------------------------------------

def mouse_down():
    if HAVE_DI:
        pydirectinput.mouseDown()
    else:
        _mouse.press(Button.left)


def mouse_up():
    if HAVE_DI:
        pydirectinput.mouseUp()
    else:
        _mouse.release(Button.left)


def click():
    mouse_down()
    time.sleep(0.015)
    mouse_up()


def cast(cfg):
    mouse_down()
    time.sleep(cfg.cast_hold_ms / 1000)
    mouse_up()


# --------------------------------------------------------------------------
# calibrate
# --------------------------------------------------------------------------

def calibrate(args):
    half = args.box // 2
    state = {"present": None, "absent": None, "point": None, "quit": False}

    def snap(sct):
        x, y = _mouse.position
        region = [int(x) - half, int(y) - half, args.box, args.box]
        return region, grab(sct, region)

    print(f"""
Calibration - two samples.

  1. Get the click prompt on screen. Put your mouse over the middle of it
     and press F8.  (You have as long as you need; retrigger a cast if the
     prompt vanishes before you're ready.)
  2. Let the prompt disappear. WITHOUT MOVING THE MOUSE, press F9.
  3. F10 to save and exit.

Sampling a {args.box}x{args.box} box around the cursor.
""")

    with mss.mss() as sct:
        def on_press(key):
            if key == keyboard.Key.f8:
                region, frame = snap(sct)
                c = frame[half - 2:half + 3, half - 2:half + 3].reshape(-1, 3)
                state["point"] = region
                state["present"] = frame
                state["color"] = np.median(c, axis=0).astype(int).tolist()
                print(f"  [F8] prompt sample taken at {region[:2]}, color={state['color']}")
            elif key == keyboard.Key.f9:
                if state["present"] is None:
                    print("  [F9] take the F8 sample first")
                    return
                _, frame = snap(sct)
                state["absent"] = frame
                print("  [F9] background sample taken")
            elif key == keyboard.Key.f10:
                state["quit"] = True
                return False

        with keyboard.Listener(on_press=on_press) as listener:
            listener.join()

    if state["present"] is None or state["absent"] is None:
        sys.exit("Need both samples. Nothing saved.")

    color = state["color"]
    cfg = Config()
    cfg.region = state["point"]
    cfg.color = color

    # pick the tolerance that separates the two samples best
    best = None
    for tol in range(10, 81, 5):
        cov_p = coverage(state["present"], color, tol)
        cov_a = coverage(state["absent"], color, tol)
        gap = cov_p - cov_a
        if best is None or gap > best[0]:
            best = (gap, tol, cov_p, cov_a)

    gap, tol, cov_p, cov_a = best
    cfg.tolerance = tol
    cfg.threshold = round((cov_p + cov_a) / 2, 3)

    print(f"\n  region     {cfg.region}")
    print(f"  color      {cfg.color}")
    print(f"  tolerance  {cfg.tolerance}")
    print(f"  prompt on  {cov_p:.0%} coverage")
    print(f"  prompt off {cov_a:.0%} coverage")
    print(f"  threshold  {cfg.threshold:.0%}")

    if gap < 0.15:
        print("\n  WARNING: the two samples look too similar. Detection will be"
              "\n  unreliable. Re-run and aim at a part of the prompt with a"
              "\n  color that isn't in the background behind it.")

    cfg.save()
    print(f"\nSaved to {CONFIG_PATH}\nNow run:  python fishbot.py test")


# --------------------------------------------------------------------------
# test
# --------------------------------------------------------------------------

def test(args):
    cfg = Config.load()
    print(f"Watching {cfg.region}  color={cfg.color}  tol={cfg.tolerance}  "
          f"threshold={cfg.threshold:.0%}\nCtrl+C to stop.\n")
    try:
        with mss.mss() as sct:
            while True:
                cov = coverage(grab(sct, cfg.region), cfg.color, cfg.tolerance)
                hit = cov >= cfg.threshold
                bar = "#" * int(cov * 40)
                print(f"\r  {cov:6.1%} |{bar:<40}| "
                      f"{'PROMPT' if hit else '  --  '}", end="", flush=True)
                time.sleep(0.05)
    except KeyboardInterrupt:
        print("\n")


# --------------------------------------------------------------------------
# run
# --------------------------------------------------------------------------

def wait_for_prompt(sct, cfg):
    deadline = time.time() + cfg.prompt_timeout_ms / 1000
    while time.time() < deadline:
        if not STATE["running"]:
            return False
        if prompt_visible(sct, cfg):
            return True
        time.sleep(0.02)
    return False


def click_through_prompt(sct, cfg):
    """Click while the prompt is up. Stop the moment it clears."""
    deadline = time.time() + cfg.max_click_ms / 1000
    misses = 0
    clicks = 0
    while time.time() < deadline and STATE["running"]:
        if prompt_visible(sct, cfg):
            misses = 0
        else:
            misses += 1
            if misses >= cfg.confirm_frames:
                return clicks, "cleared"
            time.sleep(0.01)
            continue
        click()
        clicks += 1
        time.sleep(cfg.click_interval_ms / 1000)
    return clicks, "timeout"


STATE = {"running": False, "alive": True}


def run(args):
    cfg = Config.load()

    if not HAVE_DI:
        print("NOTE: pydirectinput not installed - falling back to pynput clicks,\n"
              "      which some games ignore.  pip install pydirectinput\n")

    def on_press(key):
        if key == keyboard.Key.f2:
            STATE["running"] = not STATE["running"]
            print(f"\n>>> {'STARTED' if STATE['running'] else 'STOPPED'}")
        elif key == keyboard.Key.f4:
            STATE["running"] = False
            STATE["alive"] = False
            return False

    listener = keyboard.Listener(on_press=on_press)
    listener.start()

    print("F2 = start/stop     F4 = quit\nWaiting...\n")

    cycle = 0
    with mss.mss() as sct:
        while STATE["alive"]:
            if not STATE["running"]:
                time.sleep(0.1)
                continue

            cycle += 1
            t0 = time.time()

            cast(cfg)
            time.sleep(cfg.post_cast_grace_ms / 1000)

            if not wait_for_prompt(sct, cfg):
                if STATE["running"]:
                    print(f"  [{cycle:>4}] no prompt within "
                          f"{cfg.prompt_timeout_ms}ms - recasting")
                continue

            clicks, why = click_through_prompt(sct, cfg)
            print(f"  [{cycle:>4}] {clicks:>3} clicks, {why}, "
                  f"{time.time() - t0:.1f}s")

            if why == "timeout":
                print("         prompt never cleared - check your calibration")

            time.sleep(cfg.settle_ms / 1000)

    listener.stop()
    print("\nStopped.")


# --------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("calibrate", help="teach it the prompt's color")
    c.add_argument("--box", type=int, default=60, help="sample box size in px")
    c.set_defaults(func=calibrate)

    t = sub.add_parser("test", help="live detector readout")
    t.set_defaults(func=test)

    r = sub.add_parser("run", help="run the macro")
    r.set_defaults(func=run)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

# PixelCast

Two fishing macros that work off screen pixels instead of fixed timings. One's
AutoHotkey, one's Python. The AHK one is the one I actually use.

Both do the same thing: hold the cast until the charge bar hits the right
colour, let go, then watch for the click prompt and click until it's gone.
Watching for the prompt instead of clicking a set number of times is the whole
point. The count is randomised, and the leftover clicks were re-casting my rod
halfway through a reel.

## Heads up

Macros break the rules in most games and you can get banned for using one.
That's on you, not me.

## FishIt.ahk, the main one

Needs [AutoHotkey v1.1](https://www.autohotkey.com/). Nothing else.

Double-click the script and a small always-on-top window shows up with the
stats and a key list. Then:

1. Start a cast so the charge bar is on screen. Put your mouse on the bar at
   the point where the cast is perfect and press F1.
2. Get the reel prompt up. Hover the red stop button and press F2.
3. Press F3 for the live monitor and fish one cycle by hand while you watch
   the two readouts. If they don't light up at the right moments your pixels
   are wrong, so redo F1 and F2.
4. F8 to start.

Calibration saves to `FishIt.ini` next to the script, so you only do it once
per resolution. Delete the ini to start over.

### Keys

| Key | What it does |
| --- | --- |
| F1 | Set the cast pixel (hover first, then press) |
| F2 | Set the reel pixel |
| F3 | Live monitor on / off |
| F6 / Shift+F6 | Cast tolerance up / down |
| F7 / Shift+F7 | Reel tolerance up / down |
| F8 | Start / pause |
| F9 | Reset the stats |
| Esc | Quit |

### When it misfires

Tolerance is how far off the colour is allowed to be and still count as a
match. Mine sits at 45 for the cast and 60 for the reel.

It never casts, or casts instantly: cast tolerance is too tight or too loose.
F6 and Shift+F6 with the live monitor on.

It keeps clicking after the fish is caught: reel tolerance is too loose and
it's matching the background. Shift+F7, or pick a pixel whose colour isn't
behind it.

It worked yesterday and doesn't today: the UI moved. Different window size or
resolution means calibrating again.

Timing is at the top of the script if you want to change it. Clicks during a
reel land between 85 and 145 ms apart, there's a 900 ms pause between cycles,
and it gives up on a charge bar after 5 seconds.

## fishbot.py

Same idea, except it watches a box of pixels instead of one, so a single pixel
drifting doesn't throw it. It takes longer to set up and I don't reach for it
much.

    pip install mss numpy pynput pydirectinput

    python fishbot.py calibrate   # teach it the prompt
    python fishbot.py test        # live readout, get this right before running
    python fishbot.py run         # F2 start/stop, F4 quit

Run the game borderless windowed. Exclusive fullscreen captures as a black
frame and nothing is ever detected.

Calibration takes two samples: F8 with the prompt on screen, F9 once it's gone
with the mouse still in the same spot. It then picks whichever tolerance
separates the two best. If it warns you the samples look too alike, believe it
and aim at a part of the prompt whose colour isn't in the background.

## record.py

A setup helper, not part of the macro. It records a fishing cycle at 4 fps and
zips the frames so you can scrub through them and read exact coordinates and
colours off a still, instead of trying to hover the right pixel live. Frames
are half size and sampled nearest-neighbour, so the colours in them are real
captured colours rather than blends. Halve your screen coordinates to match.

    pip install mss numpy pillow pynput
    python record.py     # F8 start/stop, Esc quit

## Known problems

Single-pixel matching is brittle. Weather, time of day, or any UI element that
slides over your pixel will break it until you recalibrate. That's why the
Python one exists.

Nothing here checks which window is focused. Alt-tab while it's running and it
carries on clicking the same screen coordinates into whatever's in front.

The Python one has no GUI and no stats, it just prints lines.

Coordinates are stored relative to the monitor the game is on, which it works
out by looking for the Roblox window. If you're playing something else, change
the ahk_exe line in MonOffset() or it falls back to whichever monitor your
cursor happens to be on.

Written for AutoHotkey v1. It works, so I'm leaving it there.

Only tested on Windows, at my resolution.

## License

MIT, see LICENSE.

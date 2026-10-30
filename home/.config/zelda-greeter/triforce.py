#!/usr/bin/env python3
"""Spinning Triforce greeter.

  triforce.py spin     play the spin animation, ending face-on
  triforce.py static   print the face-on frame (used as the fastfetch logo)
"""
import math
import sys
import time

ROWS = 14             # terminal rows of the triforce (2 sub-rows each)
SUB = ROWS * 2
WIDTH = round(SUB * 2 / math.sqrt(3))  # equilateral, 1 sub-row ~ 1 column
PAD_TOP, PAD_LEFT = 1, 3               # must match fastfetch logo padding

GOLD = "\033[38;2;255;204;51m"
GOLD_DARK = "\033[38;2;150;105;20m"
DIM = "\033[38;2;200;160;60m"
RESET = "\033[0m"
TITLE = "Z E L D A"


def filled(x, y):
    """x in [-1, 1] across the base, y in [0, 1] from apex to base."""
    if abs(x) > y:
        return False
    # center hole: inverted triangle (-.5,.5) (.5,.5) (0,1)
    return not (y > 0.5 and abs(x) < 1 - y)


def frame(theta):
    c = math.cos(theta)
    color = GOLD if c >= 0 else GOLD_DARK
    scale = max(abs(c), 0.04)  # keep a sliver visible when edge-on
    half = WIDTH / 2
    lines = []
    for r in range(ROWS):
        out = []
        for col in range(WIDTH):
            x = (col + 0.5 - half) / (half * scale)
            top = filled(x, (2 * r + 0.5) / SUB)
            bot = filled(x, (2 * r + 1.5) / SUB)
            out.append("█" if top and bot else "▀" if top else "▄" if bot else " ")
        lines.append(" " * PAD_LEFT + color + "".join(out) + RESET)
    title_pad = PAD_LEFT + (WIDTH - len(TITLE)) // 2
    lines.append("")
    lines.append(" " * title_pad + DIM + TITLE + RESET)
    return lines


def static():
    print("\n".join(frame(0)))


def spin(turns=2, seconds=1.6, fps=40):
    n = int(seconds * fps)
    height = PAD_TOP + ROWS + 2
    out = sys.stdout
    out.write("\033[?25l" + "\n" * height)  # hide cursor, reserve space
    try:
        for i in range(n + 1):
            t = i / n
            ease = 1 - (1 - t) ** 3  # decelerate into the final pose
            lines = [""] * PAD_TOP + frame(ease * turns * 2 * math.pi)
            out.write(f"\033[{height}A" + "".join("\033[2K" + l + "\n" for l in lines))
            out.flush()
            time.sleep(1 / fps)
    except KeyboardInterrupt:
        pass
    finally:
        # erase the animation so fastfetch draws the same logo in its place
        out.write(f"\033[{height}A\033[J\033[?25h")
        out.flush()


if __name__ == "__main__":
    {"spin": spin, "static": static}.get(sys.argv[1] if len(sys.argv) > 1 else "spin", spin)()

#!/usr/bin/env python3
"""Render a spinning 3D Triforce in shade-block ASCII art as a looping,
transparent GIF.

  make_gif.py [output.gif]    (default: logo.gif next to this script)
"""
import math
import os
import subprocess
import sys
import tempfile

ROWS = 16                     # character rows of the image
DEPTH = 0.35                  # thickness of the triforce (base is 2 wide)
MIN_WALL = 3.5                # walls show once they are this many cells wide
TILT = 0.0                    # >0 looks down on it (near corners then dip)
LIGHT = (-0.3, 0.3, 0.9)      # light from the front, slightly upper left
FRAMES = 48
DELAY = 5                     # 1/100 s per frame
FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Bold.ttf"
POINT = 20
CELL_W, CELL_H, BASELINE = 12, 27, 21  # block glyph metrics for this font/size

HEIGHT = math.sqrt(3)         # equilateral triangle with base 2
SPAN_Y = HEIGHT / 2 + 0.12    # visible half-extents, room for the walls
SPAN_X = 1.15
COLS = round(SPAN_X / SPAN_Y * ROWS * CELL_H / CELL_W)

SHADES = "░▒▓█"
GOLD = ["#4a3008", "#6e4a0e", "#946414", "#b8801c", "#d89e26", "#f2be32", "#ffdc5a", "#fff2b0"]


def norm(v):
    n = math.sqrt(sum(c * c for c in v)) or 1
    return tuple(c / n for c in v)


L = norm(LIGHT)


def shape(x, y):
    """Triforce outline: x across the base, y up, centered on the origin."""
    t = (HEIGHT / 2 - y) / HEIGHT  # 0 at the apex, 1 at the base
    if not 0 <= t <= 1 or abs(x) > t:
        return False
    return not (t > 0.5 and abs(x) < 1 - t)


def to_object(sx, sy, sz, ct, st, cp, sp):
    """Undo the tilt (x axis) then the spin (y axis)."""
    y = sy * cp + sz * sp
    z1 = -sy * sp + sz * cp
    return sx * ct - z1 * st, y, sx * st + z1 * ct


def to_screen(nx, ny, nz, ct, st, cp, sp):
    x = nx * ct + nz * st
    z1 = -nx * st + nz * ct
    return x, ny * cp - z1 * sp, ny * sp + z1 * cp


def cell(sx, sy, theta):
    """Ray-cast one cell; return (brightness, is_wall), or None if empty."""
    ct, st, cp, sp = math.cos(theta), math.sin(theta), math.cos(TILT), math.sin(TILT)
    steps, reach = 400, 1.4   # fine steps, or rays skip over the thin tips
    for i in range(steps):
        sz = reach - 2 * reach * i / steps
        x, y, z = to_object(sx, sy, sz, ct, st, cp, sp)
        if abs(z) > DEPTH / 2 or not shape(x, y):
            continue
        wall = abs(z) <= DEPTH / 2 - 0.02
        if wall:
            # every slanted edge belongs to an upright triangle, so its
            # outward normal is (+-sqrt(3)/2, 1/2); probe sideways for the sign
            for e in (0.03, 0.08, 0.2):
                nx = shape(x - e, y) - shape(x + e, y)
                if nx:
                    break
            if nx:
                n = (nx * math.sqrt(3) / 2, 0.5, 0)
            else:
                # a flat top/bottom edge: seen edge-on, so shade it like a face
                wall = False
        if not wall:
            n = (0, 0, 1 if z > 0 else -1)  # front or back face
            if to_screen(*n, ct, st, cp, sp)[2] < 0:
                n = (0, 0, -n[2])  # show whichever face is toward the viewer
        n = to_screen(*n, ct, st, cp, sp)
        return 0.12 + 0.75 * max(0.0, sum(a * b for a, b in zip(n, L))), wall
    return None


def hide_slivers(row, min_run):
    """Give wall strips narrower than min_run cells the shade of the face
    beside them; thin strips of wall read as specks rather than depth."""
    out = list(row)
    c = 0
    while c < len(row):
        if not row[c] or not row[c][1]:
            c += 1
            continue
        end = c
        while end < len(row) and row[end] and row[end][1]:
            end += 1
        if end - c < min_run:
            left = row[c - 1] if c > 0 else None
            right = row[end] if end < len(row) else None
            # no face beside it: a stray sliver floating off the edge, drop it
            out[c:end] = [left or right] * (end - c)
        c = end
    return out


def grid(theta):
    """Rows of (char, color) cells for one rotation angle."""
    # decide per frame, not per strip: strips that cross the cutoff one by one
    # pop in for a single frame and flicker
    wall_width = DEPTH * abs(math.sin(theta)) * COLS / (2 * SPAN_X)
    min_run = 2 if wall_width >= MIN_WALL else COLS + 1
    grid_hits = []
    for r in range(ROWS):
        sy = SPAN_Y - 2 * SPAN_Y * (r + 0.5) / ROWS
        grid_hits.append(hide_slivers([cell(-SPAN_X + 2 * SPAN_X * (c + 0.5) / COLS, sy, theta)
                                       for c in range(COLS)], min_run))

    # a wall cell with no wall above or below is a 1-row speck: use the face beside it
    def is_wall(r, c):
        return 0 <= r < ROWS and bool(grid_hits[r][c]) and grid_hits[r][c][1]

    for r, hits in enumerate(grid_hits):
        for c in range(COLS):
            if is_wall(r, c) and not is_wall(r - 1, c) and not is_wall(r + 1, c):
                beside = [hits[i] for i in (c - 1, c + 1, c - 2, c + 2)
                          if 0 <= i < COLS and hits[i] and not hits[i][1]]
                hits[c] = beside[0] if beside else None

    rows = []
    for hits in grid_hits:
        row = []
        for hit in hits:
            if hit is None:
                row.append((" ", None))
            else:
                b = hit[0]
                row.append((SHADES[min(len(SHADES) - 1, int(b * len(SHADES)))],
                            GOLD[min(len(GOLD) - 1, int(b * len(GOLD)))]))
        rows.append(row)
    return rows


def render(cells, path):
    args = ["magick", "-size", f"{COLS * CELL_W}x{ROWS * CELL_H}", "xc:none",
            "+antialias", "-font", FONT, "-pointsize", str(POINT)]
    # draw each same-colored run at its own offset (leading spaces get collapsed)
    for r, row in enumerate(cells):
        start = 0
        while start < len(row):
            color = row[start][1]
            end = start
            while end < len(row) and row[end][1] == color:
                end += 1
            if color:
                text = "".join(ch for ch, _ in row[start:end])
                args += ["-fill", color, "-annotate",
                         f"+{start * CELL_W}+{r * CELL_H + BASELINE}", text]
            start = end
    subprocess.run(args + [path], check=True)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "logo.gif")
    with tempfile.TemporaryDirectory() as tmp:
        frames = []
        for i in range(FRAMES):
            path = os.path.join(tmp, f"{i:03d}.png")
            render(grid(2 * math.pi * i / FRAMES), path)
            frames.append(path)
        subprocess.run(["magick", "-dispose", "Background", "-delay", str(DELAY),
                        "-loop", "0", *frames, "-layers", "OptimizeTransparency", out],
                       check=True)
    print(out)


if __name__ == "__main__":
    main()

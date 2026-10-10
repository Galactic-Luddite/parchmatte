#!/usr/bin/env python3
"""Procedurally generate Parchmatte's tileable surface textures.

Pure standard-library Python: no third-party packages, no external imagery.
Each texture is a seeded, seamlessly tiling RGBA "grain map". Pixels lighter
than the midpoint are drawn warm white, darker ones warm brown, and alpha
carries the strength of the deviation, so the overlay adds tooth and fibre to
the screen without greying it out.

Two rules keep the surface from looking artificial on large displays:

* No visible repeat. The app draws one texture pixel per device pixel, so a
  256 px tile repeats 20 times across a 5K screen. Tiles are therefore 512 px
  (the signature texture 1024 px), and every noise octave's cell count is an
  integer divisor of the tile, with no feature larger than ~1/16 of the tile:
  the eye finds a repeat through large blotches and landmarks, not fine grain.
  Memory tradeoff: a 512 px tile is 1 MB of GPU memory and a 1024 px tile
  4 MB (RGBA8), with PNGs of roughly 0.3 and 1.3 MB; going bigger would cost
  4x per step for little gain once the landmarks are gone.
* No sparkle. Light pixels are drawn warm white over the screen, so isolated
  bright pixels read as glitter, especially along fibres and threads. Light
  outliers are pulled back toward their neighbours (`tame_highlights`) and the
  light side goes through a soft knee in `render`, while the dark side keeps
  its full range, so each texture keeps its character.

Output: Sources/Parchmatte/Textures/<name>.png
Run: python3 scripts/generate_textures.py
"""
import math
import random
import struct
import zlib
from pathlib import Path

SIZE = 256
OUT_DIR = Path(__file__).resolve().parent.parent / "Sources" / "Parchmatte" / "Textures"

LIGHT = (255, 252, 244)
DARK = (92, 72, 52)


def write_png(path, rows):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw += row
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def periodic_noise(seed, cells):
    """Smooth value noise that wraps every SIZE pixels (seamless tiling)."""
    rng = random.Random(seed)
    lattice = [[rng.random() for _ in range(cells)] for _ in range(cells)]

    def smooth(t):
        return t * t * (3 - 2 * t)

    def sample(x, y):
        fx, fy = x / SIZE * cells, y / SIZE * cells
        x0, y0 = int(fx), int(fy)
        tx, ty = smooth(fx - x0), smooth(fy - y0)
        x0, y0 = x0 % cells, y0 % cells
        x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
        top = lattice[y0][x0] + (lattice[y0][x1] - lattice[y0][x0]) * tx
        bottom = lattice[y1][x0] + (lattice[y1][x1] - lattice[y1][x0]) * tx
        return top + (bottom - top) * ty

    return sample


def field(seed, octaves):
    """Centered sum of periodic noise octaves given as (cells, weight)."""
    layers = [(periodic_noise(seed + i, cells), weight) for i, (cells, weight) in enumerate(octaves)]
    total = sum(weight for _, weight in layers)
    return [
        [sum(fn(x, y) * weight for fn, weight in layers) / total - 0.5 for x in range(SIZE)]
        for y in range(SIZE)
    ]


def add_fibres(grid, seed, count, length, strength, angle=0.0, spread=math.pi, light=0.5):
    """Scatter short wrapped strokes that randomly lighten or darken. Light
    strokes are drawn at `light` times the strength of dark ones: a bright
    line on screen reads as a scratch of glare, a dark one as a fibre."""
    rng = random.Random(seed)
    for _ in range(count):
        x, y = rng.uniform(0, SIZE), rng.uniform(0, SIZE)
        a = angle + rng.uniform(-spread / 2, spread / 2)
        s = strength * rng.uniform(0.4, 1.0) * (light if rng.random() < 0.5 else -1)
        for step in range(int(rng.uniform(length * 0.4, length))):
            grid[int(y + math.sin(a) * step) % SIZE][int(x + math.cos(a) * step) % SIZE] += s


def tile_size(n):
    """Switch the tile size for the textures that follow. Noise octaves are
    given in cells per tile, so double the cells when doubling the tile to
    keep the same physical grain."""
    global SIZE
    SIZE = n


def add_flecks(grid, seed, count, strength):
    """A few tiny dark flecks, as found in real parchment."""
    rng = random.Random(seed)
    for _ in range(count):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        s = strength * rng.uniform(0.5, 1.0)
        grid[y][x] -= s
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grid[(y + dy) % SIZE][(x + dx) % SIZE] -= s * 0.4


def linen(seed, pitch=4):
    """A plain-weave linen cloth: warp and weft threads alternate over and
    under at every crossing. What makes it read as linen rather than a grid:
    each thread has its own tone, swells and thins along its length with
    occasional slubs (thick lumps typical of flax), wanders slightly off
    straight, and is shaded like a round thread with dark gaps between."""
    rng = random.Random(seed)
    threads = SIZE // pitch  # SIZE must be a multiple of 2 * pitch to tile

    def thread_profiles():
        """Per thread, along its length: tone (streaks) and width (slubs)."""
        tones, widths = [], []
        for t in range(threads):
            base = rng.gauss(0, 0.035)
            drift = periodic_noise(seed * 100 + t, SIZE // 64)
            swell = periodic_noise(seed * 100 + t + 50, SIZE // 32)
            # Tone wanders slowly along the thread, so it reads as a long streak.
            tone = [base + 0.07 * (drift(p, 0) - 0.5) for p in range(SIZE)]
            width = [0.9 + 0.12 * (swell(p, 0) - 0.5) for p in range(SIZE)]
            # Slubs: longer, thicker and lighter stretches, typical of flax.
            # (About one per 1000 px of thread, whatever the tile size.)
            for _ in range(1 if rng.random() < SIZE / 1024 else 0):
                centre, half = rng.uniform(0, SIZE), rng.uniform(10, 36)
                lift = rng.uniform(0.015, 0.035)  # soft, or the slub glints
                for p in range(SIZE):
                    d = min(abs(p - centre), SIZE - abs(p - centre))
                    if d < half:
                        k = math.cos(d / half * math.pi / 2) ** 2
                        width[p] += 0.25 * k
                        tone[p] += lift * k
            tones.append(tone)
            widths.append([min(w, 1.0) for w in width])
        return tones, widths

    warp_tone, warp_width = thread_profiles()
    weft_tone, weft_width = thread_profiles()
    wander_x = periodic_noise(seed + 7, SIZE // 42)
    wander_y = periodic_noise(seed + 8, SIZE // 42)

    grid = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            u = (x + (wander_x(x, y) - 0.5) * 0.5) / pitch
            v = (y + (wander_y(x, y) - 0.5) * 0.5) / pitch
            i, j = int(u) % threads, int(v) % threads
            fu, fv = u - int(u), v - int(v)
            du, dv = abs(fu - 0.5) * 2, abs(fv - 0.5) * 2
            ww, fw = warp_width[i][y], weft_width[j][x]
            warp_on_top = (i + j) % 2 == 0
            # The gap where threads cross: only slightly darker, or it reads as
            # a regular grid of dots.
            value = -0.1
            layers = [("warp", du, ww, fv), ("weft", dv, fw, fu)]
            if not warp_on_top:
                layers.reverse()
            for kind, across, width, along in layers:
                if across < width:
                    shade = math.cos(across / width * math.pi / 2) ** 0.4  # round, flat-topped thread
                    dip = 0.85 + 0.15 * math.sin(math.pi * along)  # dives under at the ends
                    # Mostly the upper thread's tone, with some of the one
                    # beneath, so a light thread reads as a continuous soft
                    # line rather than a dashed row of dots.
                    top = warp_tone[i][y] if kind == "warp" else weft_tone[j][x]
                    under = weft_tone[j][x] if kind == "warp" else warp_tone[i][y]
                    value = 0.14 * shade * dip + 0.6 * top + 0.4 * under - 0.02
                    break
            row.append(value)
        grid.append(row)
    # A light wrap-around 3x3 smoothing takes the hard square edges off each
    # crossing without losing the weave.
    soft = [[0.0] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            around = sum(grid[(y + dy) % SIZE][(x + dx) % SIZE] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
            soft[y][x] = 0.8 * grid[y][x] + 0.2 * around / 9
    mean = sum(map(sum, soft)) / (SIZE * SIZE)
    return [[v - mean for v in row] for row in soft]


def add_speckle(grid, seed, amount, light=0.5):
    """Per-pixel tooth. Its light half is scaled by `light`: single bright
    pixels are exactly the sparkle to avoid, single dark ones read as tooth."""
    rng = random.Random(seed)
    for row in grid:
        for x in range(SIZE):
            n = (rng.random() - 0.5) * amount
            row[x] += n * light if n > 0 else n


def tame_highlights(grid, reach):
    """Pull any pixel that is lighter than the mean of its eight neighbours by
    more than `reach` back to that limit (wrapping, so the tile stays
    seamless). Removes isolated bright specks and glinting line crests while
    leaving dark detail and broad light areas alone."""
    out = []
    for y in range(SIZE):
        up, row, down = grid[y - 1], grid[y], grid[(y + 1) % SIZE]
        new = []
        for x in range(SIZE):
            l, r = x - 1, (x + 1) % SIZE
            around = (up[l] + up[x] + up[r] + row[l] + row[r] + down[l] + down[x] + down[r]) / 8
            new.append(min(row[x], around + reach))
        out.append(new)
    return out


def render(name, grid, gain, max_alpha=150, knee=0.5, light=LIGHT, dark=DARK):
    """Map the grain to warm white (light) or warm brown (dark) pixels. The
    light side is soft-kneed so its alpha approaches `knee * max_alpha`
    gradually instead of clipping into bright white points."""
    rows = []
    for line in grid:
        row = bytearray()
        for value in line:
            v = max(-1.0, min(1.0, value * gain))
            if v > 0:
                v = knee * math.tanh(v / knee)
            r, g, b = light if v >= 0 else dark
            row += bytes((r, g, b, int(abs(v) * max_alpha)))
        rows.append(row)
    write_png(OUT_DIR / f"{name}.png", rows)
    print(f"wrote {name}.png")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tile_size(512)

    # Fine grain dominates; low-frequency noise is only a faint undertone.
    g = field(11, [(64, 0.3), (256, 0.7)])
    add_speckle(g, 12, 0.55)
    render("matte", tame_highlights(g, 0.12), 1.4)

    # Parchmatte, the signature texture: real parchment's soft, cloudy
    # mottling, a fine tooth over it, sparse short fibres and the odd fleck.
    # The clouds are the largest features of any texture, so this tile is
    # 1024 px, and the clouds stop at 64 px so no single blotch is a landmark.
    tile_size(1024)
    clouds = field(21, [(16, 0.12), (32, 0.38), (64, 0.5)])
    tooth = field(22, [(512, 1.0)])
    g = [[0.55 * c + 0.5 * t for c, t in zip(cr, tr)] for cr, tr in zip(clouds, tooth)]
    add_fibres(g, 23, 5600, 10, 0.12)
    add_speckle(g, 24, 0.3)
    add_flecks(g, 25, 240, 0.35)
    render("parchmatte", tame_highlights(g, 0.06), 2.0, knee=0.65)
    tile_size(512)

    g = field(31, [(32, 0.2), (128, 0.35), (256, 0.45)])
    add_fibres(g, 32, 3600, 8, 0.22, light=0.35)  # chalk dust streaks, not glare
    add_speckle(g, 33, 0.3)
    render("chalkboard", tame_highlights(g, 0.08), 1.4)

    g = linen(41, pitch=2)
    add_fibres(g, 42, 1200, 6, 0.12, light=0.3)  # stray flax hairs
    add_speckle(g, 44, 0.12)
    render("linen", tame_highlights(g, 0.03), 2.8, knee=0.5)

    g = field(51, [(128, 0.5), (256, 0.5)])
    add_speckle(g, 52, 0.4)
    render("press", tame_highlights(g, 0.08), 1.8, knee=0.45)

    g = field(61, [(64, 0.3), (256, 0.4)])
    add_fibres(g, 62, 2000, 12, 0.1, light=0.4)
    add_speckle(g, 63, 0.25)
    render("vellum", tame_highlights(g, 0.08), 1.1, max_alpha=110)

    g = field(71, [(256, 0.6)])
    add_fibres(g, 72, 20000, 4, 0.22)
    add_speckle(g, 73, 0.3)
    render("felt", tame_highlights(g, 0.1), 1.4)

    # Pale-wash denim: a fine diagonal twill softened by cloudy cotton tooth.
    # Both diagonal periods divide the tile, so the weave and its brushed
    # variation wrap without a join. A faint stonewash blue lives in the
    # grain-map colour, kept near grey so the cloth does not tint the page;
    # alpha remains adjustable through the app's Strength control.
    cloud = field(81, [(32, 0.25), (64, 0.35), (256, 0.4)])
    brush = field(82, [(128, 0.35), (256, 0.65)])
    g = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            twill = math.sin(2 * math.pi * (x + y) / 8)
            companion = math.sin(2 * math.pi * (x - y) / 32)
            row.append(0.11 * twill + 0.025 * companion + 0.16 * cloud[y][x] + 0.12 * brush[y][x])
        g.append(row)
    add_fibres(g, 83, 9000, 5, 0.065, angle=math.pi / 4, spread=0.45, light=0.45)
    add_speckle(g, 84, 0.08, light=0.4)
    render(
        "denim", tame_highlights(g, 0.025), 3.5, max_alpha=150, knee=0.42,
        light=(239, 240, 242), dark=(105, 110, 117),
    )


if __name__ == "__main__":
    main()

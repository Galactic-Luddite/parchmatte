#!/usr/bin/env python3
"""Draw Parchmatte's placeholder app icon: a warm sheet with ruled lines and a
folded corner on a dusk-blue tile. Pure standard library; writes
Resources/AppIcon-1024.png, which scripts/make_icons.sh scales down.
"""
import struct
import zlib
from pathlib import Path

N = 1024
OUT = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon-1024.png"


def inside_rounded(x, y, x0, y0, x1, y1, r):
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def pixel(x, y):
    # Transparent margin outside the macOS icon tile.
    if not inside_rounded(x, y, 100, 100, 924, 924, 185):
        return (0, 0, 0, 0)
    # Tile: vertical dusk gradient.
    t = (y - 100) / 824
    bg = (int(38 + 30 * t), int(52 + 20 * t), int(92 - 10 * t), 255)

    sx0, sy0, sx1, sy1 = 270, 210, 754, 814
    fold = 130
    if sx0 <= x <= sx1 and sy0 <= y <= sy1:
        # Folded top-right corner.
        if x - (sx1 - fold) > y - sy0:
            if x - (sx1 - fold) >= 0 and y - sy0 >= 0 and (x - (sx1 - fold)) + (y - sy0) <= fold * 2:
                return bg
        if x >= sx1 - fold and y <= sy0 + fold and (x - (sx1 - fold)) <= (y - sy0):
            return (214, 196, 160, 255)
        # Warm lamp glow across the sheet.
        dx, dy = (x - 512) / 420, (y - 470) / 420
        glow = max(0.0, 1 - (dx * dx + dy * dy))
        base = (244 + int(8 * glow), 234 + int(10 * glow), 208 + int(6 * glow))
        # Ruled lines and a margin rule.
        if 330 < y < 770 and (y - 330) % 58 < 5 and x > 320:
            return (176, 190, 214, 255)
        if 332 <= x <= 337 and y > 250:
            return (222, 150, 140, 255)
        return (*base, 255)
    # Soft shadow under the sheet.
    if sx0 + 14 <= x <= sx1 + 14 and sy0 + 18 <= y <= sy1 + 18:
        return (int(bg[0] * 0.7), int(bg[1] * 0.7), int(bg[2] * 0.7), 255)
    return bg


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    raw = bytearray()
    for y in range(N):
        raw.append(0)
        for x in range(N):
            raw += bytes(pixel(x, y))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    OUT.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()

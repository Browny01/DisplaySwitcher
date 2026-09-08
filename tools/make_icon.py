#!/usr/bin/env python3
"""Generate a placeholder DisplaySwitcher app icon (two monitors + switch arrow).

Pure standard library: renders a 1024px RGBA PNG, then uses `sips` to derive
the .iconset sizes. Production icons should replace
DisplaySwitcher/Resources/Assets.xcassets/AppIcon.appiconset/.
"""
import math
import os
import struct
import subprocess
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "DisplaySwitcher", "Resources",
                       "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024


class Canvas:
    def __init__(self, size):
        self.n = size
        self.px = bytearray(size * size * 4)

    def blend(self, x, y, r, g, b, a=255):
        if 0 <= x < self.n and 0 <= y < self.n:
            i = (y * self.n + x) * 4
            if a >= 255:
                self.px[i:i + 4] = bytes((r, g, b, 255))
            else:
                inv = 255 - a
                self.px[i] = (r * a + self.px[i] * inv) // 255
                self.px[i + 1] = (g * a + self.px[i + 1] * inv) // 255
                self.px[i + 2] = (b * a + self.px[i + 2] * inv) // 255
                self.px[i + 3] = 255

    def disc(self, cx, cy, rad, color):
        for y in range(int(cy - rad), int(cy + rad) + 1):
            for x in range(int(cx - rad), int(cx + rad) + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad:
                    self.blend(x, y, *color)

    def rect(self, x0, y0, x1, y1, color):
        for y in range(max(0, y0), min(self.n, y1)):
            for x in range(max(0, x0), min(self.n, x1)):
                self.blend(x, y, *color)

    def rounded_rect(self, x0, y0, x1, y1, rad, color, fill=True, width=24):
        if fill:
            self.rect(x0 + rad, y0, x1 - rad, y1, color)
            self.rect(x0, y0 + rad, x1, y1 - rad, color)
            for cx, cy in ((x0 + rad, y0 + rad), (x1 - rad, y0 + rad),
                           (x0 + rad, y1 - rad), (x1 - rad, y1 - rad)):
                self.disc(cx, cy, rad, color)
        else:
            self.rounded_rect(x0, y0, x1, y1, rad, color, True)
            inset = width
            # punch out interior by overdrawing with transparent -> instead draw
            # stroke as ring: redraw smaller rounded rect with bg? Caller passes
            # bg-matching color for the punch. Handled via punch() below.

    def ring_arc(self, cx, cy, rad, width, a0, a1, color, step=0.4):
        a = a0
        while a <= a1:
            rad_angle = math.radians(a)
            for w in range(-width // 2, width // 2 + 1):
                self.disc(int(cx + (rad + w) * math.cos(rad_angle)),
                          int(cy + (rad + w) * math.sin(rad_angle)),
                          width // 3 + 1, color)
            a += step

    def triangle(self, p1, p2, p3, color):
        xs = [p1[0], p2[0], p3[0]]
        ys = [p1[1], p2[1], p3[1]]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            for x in range(int(min(xs)), int(max(xs)) + 1):
                if _point_in_tri(x, y, p1, p2, p3):
                    self.blend(x, y, *color)


def _sign(x, y, ax, ay, bx, by):
    return (x - bx) * (ay - by) - (ax - bx) * (y - by)


def _point_in_tri(x, y, p1, p2, p3):
    d1 = _sign(x, y, *p1, *p2)
    d2 = _sign(x, y, *p2, *p3)
    d3 = _sign(x, y, *p3, *p1)
    neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (neg and pos)


def lerp(a, b, t):
    return int(a + (b - a) * t)


def main():
    c = Canvas(SIZE)
    # Background: vertical blue gradient rounded square.
    top = (14, 132, 255)
    bottom = (0, 70, 200)
    rad = 230
    for y in range(SIZE):
        t = y / SIZE
        col = (lerp(top[0], bottom[0], t), lerp(top[1], bottom[1], t), lerp(top[2], bottom[2], t))
        if rad <= y < SIZE - rad:
            c.rect(0, y, SIZE, y + 1, col)
        else:
            dy = rad - y if y < rad else y - (SIZE - rad)
            dx = int(math.sqrt(max(0, rad * rad - dy * dy)))
            c.rect(rad - dx, y, SIZE - rad + dx, y + 1, col)

    white = (255, 255, 255)
    # Back monitor: outline only, upper right.
    bx0, by0, bx1, by1, br = 430, 210, 850, 540, 46
    c.rounded_rect(bx0, by0, bx1, by1, br, (*white, 235), fill=True)
    c.rounded_rect(bx0 + 30, by0 + 30, bx1 - 30, by1 - 30, br - 20,
                   (10, 100, 230), fill=True)  # punch with inner blue
    # redraw inner as slightly lighter blue screen
    # Front monitor: solid white body, lower left.
    fx0, fy0, fx1, fy1, fr = 175, 420, 640, 790, 46
    c.rounded_rect(fx0, fy0, fx1, fy1, fr, (*white, 255), fill=True)
    # Screen inset.
    sx0, sy0, sx1, sy1 = fx0 + 34, fy0 + 34, fx1 - 34, fy1 - 84
    c.rounded_rect(sx0, sy0, sx1, sy1, 26, (10, 110, 235), fill=True)
    # Stand.
    c.rect(370, fy1 - 52, 448, fy1 - 8, (*white, 255))
    c.rounded_rect(300, fy1 - 26, 518, fy1 + 2, 12, (*white, 255), fill=True)
    # Circular switch arrow on the front screen.
    ccx, ccy, cr = (sx0 + sx1) // 2, (sy0 + sy1) // 2, 78
    c.ring_arc(ccx, ccy, cr, 30, -40, 230, (*white, 255))
    # Arrowhead at end of arc (angle 230deg).
    ex = ccx + cr * math.cos(math.radians(230))
    ey = ccy + cr * math.sin(math.radians(230))
    tx, ty = math.cos(math.radians(230 - 90)), math.sin(math.radians(230 - 90))
    tip = (ex + tx * 52, ey + ty * 52)
    base = (ex - tx * 10, ey - ty * 10)
    nx, ny = -ty, tx
    c.triangle(tip, (base[0] + nx * 34, base[1] + ny * 34),
               (base[0] - nx * 34, base[1] - ny * 34), (*white, 255))

    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        raw.extend(c.px[y * SIZE * 4:(y + 1) * SIZE * 4])

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
           + chunk(b"IEND", b""))
    master = os.path.join(ICONSET, "icon_1024x1024.png")
    os.makedirs(ICONSET, exist_ok=True)
    with open(master, "wb") as f:
        f.write(png)

    sizes = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"),
             (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
             (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"),
             (1024, "icon_512x512@2x")]
    for px, name in sizes:
        out = os.path.join(ICONSET, f"{name}.png")
        if px == 1024:
            continue
        subprocess.run(["sips", "-z", str(px), str(px), master, "--out", out],
                       check=True, capture_output=True)
    os.rename(master, os.path.join(ICONSET, "icon_512x512@2x.png"))

    contents = {"images": [], "info": {"author": "xcode", "version": 1}}
    for px, name in sizes:
        size_label = f"{px // (2 if '@2x' in name else 1)}x{px // (2 if '@2x' in name else 1)}"
        entry = {"filename": f"{name}.png", "idiom": "universal",
                 "platform": "macosx", "size": size_label}
        if "@2x" in name:
            entry["scale"] = "2x"
        else:
            entry["scale"] = "1x"
        contents["images"].append(entry)
    import json
    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("Icon set written to", ICONSET)


if __name__ == "__main__":
    main()

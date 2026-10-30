"""Draws the app icon artwork: a gauge with a needle on the brand gradient."""
import math, sys
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]
S = 4096  # draw large, downscale for smooth edges
TOP, BOTTOM = (0x2F, 0x6B, 0xC0), (0x0B, 0x1B, 0x33)

def gradient(size):
    img = Image.new('RGB', (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    return img

def glyph(size, scale=1.0, color=(255, 255, 255, 255)):
    """The gauge, centred, on a transparent layer. scale shrinks it into a safe zone."""
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = size / 2
    r = size * 0.30 * scale
    w = size * 0.055 * scale
    cy = c + size * 0.04 * scale
    box = [c - r, cy - r, c + r, cy + r]
    # 270° arc from bottom-left to bottom-right, a faint track plus a bright 70% sweep.
    d.arc(box, start=135, end=405, fill=color[:3] + (90,), width=round(w))
    d.arc(box, start=135, end=135 + 270 * 0.7, fill=color, width=round(w))
    # Round the arc ends (the faint track's far end first, so the bright parts sit on top).
    a = math.radians(405)
    x, y = c + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)
    d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=color[:3] + (90,))
    for ang in (135, 135 + 270 * 0.7):
        a = math.radians(ang)
        x, y = c + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=color)
    # Ticks.
    for i in range(11):
        a = math.radians(135 + 27 * i)
        r1, r2 = r - w * 1.6, r - w * (2.3 if i % 5 == 0 else 2.0)
        d.line([(c + r1 * math.cos(a), cy + r1 * math.sin(a)), (c + r2 * math.cos(a), cy + r2 * math.sin(a))],
               fill=color[:3] + (200,), width=round(w * 0.32))
    # Needle pointing at the end of the sweep, with a hub.
    a = math.radians(135 + 270 * 0.7)
    tip = (c + (r - w * 2.6) * math.cos(a), cy + (r - w * 2.6) * math.sin(a))
    nw = w * 0.42
    perp = (math.cos(a + math.pi / 2) * nw, math.sin(a + math.pi / 2) * nw)
    d.polygon([tip, (c + perp[0], cy + perp[1]), (c - perp[0], cy - perp[1])], fill=color)
    hub = w * 0.85
    d.ellipse([c - hub, cy - hub, c + hub, cy + hub], fill=color)
    return layer

def save(img, name, size):
    img.resize((size, size), Image.LANCZOS).save(f'{out}/{name}')

# Full icon (iOS, legacy Android): gradient square with the glyph.
full = gradient(S).convert('RGBA')
full.alpha_composite(glyph(S))
save(full.convert('RGB'), 'icon.png', 1024)
# Android adaptive icon foreground: glyph inside the 66% safe zone.
save(glyph(S, scale=0.62), 'icon_foreground.png', 1024)
# Splash image: glyph only (Android 12 shows it inside a circle, so keep it small).
save(glyph(S, scale=0.55), 'splash.png', 1152)
print('ok')

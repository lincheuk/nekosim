# Generates the NekoSim launcher icon set (Android legacy + adaptive)
# and a 1024px master for stores / other platforms.
#
#   python branding/generate_icon.py
#
# Design: deep space gradient, faint circuit traces, neon-cyan SIM card
# with cut corner and contact pads. Original artwork (the upstream cat
# mascot is not licensed for fork branding, see BRANDING.md).

from PIL import Image, ImageDraw, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
SS = 4  # supersampling factor

NAVY = (13, 19, 51)
INDIGO = (49, 46, 129)
VIOLET = (91, 53, 173)
CYAN = (34, 211, 238)
CYAN_DIM = (34, 211, 238, 90)
PAD_GOLD = (250, 204, 21)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_bg(size):
    """Diagonal navy->indigo->violet gradient with faint circuit traces."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            c = lerp(NAVY, INDIGO, min(1, t * 1.6)) if t < 0.55 else lerp(
                INDIGO, VIOLET, (t - 0.55) / 0.45)
            px[x, y] = c
    d = ImageDraw.Draw(img, "RGBA")
    w = max(1, size // 256)
    step = size // 8
    trace = (255, 255, 255, 10)
    for i in range(1, 8):
        d.line([(i * step, 0), (i * step, size)], fill=trace, width=w)
        d.line([(0, i * step), (size, i * step)], fill=trace, width=w)
    # a couple of brighter angled traces with nodes
    glow = (CYAN[0], CYAN[1], CYAN[2], 36)
    d.line([(0, size * 0.78), (size * 0.30, size * 0.78),
            (size * 0.42, size * 0.66), (size, size * 0.66)],
           fill=glow, width=w * 2)
    d.line([(size * 0.72, 0), (size * 0.72, size * 0.18),
            (size * 0.60, size * 0.30), (size * 0.60, size * 0.46)],
           fill=glow, width=w * 2)
    for cx, cy in [(size * 0.30, size * 0.78), (size * 0.60, size * 0.46),
                   (size * 0.72, size * 0.18)]:
        r = w * 3
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=glow)
    return img


def sim_glyph(size, scale=1.0):
    """Neon SIM card glyph on transparent canvas (size x size)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cw = size * 0.52 * scale   # card width
    ch = size * 0.66 * scale   # card height
    x0 = (size - cw) / 2
    y0 = (size - ch) / 2
    x1, y1 = x0 + cw, y0 + ch
    r = size * 0.055 * scale
    cut = cw * 0.34            # cut corner (top-right)
    lw = max(2, int(size * 0.022 * scale))

    # card silhouette with cut top-right corner
    pts = [
        (x0 + r, y0), (x1 - cut, y0), (x1, y0 + cut),
        (x1, y1 - r), (x1 - r, y1), (x0 + r, y1), (x0, y1 - r), (x0, y0 + r),
    ]
    # soft glow
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.polygon(pts, outline=CYAN + (255,), width=lw * 3)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.02))
    img.alpha_composite(glow)
    # body fill + outline
    d.polygon(pts, fill=(CYAN[0], CYAN[1], CYAN[2], 26))
    d.polygon(pts, outline=CYAN + (255,), width=lw)

    # contact pad block (gold, rounded)
    pw = cw * 0.52
    ph = ch * 0.34
    px0 = x0 + (cw - pw) / 2
    py0 = y0 + ch * 0.42
    d.rounded_rectangle([px0, py0, px0 + pw, py0 + ph],
                        radius=r * 0.8, outline=PAD_GOLD + (255,), width=lw)
    # pad grid lines
    d.line([(px0 + pw / 3, py0), (px0 + pw / 3, py0 + ph)],
           fill=PAD_GOLD + (200,), width=max(1, lw // 2))
    d.line([(px0 + 2 * pw / 3, py0), (px0 + 2 * pw / 3, py0 + ph)],
           fill=PAD_GOLD + (200,), width=max(1, lw // 2))
    d.line([(px0, py0 + ph / 2), (px0 + pw, py0 + ph / 2)],
           fill=PAD_GOLD + (200,), width=max(1, lw // 2))

    # signal arcs (top-left, inside card)
    ax, ay = x0 + cw * 0.20, y0 + ch * 0.30
    for i, rad in enumerate([cw * 0.10, cw * 0.18, cw * 0.26]):
        alpha = 255 - i * 60
        d.arc([ax - rad, ay - rad, ax + rad, ay + rad], start=-80, end=10,
              fill=(CYAN[0], CYAN[1], CYAN[2], alpha), width=lw)
    dot = lw * 1.4
    d.ellipse([ax - dot, ay - dot, ax + dot, ay + dot], fill=CYAN + (255,))
    return img


def rounded_mask(size, radius_ratio=0.22):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    return m


def render_full(size):
    """Legacy launcher icon: rounded square, gradient + glyph."""
    big = size * SS
    img = gradient_bg(big).convert("RGBA")
    img.alpha_composite(sim_glyph(big, scale=1.06))
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(img, mask=rounded_mask(big))
    return out.resize((size, size), Image.LANCZOS)


def render_foreground(size):
    """Adaptive foreground: glyph inside the 66% safe zone, transparent bg."""
    big = size * SS
    img = sim_glyph(big, scale=0.62)
    return img.resize((size, size), Image.LANCZOS)


def render_background(size):
    big = size * SS
    return gradient_bg(big).resize((size, size), Image.LANCZOS)


def save(img, *path):
    p = os.path.join(*path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    print("wrote", os.path.relpath(p, ROOT))


def main():
    densities = {
        "mipmap-mdpi": (48, 108),
        "mipmap-hdpi": (72, 162),
        "mipmap-xhdpi": (96, 216),
        "mipmap-xxhdpi": (144, 324),
        "mipmap-xxxhdpi": (192, 432),
    }
    for folder, (legacy, adaptive) in densities.items():
        save(render_full(legacy), RES, folder, "ic_launcher.png")
        save(render_foreground(adaptive), RES, folder, "ic_launcher_foreground.png")
        save(render_background(adaptive), RES, folder, "ic_launcher_background.png")
    # masters
    save(render_full(1024), ROOT, "branding", "icon_1024.png")
    save(render_foreground(1024), ROOT, "branding", "icon_foreground_1024.png")
    save(render_background(1024), ROOT, "branding", "icon_background_1024.png")


if __name__ == "__main__":
    main()

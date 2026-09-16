"""Генерирует иконки Vigilia (глаз в круге) — трей вкл/выкл и иконку приложения.

    python tool/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
S = 1024  # рисуем крупно, потом уменьшаем — получаем сглаживание

ACCENT, ACCENT_DARK = (0xCB, 0xA6, 0xF7), (0xA7, 0x7F, 0xD8)
SURF_HI, SURF_LO = (0x55, 0x4A, 0x6B), (0x2B, 0x24, 0x38)
INK_ON, INK_OFF = (0x10, 0x0D, 0x16), (0xD2, 0xC8, 0xE6)
SCLERA = (0xFB, 0xF6, 0xFF)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def quad(p0, p1, p2, n=64):
    return [
        (
            (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
            (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1],
        )
        for t in (i / n for i in range(n + 1))
    ]


def render(on: bool) -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # диагональный градиент диска
    hi, lo = (ACCENT, ACCENT_DARK) if on else (SURF_HI, SURF_LO)
    grad = Image.new("RGBA", (S, S))
    gp = grad.load()
    for y in range(S):
        for x in range(0, S, 4):
            c = lerp(hi, lo, (x + y) / (2 * S)) + (255,)
            for dx in range(4):
                gp[x + dx, y] = c
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse((8, 8, S - 8, S - 8), fill=255)
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S / 2 + 20
    w, h = S * 0.62, S * 0.21
    ink = INK_ON if on else INK_OFF
    stroke = round(S * 0.055)
    left, right = (cx - w / 2, cy), (cx + w / 2, cy)
    if on:
        upper = quad(left, (cx, cy - 2.0 * h), right)
        lower = quad(right, (cx, cy + 1.7 * h), left)
        d.polygon(upper + lower, fill=SCLERA)
        ir = h * 0.95
        d.ellipse((cx - ir, cy - ir + h * 0.05, cx + ir, cy + ir + h * 0.05), fill=INK_ON)
        hr = ir * 0.28
        hx, hy = cx - ir * 0.32, cy - ir * 0.3
        d.ellipse((hx - hr, hy - hr, hx + hr, hy + hr), fill=SCLERA)
        # радужка не должна вылезать за веки: снаружи глаза возвращаем чистый диск
        eye = Image.new("L", (S, S), 0)
        ImageDraw.Draw(eye).polygon(upper + lower, fill=255)
        base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        base.paste(grad, (0, 0), mask)
        img = Image.composite(img, base, eye)
        d = ImageDraw.Draw(img)
        d.line(upper + lower + [upper[1]], fill=ink, width=stroke, joint="curve")
    else:
        closed = quad(left, (cx, cy + 0.6 * h), right)
        d.line(closed, fill=ink, width=stroke, joint="curve")
        for s in (0.22, 0.5, 0.78):
            x = left[0] + w * s
            y = cy + 2 * s * (1 - s) * 0.6 * h + stroke * 0.3
            dx = (s - 0.5) * 0.9 * h * 0.55
            d.line([(x, y), (x + dx, y + h * 0.55)], fill=ink, width=round(stroke * 0.8))
    # скруглённые концы линий
    r = stroke / 2
    for px, py in (left, right):
        d.ellipse((px - r, py - r, px + r, py + r), fill=ink)
    return img


def save_ico(img: Image.Image, path: Path, sizes):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="ICO", sizes=[(s, s) for s in sizes])
    print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    on, off = render(True), render(False)
    tray = [16, 20, 24, 32, 40, 48]
    save_ico(on.resize((256, 256), Image.LANCZOS), ROOT / "assets/tray_on.ico", tray)
    save_ico(off.resize((256, 256), Image.LANCZOS), ROOT / "assets/tray_off.ico", tray)
    save_ico(on.resize((256, 256), Image.LANCZOS), ROOT / "windows/runner/resources/app_icon.ico",
             [16, 24, 32, 48, 64, 128, 256])
    on.resize((512, 512), Image.LANCZOS).save(ROOT / "assets/icon.png")
    print("wrote assets/icon.png")

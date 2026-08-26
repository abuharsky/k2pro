#!/usr/bin/env python3
"""Раскладывает иконку приложения по каталогам ассетов iOS, watchOS и macOS.

    python3 tool/icons/generate_icons.py                    # из готового мастера
    python3 tool/icons/generate_icons.py --rebuild-master   # пересобрать из исходника

Исходный рендер очень тёмный, поэтому перед раскладкой он проходит лёгкую
цветокоррекцию, а для часов — более сильную: там иконка живёт на чёрном
циферблате и без подсветки сливается с ним.
"""
import json
import math
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance

ROOT = pathlib.Path(__file__).resolve().parents[2]
BRANDING = ROOT / "assets" / "branding"
SOURCE = BRANDING / "app_icon_source.png"   # исходный рендер как есть
MASTER = BRANDING / "app_icon_master.png"   # кроп 1024 без коррекции
ICON = BRANDING / "app_icon.png"            # то, что реально едет на устройства

IOS_SET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WATCH_SET = ROOT / "ios" / "K2ProWatch" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_SET = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# iOS: полный квадрат без альфы — маску рисует система.
IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
MACOS_CONTENT = 824 / 1024  # сетка Apple: рисунок занимает не весь холст
WATCH_FILENAME = "AppIcon-1024.png"

# gamma < 1 поднимает средние тона, lift отрывает чёрное от нуля.
IOS_GRADE = dict(gamma=0.86, lift=3, saturation=1.06)
WATCH_GRADE = dict(gamma=0.58, lift=8, saturation=1.12)
WATCH_GLOW = (68, 45, 24)  # тёплая подсветка, подмешивается режимом screen


def grade(img: Image.Image, gamma: float, lift: int, saturation: float) -> Image.Image:
    lut = []
    for v in range(256):
        x = 255.0 * (v / 255.0) ** gamma
        lut.append(int(round(min(255.0, lift + x * (255.0 - lift) / 255.0))))
    out = img.point(lut * 3)
    return ImageEnhance.Color(out).enhance(saturation) if saturation != 1.0 else out


def warm_glow(size: int, color: tuple[int, int, int]) -> Image.Image:
    """Радиальное свечение из-под холдера: строим мелким и растягиваем."""
    n = 256
    glow = Image.new("RGB", (n, n))
    px = glow.load()
    cx, cy, radius, floor = 0.5 * n, 0.42 * n, 0.78 * n, 0.10
    for y in range(n):
        for x in range(n):
            k = max(0.0, 1.0 - math.hypot(x - cx, y - cy) / radius)
            k = k * k * (3 - 2 * k)  # smoothstep
            k = floor + (1.0 - floor) * k
            px[x, y] = tuple(int(c * k) for c in color)
    return glow.resize((size, size), Image.LANCZOS)


def screen(a: Image.Image, b: Image.Image) -> Image.Image:
    return ImageChops.invert(
        ImageChops.multiply(ImageChops.invert(a), ImageChops.invert(b))
    )


def squircle_mask(size: int, exponent: float = 5.0, supersample: int = 4) -> Image.Image:
    """Маска-суперэллипс: приближение непрерывного скругления Apple."""
    s = size * supersample
    mask = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(mask)
    a = s / 2.0
    for y in range(s):
        ny = abs((y + 0.5 - a) / a)
        if ny >= 1.0:
            continue
        half = ((1.0 - ny**exponent) ** (1.0 / exponent)) * a
        draw.line([(a - half, y), (a + half, y)], fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def rebuild_master() -> None:
    """Пересобирает квадратный мастер 1024 из исходного рендера.

    В исходнике карточка иконки лежит с чёрными полями и собственным
    скруглением; обрезаем ровно по её границам (плюс 3 px внутрь, чтобы
    убрать светлый рант) — скругление накладывает уже сама система.
    """
    src = Image.open(SOURCE).convert("RGB")
    lum = src.convert("L").load()
    w, h = src.size
    xs, ys = [], []
    for y in range(0, h, 7):
        row = [lum[x, y] for x in range(w)]
        left = next((x for x, v in enumerate(row) if v >= 10), None)
        if left is None:
            continue
        right = next(x for x, v in reversed(list(enumerate(row))) if v >= 10)
        xs += [left, right]
    for x in range(0, w, 7):
        col = [lum[x, y] for y in range(h)]
        top = next((y for y, v in enumerate(col) if v >= 10), None)
        if top is None:
            continue
        bottom = next(y for y, v in reversed(list(enumerate(col))) if v >= 10)
        ys += [top, bottom]
    inset = 3
    box = (min(xs) + inset, min(ys) + inset, max(xs) + 1 - inset, max(ys) + 1 - inset)
    src.crop(box).resize((1024, 1024), Image.LANCZOS).save(MASTER, "PNG")


def square(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    if not MASTER.exists() or "--rebuild-master" in sys.argv:
        rebuild_master()

    master = Image.open(MASTER).convert("RGB")
    assert master.width == master.height, "мастер должен быть квадратным"

    icon = grade(master, **IOS_GRADE)
    icon.save(ICON, "PNG")  # он же ассет приложения

    # iOS — квадрат, RGB без альфы (App Store не принимает прозрачность).
    for name, size in IOS_SIZES.items():
        square(icon, size).save(IOS_SET / name, "PNG")

    # watchOS — сильнее поднят и с тёплым свечением, иначе чёрное на чёрном.
    watch = screen(grade(master, **WATCH_GRADE), warm_glow(master.width, WATCH_GLOW))
    WATCH_SET.mkdir(parents=True, exist_ok=True)
    square(watch, 1024).save(WATCH_SET / WATCH_FILENAME, "PNG")
    (WATCH_SET / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {
                        "idiom": "universal",
                        "platform": "watchos",
                        "size": "1024x1024",
                        "filename": WATCH_FILENAME,
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )

    # macOS — та же картинка, что и на iPhone, но маску система здесь не
    # рисует (в отличие от iOS), поэтому скругляем сами. И вписываем в сетку
    # Apple (824 из 1024), иначе иконка крупнее соседей по доку.
    for size in MACOS_SIZES:
        content = max(1, round(size * MACOS_CONTENT))
        art = square(icon, content).convert("RGBA")
        art.putalpha(squircle_mask(content))
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        off = (size - content) // 2
        canvas.paste(art, (off, off), art)
        canvas.save(MACOS_SET / f"app_icon_{size}.png", "PNG")

    print("готово")


if __name__ == "__main__":
    main()

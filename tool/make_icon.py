"""Draws the TimeGrid launcher icon in the style the user picked:

  * a deep navy rounded square with a soft diagonal gradient and a gentle
    top-left sheen;
  * a bold white "T" whose junction carries a pivot circle with two hands,
    one long going up-right and one shorter going down-right;
  * a 2x3 grid of small white rounded squares in the lower right.

Legacy launchers get the whole icon; Android 8+ gets an adaptive icon whose
foreground is just the white mark, inset into the safe zone, so the launcher
can mask it into whatever shape the device uses.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

RES = r"D:\coding\Android\TIME GRID\android\app\src\main\res"
PREVIEW = r"D:\coding\Android\TIME GRID\dist\icon-preview.png"

TOP_LEFT = (37, 85, 168)      # #2555A8
BOTTOM_RIGHT = (14, 42, 98)   # #0E2A62
WHITE = (255, 255, 255)

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

SUPER = 4096


def diagonal_gradient(size):
    """Linear blend from the top-left colour to the bottom-right one."""
    n = 256
    small = Image.new("RGB", (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(
                round(TOP_LEFT[i] + (BOTTOM_RIGHT[i] - TOP_LEFT[i]) * t)
                for i in range(3)
            )
    return small.resize((size, size), Image.BICUBIC)


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def sheen(size):
    """A soft highlight in the top-left, so the tile is not perfectly flat."""
    layer = Image.new("L", (size, size), 0)
    ImageDraw.Draw(layer).ellipse(
        [-int(size * 0.25), -int(size * 0.35),
         int(size * 0.75), int(size * 0.65)], fill=48)
    return layer.filter(ImageFilter.GaussianBlur(size * 0.09))


def draw_mark(size):
    """The white mark on a transparent canvas, laid out for a full-bleed tile."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def thick_line(p0, p1, width):
        d.line([p0, p1], fill=WHITE, width=width)
        r = width // 2
        for p in (p0, p1):
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=WHITE)

    # --- the T ------------------------------------------------------------
    # The bar stops short of the right edge so the pivot below it keeps its
    # own silhouette instead of merging into the letter.
    bar_y = int(size * 0.292)
    bar_h = int(size * 0.098)
    d.rounded_rectangle(
        [int(size * 0.235), bar_y, int(size * 0.605), bar_y + bar_h],
        radius=bar_h // 2, fill=WHITE)

    stem_w = int(size * 0.098)
    stem_x = int(size * 0.372)
    d.rounded_rectangle(
        [stem_x, bar_y, stem_x + stem_w, int(size * 0.655)],
        radius=stem_w // 2, fill=WHITE)

    # --- pivot circle and its two hands -----------------------------------
    cx, cy = int(size * 0.575), int(size * 0.455)
    radius = int(size * 0.052)
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=WHITE)

    hand = int(size * 0.070)
    long_len = size * 0.155
    short_len = size * 0.105
    ratio = 0.7071  # 45 degrees
    thick_line((cx, cy),
               (int(cx + long_len * ratio), int(cy - long_len * ratio)), hand)
    thick_line((cx, cy),
               (int(cx + short_len * ratio), int(cy + short_len * ratio)), hand)

    # --- 2x3 grid of small squares ----------------------------------------
    cell = int(size * 0.076)
    gap = int(size * 0.030)
    x0 = int(size * 0.558)
    y0 = int(size * 0.555)
    for row in range(3):
        for col in range(2):
            x = x0 + col * (cell + gap)
            y = y0 + row * (cell + gap)
            d.rounded_rectangle([x, y, x + cell, y + cell],
                                radius=int(cell * 0.28), fill=WHITE)
    return img


def legacy_icon(size):
    base = diagonal_gradient(size).convert("RGBA")
    base.alpha_composite(
        Image.merge("RGBA", (
            Image.new("L", (size, size), 255),
            Image.new("L", (size, size), 255),
            Image.new("L", (size, size), 255),
            sheen(size),
        )))
    mark = draw_mark(size)
    base.alpha_composite(mark)
    base.putalpha(rounded_mask(size, int(size * 0.225)))
    return base


def foreground_icon(size):
    """Only the mark, scaled into the adaptive icon's safe zone."""
    square = int(size * 0.62)
    mark = draw_mark(square)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - square) // 2
    canvas.alpha_composite(mark, (offset, offset))
    return canvas


def main():
    master = legacy_icon(SUPER)
    fg_master = foreground_icon(SUPER)
    for folder, size in SIZES.items():
        target = os.path.join(RES, folder)
        os.makedirs(target, exist_ok=True)
        master.resize((size, size), Image.LANCZOS).save(
            os.path.join(target, "ic_launcher.png"), "PNG", optimize=True)
        fg_master.resize((size, size), Image.LANCZOS).save(
            os.path.join(target, "ic_launcher_foreground.png"), "PNG",
            optimize=True)
        print(f"{folder}: {size}px")

    master.resize((512, 512), Image.LANCZOS).save(PREVIEW, "PNG")
    print("preview:", PREVIEW)


if __name__ == "__main__":
    main()

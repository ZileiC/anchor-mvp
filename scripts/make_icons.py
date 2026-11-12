"""Regenerate every icon and the in-app logo from one source file.

    python scripts/make_icons.py            # writes the files
    python scripts/make_icons.py --check    # only reports what would change

Source of truth: ``docs/assets/anchor-logo.png`` (the jade bowl with three sound
waves on warm paper, 512 px). This script is the whole icon pipeline, so a brand
change is one file plus one command instead of ten hand-exported PNGs:

* ``mobile/assets/images/anchor-logo.png``  - the logo shown inside the app
* ``mobile/android/.../mipmap-*/ic_launcher.png`` - the Android launcher icon at
  every density Flutter's template ships (mdpi 48 ... xxxhdpi 192)
* ``mobile/android/.../drawable-nodpi/launch_image.png`` - the centred mark on the
  launch screen (the launch background itself is the paper colour)
* ``mobile/windows/runner/resources/app_icon.ico`` - the Windows application icon
  (16/24/32/48/64/128/256, what the taskbar, Alt-Tab and Explorer show)

The launcher icon and the .ico are cropped to the glyph with a 10% margin, so the
mark fills the icon the way an app icon should; the in-app asset keeps the full
original composition with its paper field.

Pillow is required. Use the bundled runtime:
    C:\\Users\\<user>\\.dsh\\dsh-runtimes\\dsh-primary-runtime\\dependencies\\python\\python.exe
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "docs" / "assets" / "anchor-logo.png"
IN_APP = REPO / "mobile" / "assets" / "images" / "anchor-logo.png"
ANDROID_RES = REPO / "mobile" / "android" / "app" / "src" / "main" / "res"
WINDOWS_ICO = REPO / "mobile" / "windows" / "runner" / "resources" / "app_icon.ico"

# mipmap density -> legacy launcher icon size (Android's own table).
LAUNCHER_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

# The launch screen shows the mark at a fixed physical size, so one file in
# drawable-nodpi is enough and cannot be upscaled by a density bucket.
LAUNCH_IMAGE_SIZE = 320

# How far a pixel must be from the paper colour to count as "ink" when the crop
# box is measured. The glyph is jade on paper, so this is a wide margin and it
# never mistakes anti-aliased edges for the mark.
INK_DISTANCE = 40


def paper_colour(image: Image.Image) -> tuple[int, int, int]:
    """The background is the paper colour; read it from the four corners."""
    rgb = image.convert("RGB")
    width, height = rgb.size
    corners = [
        rgb.getpixel((0, 0)),
        rgb.getpixel((width - 1, 0)),
        rgb.getpixel((0, height - 1)),
        rgb.getpixel((width - 1, height - 1)),
    ]
    return tuple(sum(channel) // len(corners) for channel in zip(*corners))  # type: ignore[return-value]


def glyph_box(image: Image.Image, paper: tuple[int, int, int]) -> tuple[int, int, int, int]:
    """Bounding box of whatever is not paper, plus a 10% margin, as a square."""
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    left, top, right, bottom = width, height, 0, 0
    for y in range(height):
        for x in range(width):
            red, green, blue = pixels[x, y]
            if (
                abs(red - paper[0]) + abs(green - paper[1]) + abs(blue - paper[2])
                > INK_DISTANCE
            ):
                if x < left:
                    left = x
                if y < top:
                    top = y
                if x > right:
                    right = x
                if y > bottom:
                    bottom = y
    if right <= left or bottom <= top:
        raise SystemExit("the source logo looks empty: no ink found")
    span = max(right - left, bottom - top)
    margin = int(span * 0.10)
    side = span + 2 * margin
    centre_x = (left + right) // 2
    centre_y = (top + bottom) // 2
    box = (
        max(0, centre_x - side // 2),
        max(0, centre_y - side // 2),
        min(width, centre_x + side // 2),
        min(height, centre_y + side // 2),
    )
    return box


def square(image: Image.Image, box: tuple[int, int, int, int], paper) -> Image.Image:
    cropped = image.crop(box)
    side = max(cropped.size)
    # Paper, not transparency: the mark is drawn on paper, and a transparent
    # corner would turn black the moment the file is flattened to RGB.
    canvas = Image.new("RGBA", (side, side), tuple(paper) + (255,))
    canvas.paste(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2))
    return canvas


def write_png(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).convert("RGB").save(path, "PNG", optimize=True)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report only, write nothing")
    args = parser.parse_args(argv)

    if not SOURCE.is_file():
        print(f"missing source logo: {SOURCE}", file=sys.stderr)
        return 1

    logo = Image.open(SOURCE)
    paper = paper_colour(logo)
    box = glyph_box(logo, paper)
    mark = square(logo, box, paper)

    planned: list[tuple[Path, int]] = [(IN_APP, logo.size[0])]
    for folder, size in LAUNCHER_SIZES.items():
        planned.append((ANDROID_RES / folder / "ic_launcher.png", size))
    planned.append((ANDROID_RES / "drawable-nodpi" / "launch_image.png", LAUNCH_IMAGE_SIZE))

    for path, size in planned:
        exists = path.is_file()
        note = "" if exists else " (new)"
        print(f"{'keep  ' if exists and args.check else 'write '} {path.relative_to(REPO)} @ {size}px{note}")
        if not args.check:
            write_png(logo if path == IN_APP else mark, path, size)

    print(f"{'keep  ' if args.check else 'write '} {WINDOWS_ICO.relative_to(REPO)} "
          f"@ {', '.join(f'{w}x{h}' for w, h in ICO_SIZES)}")
    if not args.check:
        WINDOWS_ICO.parent.mkdir(parents=True, exist_ok=True)
        windows_source = mark.resize((256, 256), Image.LANCZOS)
        windows_source.save(WINDOWS_ICO, format="ICO", sizes=ICO_SIZES)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

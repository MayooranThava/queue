#!/usr/bin/env python3
"""Audit the *actual* Queue atlas art before approving a replacement.

Requires Pillow: python3 -m pip install Pillow
Usage: python3 Scripts/audit_companion_art.py Queue/Resources/Atlases/Working.atlas --output /tmp/queue-art-audit

Writes a visual contact sheet, a JSON report, and a difference heatmap.
Does NOT alter the source images or the app.
"""
import argparse
import json
import pathlib
import statistics
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageStat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("atlas", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("art-audit"))
    parser.add_argument("--min-visible-change", type=float, default=0.005,
                        help="Minimum fraction of changed opaque pixels for a meaningful frame")
    args = parser.parse_args()
    files = sorted(args.atlas.glob("*.png"))
    if len(files) < 2:
        parser.error("Need at least two PNG frames")
    args.output.mkdir(parents=True, exist_ok=True)
    images = [Image.open(path).convert("RGBA") for path in files]
    sizes = {image.size for image in images}
    if len(sizes) != 1:
        parser.error(f"Inconsistent frame dimensions: {sizes}")
    width, height = images[0].size

    # Pixel differences are measured on composited artwork, ignoring invisible RGB
    # in fully transparent areas. Threshold of 12/255 rejects compression noise.
    flattened = []
    for image in images:
        bg = Image.new("RGBA", image.size, (35, 35, 38, 255))
        flattened.append(Image.alpha_composite(bg, image).convert("RGB"))
    fractions = []
    for first, second in zip(flattened, flattened[1:] + flattened[:1]):
        diff = ImageChops.difference(first, second).convert("L")
        binary = diff.point(lambda value: 255 if value >= 12 else 0)
        histogram = binary.histogram()
        fractions.append((width * height - histogram[0]) / (width * height))

    thumbs = []
    for i, image in enumerate(flattened):
        thumb = image.copy()
        thumb.thumbnail((260, 260))
        tile = Image.new("RGB", (280, 300), (245, 245, 245))
        tile.paste(thumb, ((280 - thumb.width) // 2, 10))
        ImageDraw.Draw(tile).text((12, 273), files[i].name, fill=(20, 20, 20))
        thumbs.append(tile)
    cols = min(4, len(thumbs))
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 280, rows * 300), (245, 245, 245))
    for i, tile in enumerate(thumbs):
        sheet.paste(tile, ((i % cols) * 280, (i // cols) * 300))
    sheet.save(args.output / "contact_sheet.png")

    heat = Image.new("L", (width, height))
    for first, second in zip(flattened, flattened[1:] + flattened[:1]):
        diff = ImageChops.difference(first, second).convert("L")
        heat = ImageChops.lighter(heat, diff)
    ImageEnhance.Contrast(heat).enhance(3).save(args.output / "difference_heatmap.png")

    report = {
        "atlas": str(args.atlas),
        "frames": len(files),
        "dimensions": [width, height],
        "changed_pixel_fraction_by_transition": [round(x, 6) for x in fractions],
        "median_changed_fraction": round(statistics.median(fractions), 6),
        "min_changed_fraction": round(min(fractions), 6),
        "max_changed_fraction": round(max(fractions), 6),
        "potentially_static_transitions": [
            f"{files[i].name} -> {files[(i+1)%len(files)].name}"
            for i, value in enumerate(fractions) if value < args.min_visible_change
        ],
        "note": "Automated changes do not prove correct paw motion; review the heatmap and preview.",
    }
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"Saved {args.output / 'contact_sheet.png'} and difference_heatmap.png")


if __name__ == "__main__":
    main()

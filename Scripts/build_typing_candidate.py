#!/usr/bin/env python3
"""Build a NON-SHIPPING 20-frame cutout typing proof of concept from Queue's actual art.

Requires Pillow and OpenCV. Outputs are deliberately staged in Artwork/Candidates,
not in the app's resource directories. Inspect the preview before integration.
"""
from pathlib import Path
import math
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Queue/Resources/Atlases/Working.atlas/working_000.png"
OUTPUT = ROOT / "Artwork/Candidates/Typing.atlas"
PREVIEW = ROOT / "Artwork/Candidates/typing_preview.gif"

def mask_for_ellipse(size, bounds, feather=4):
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).ellipse(bounds, fill=255)
    if feather:
        from PIL import ImageFilter
        mask = mask.filter(ImageFilter.GaussianBlur(feather))
    return mask

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    original = Image.open(SOURCE).convert("RGBA")
    if original.size != (768, 768):
        raise RuntimeError(f"Unexpected original image size {original.size}")
    # Actual hand regions, not generated ellipses. Coordinates were inspected
    # against Working/working_000.png (768 x 768 transparent source).
    # The masks only select *existing* paw pixels for movement.
    regions = [
        (369, 431, 419, 498), # left-side paw, partially behind laptop
        (405, 433, 493, 513), # right-side paw over keyboard
    ]
    masks = [mask_for_ellipse(original.size, b, feather=3) for b in regions]
    base = np.array(original)
    # Repair exposed pixels from the displaced paws. Alpha channel remains
    # transparent outside the source illustration.
    combined = np.zeros((768,768), dtype=np.uint8)
    for mask in masks:
        combined = np.maximum(combined, np.array(mask))
    # Only inpaint the interior of each selected paw (not the entire scene).
    fillmask = np.where(combined > 150, 255, 0).astype(np.uint8)
    inpainted = cv2.inpaint(cv2.cvtColor(base[:,:,:3], cv2.COLOR_RGB2BGR), fillmask, 3, cv2.INPAINT_TELEA)
    repaired = np.dstack((cv2.cvtColor(inpainted, cv2.COLOR_BGR2RGB), base[:,:,3]))
    background = Image.fromarray(repaired, "RGBA")
    # This is a PROTOTYPE: an automatically inpainted underlay is not equivalent
    # to a hand-painted layered master. It must pass visual review.
    frames = []
    for index in range(20):
        phase = 2 * math.pi * index / 20
        frame = background.copy()
        for hand, mask in enumerate(masks):
            # Opposite-hand stagger: a clear but restrained downward key press.
            wave = math.sin(phase + hand * math.pi * 0.85)
            # Keep subpixel precision: integer rounding caused consecutive
            # frames to collapse to identical PNGs in the first CI run.
            # Increase the key-press arc. The original 5px peak was
            # imperceptible when the 768px illustration was shown at ~300px.
            dx = 3.0 * math.sin(phase * 2 + hand)
            dy = 11.0 * max(0, wave) - 4.0 * max(0, -wave)
            dy += 0.65 * math.sin(phase + hand * 0.6)
            moving = original.copy()
            # Preserve the source transparency; the ellipse is only a region mask.
            moving.putalpha(ImageChops.multiply(original.getchannel("A"), mask))
            # PIL affine transform maps destination -> source. Bilinear
            # resampling produces distinct, smoothly interpolated positions.
            shifted = moving.transform(
                original.size, Image.Transform.AFFINE,
                (1, 0, -dx, 0, 1, -dy),
                resample=Image.Resampling.BILINEAR,
                fillcolor=(0, 0, 0, 0),
            )
            frame = Image.alpha_composite(frame, shifted)
        dest = OUTPUT / f"typing_{index:03d}.png"
        frame.save(dest, optimize=True)
        thumb = Image.new("RGBA", frame.size, (35, 35, 38, 255))
        thumb = Image.alpha_composite(thumb, frame)
        thumb.thumbnail((320, 320))
        frames.append(thumb.convert("RGB"))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(PREVIEW, save_all=True, append_images=frames[1:],
                   duration=75, loop=0, disposal=2, optimize=False)
    print(f"Generated {len(frames)} prototype frames and {PREVIEW}")
    print("NOT FOR PRODUCTION: inspect occlusion, inpainting, and real paw motion.")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Validate a proposed Queue companion PNG animation before Xcode integration.

Usage: python3 Scripts/validate_companion_frames.py path/to/Typing.atlas
Only standard-library modules are required. Exit status is nonzero on failure.
"""
import argparse
import hashlib
import pathlib
import re
import struct
import sys
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"
PATTERN = re.compile(r"typing_(\d{3})\.png$")
COUNT = 20


def inspect_png(path):
    data = path.read_bytes()
    if not data.startswith(SIGNATURE):
        raise ValueError("not a PNG")
    offset = len(SIGNATURE)
    width = height = color_type = bit_depth = None
    has_idat = False
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        name = data[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("truncated PNG chunk")
        payload = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(name + payload) & 0xffffffff != expected_crc:
            raise ValueError("invalid PNG chunk CRC")
        if name == b"IHDR":
            if length != 13:
                raise ValueError("invalid IHDR")
            width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", payload)
        elif name == b"IDAT":
            has_idat = True
        elif name == b"IEND":
            break
        offset = end
    if not width or not height or not has_idat:
        raise ValueError("missing dimensions or image data")
    if bit_depth != 8 or color_type != 6:
        raise ValueError("must be 8-bit RGBA (PNG color type 6)")
    return (width, height), hashlib.sha256(data).hexdigest()


def validate(folder):
    errors = []
    names = sorted(p.name for p in folder.glob("*.png"))
    expected = [f"typing_{i:03d}.png" for i in range(COUNT)]
    if names != expected:
        missing = sorted(set(expected) - set(names))
        extra = sorted(set(names) - set(expected))
        errors.append(f"Expected exactly 20 ordered PNGs; missing={missing}, unexpected={extra}")
    sizes, hashes = set(), []
    for name in expected:
        path = folder / name
        if not path.is_file():
            continue
        try:
            size, digest = inspect_png(path)
            sizes.add(size)
            hashes.append(digest)
        except (OSError, ValueError, struct.error) as exc:
            errors.append(f"{name}: {exc}")
    if len(sizes) > 1:
        errors.append(f"Frame dimensions differ: {sorted(sizes)}")
    if len(hashes) == COUNT and len(set(hashes)) < 10:
        errors.append(f"Too few distinct frames: {len(set(hashes))} of {COUNT}")
    if len(hashes) == COUNT:
        adjacent_identical = sum(hashes[i] == hashes[(i + 1) % COUNT] for i in range(COUNT))
        if adjacent_identical:
            errors.append(f"{adjacent_identical} adjacent frames are byte-identical")
    return errors, sizes, len(set(hashes))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("atlas", type=pathlib.Path)
    args = parser.parse_args()
    if not args.atlas.is_dir():
        parser.error(f"Atlas directory not found: {args.atlas}")
    errors, sizes, unique = validate(args.atlas)
    print(f"Atlas: {args.atlas} | sizes: {sorted(sizes)} | unique frames: {unique}/{COUNT}")
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    print("PASS: naming, PNG integrity, RGBA, dimensions, and basic frame uniqueness")
    print("NOTE: human visual review and stationary-background checks are still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

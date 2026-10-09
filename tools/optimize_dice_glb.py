#!/usr/bin/env python3
"""Shrinks assets/dice.glb without touching its shape.

The dice are a 24-vertex cube whose entire weight is six 1000x1000 PNG face
textures - about 4.5 MB of the file. A die face is drawn at roughly 80 CSS px,
so those textures are many times the size they can ever be seen at. This script
resizes every embedded texture, re-encodes it as PNG, and turns off double-sided
rendering on the (closed) cube so each frame rasterises half as many fragments.

Run after the model is replaced or the size policy changes:

    python3 tools/optimize_dice_glb.py            # 512 px, full colour
    python3 tools/optimize_dice_glb.py --size 256
    python3 tools/optimize_dice_glb.py --colors 256

`--colors` quantises to a palette, which is smaller but can band on smooth
gradients; it is off by default because the textures are not flat art.

Same rule as generate_assets.py: standard library plus Pillow, no network.
"""

import argparse
import io
import json
import os
import struct
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - guidance rather than a stack trace
    sys.exit("This script needs Pillow: python3 -m pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PATH = os.path.join(ROOT, "assets", "dice.glb")

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack("<III", data[:12])
    if magic != GLB_MAGIC or version != 2:
        raise ValueError(f"{path} is not a glTF 2.0 binary")
    chunks = []
    off = 12
    while off < len(data):
        length, kind = struct.unpack("<II", data[off : off + 8])
        chunks.append((kind, data[off + 8 : off + 8 + length]))
        off += 8 + length
    doc = next(c for k, c in chunks if k == CHUNK_JSON)
    blob = next(c for k, c in chunks if k == CHUNK_BIN)
    return json.loads(doc), blob


def _png_bytes(image):
    out = io.BytesIO()
    image.save(out, format="PNG", optimize=True)
    return out.getvalue()


def shrink_images(gltf, blob, size, colors):
    views = gltf["bufferViews"]
    new_data = {}
    for index, image in enumerate(gltf.get("images", [])):
        view_index = image.get("bufferView")
        if view_index is None:
            continue
        view = views[view_index]
        start = view.get("byteOffset", 0)
        raw = blob[start : start + view["byteLength"]]
        img = Image.open(io.BytesIO(raw))
        img = img.resize((size, size), Image.LANCZOS)
        if colors:
            img = img.convert("RGB").quantize(
                colors=colors, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG
            )
        encoded = _png_bytes(img)
        new_data[view_index] = encoded
        print(
            f"  texture {index} ({image.get('name', '?')}): "
            f"{len(raw) / 1024:6.0f} KB -> {len(encoded) / 1024:5.0f} KB "
            f"@ {size}px"
        )
    return new_data


def rebuild_buffer(gltf, original_slices, replacements):
    """Lay every bufferView back out in order, swapping in the new textures.

    Accessors point at bufferViews, not absolute offsets, so as long as the
    untouched views still hold byte-for-byte the same data the geometry is
    unaffected; only the offsets move.
    """
    views = gltf["bufferViews"]
    out = bytearray()
    for index, view in enumerate(views):
        while len(out) % 4:
            out.append(0)
        data = replacements.get(index, original_slices[index])
        view["byteOffset"] = len(out)
        view["byteLength"] = len(data)
        out.extend(data)
    while len(out) % 4:
        out.append(0)
    gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def write_glb(path, gltf, blob):
    doc = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(doc) % 4:
        doc += b" "
    binary = blob
    while len(binary) % 4:
        binary += b"\x00"

    total = 12 + 8 + len(doc) + 8 + len(binary)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", GLB_MAGIC, 2, total))
        fh.write(struct.pack("<II", len(doc), CHUNK_JSON))
        fh.write(doc)
        fh.write(struct.pack("<II", len(binary), CHUNK_BIN))
        fh.write(binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", default=DEFAULT_PATH)
    parser.add_argument("--size", type=int, default=512, help="texture edge in px")
    parser.add_argument(
        "--colors",
        type=int,
        default=0,
        help="palette size (0 = keep full colour)",
    )
    args = parser.parse_args()

    gltf, blob = read_glb(args.path)
    before = os.path.getsize(args.path)

    # Snapshot original view slices before rebuild_buffer rewrites offsets.
    original_slices = []
    for view in gltf["bufferViews"]:
        start = view.get("byteOffset", 0)
        original_slices.append(blob[start : start + view["byteLength"]])

    print("Optimising dice:")
    replacements = shrink_images(gltf, blob, args.size, args.colors)

    # The cube is closed, so culling the back faces is safe and halves the
    # fragment work model-viewer does per die per frame.
    culled = 0
    for material in gltf.get("materials", []):
        if material.get("doubleSided"):
            material["doubleSided"] = False
            culled += 1

    new_blob = rebuild_buffer(gltf, original_slices, replacements)
    write_glb(args.path, gltf, new_blob)

    after = os.path.getsize(args.path)
    print(f"  double-sided materials culled: {culled}")
    print(
        f"  dice.glb {before / 1024 / 1024:.2f} MB -> "
        f"{after / 1024 / 1024:.2f} MB"
    )


if __name__ == "__main__":
    main()

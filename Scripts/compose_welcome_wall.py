"""Compose a deterministic, Retina-ready Honya welcome wall.

The input directory contains portrait cover JPEGs named in display order.  The
script never downloads anything: catalog selection, licensing and attribution
remain explicit outside image processing.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


WIDTH = 1290
HEIGHT = 2796
COLUMNS = 3
GAP = 9
RADIUS = 12
STARTS = (-54, -222, -116)
TILE_WIDTH = 430
TILE_HEIGHT = 645


def cover_tile(source: Image.Image, width: int, height: int) -> Image.Image:
    fitted = ImageOps.fit(
        source.convert("RGB"),
        (width, height),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, width - 1, height - 1), radius=RADIUS, fill=255
    )
    tile = Image.new("RGB", (width, height), "black")
    tile.paste(fitted, mask=mask)
    return tile


def compose(inputs: list[Path], output: Path) -> None:
    if len(inputs) < 9:
        raise ValueError("At least nine covers are required for a varied wall")

    dimensions = {}
    for path in inputs:
        with Image.open(path) as source:
            dimensions[path] = source.size
    too_small = {
        path: size for path, size in dimensions.items()
        if size[0] < 400 or size[1] < 550
    }
    if too_small:
        details = ", ".join(
            f"{path.name}={size[0]}x{size[1]}"
            for path, size in too_small.items()
        )
        raise ValueError(f"Covers below 400x550 pixels: {details}")

    column_width = (WIDTH - GAP * (COLUMNS - 1)) // COLUMNS
    tile_height = round(column_width * 1.5)
    canvas = Image.new("RGB", (WIDTH, HEIGHT), "black")
    tiles = []
    for path in inputs:
        with Image.open(path) as source:
            tiles.append(cover_tile(source, column_width, tile_height))

    for column in range(COLUMNS):
        x = column * (column_width + GAP)
        y = STARTS[column]
        index = column
        while y < HEIGHT:
            canvas.paste(tiles[index % len(tiles)], (x, y))
            y += tile_height + GAP
            index += COLUMNS

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(
        output,
        format="JPEG",
        quality=92,
        subsampling=0,
        optimize=True,
        progressive=False,
    )


def export_asset_tiles(inputs: list[Path], asset_catalog: Path) -> None:
    """Export the same licensed covers as independently animatable assets."""
    for index, path in enumerate(inputs, start=1):
        asset_name = f"BienvenueMur-fr-{index:02d}"
        imageset = asset_catalog / f"{asset_name}.imageset"
        imageset.mkdir(parents=True, exist_ok=True)

        with Image.open(path) as source:
            tile = cover_tile(source, TILE_WIDTH, TILE_HEIGHT)
        tile.save(
            imageset / f"{asset_name}.jpg",
            format="JPEG",
            quality=92,
            subsampling=0,
            optimize=True,
            progressive=False,
        )

        contents = {
            "images": [
                {"idiom": "universal", "scale": "1x"},
                {"idiom": "universal", "scale": "2x"},
                {
                    "filename": f"{asset_name}.jpg",
                    "idiom": "universal",
                    "scale": "3x",
                },
            ],
            "info": {"author": "xcode", "version": 1},
        }
        (imageset / "Contents.json").write_text(
            json.dumps(contents, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_directory", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--tiles-asset-catalog", type=Path)
    args = parser.parse_args()
    inputs = sorted(args.input_directory.glob("wall-*.jpg"))
    compose(inputs, args.output)
    if args.tiles_asset_catalog:
        export_asset_tiles(inputs, args.tiles_asset_catalog)


if __name__ == "__main__":
    main()

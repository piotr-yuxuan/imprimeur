# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
"""Judge, by pixels, how the letters of Cahier sit on the Seyès ruling.

    align-check.py DIRECTORY STEM [STEM ...]

STEM names a case that the driver captured: STEM.json is the page's account of where
each letter is, and STEM-real-TOP.png and STEM-ink-TOP.png are its slices, at the CSS
offset TOP.  Nothing here trusts computed style: the ruling's rows come from the real
picture, in a column left of the margin that nothing else crosses, and the letters'
edges from the picture of the ink alone.

An edge is in device pixels, with its fraction read from the cover of the rows around
half cover, so a true edge inside a row is found inside that row.  A line's error is the
median over its letters that sit on the baseline, positive below.  The baseline is
measured against the top of the nearest thick line, and the x-height, on lines of the
body, against the top of the first thin line above it.

A case passes when every baseline and x-height of the writing is within half a device
pixel, no block of main starts off the grid, and the thick lines are one line apart.
Two kinds of line are held to one device pixel, and printed apart: headings, as a large
size keeps the 0.017 em overshoot that the hinter flattens at the body's size, and
notes, in Caveat, whose own letters do not keep one baseline.  Exit status 1 when one
fails.
"""

import json
import statistics
import sys
from collections.abc import Callable
from itertools import pairwise
from pathlib import Path

from PIL import Image

SITTERS = set("acemnorsuvwx")
TOPPERS = set("acemno")
TOLERANCE = 6
FAINT = 0.2
LIMIT = 0.5
LIMITS = {"heading": 1.0, "note": 1.0}
COVERED = 0.5
ON_THE_GRID = 0.01

Cover = Callable[[int, int], float]


def stitched(directory: Path, stem: str, part: str, facts: dict) -> Image.Image:
    """Return the whole page as one picture, from its slices."""
    width, height = round(facts["width"]), round(facts["height"])
    page = Image.new("RGB", (width, height), (255, 0, 255))
    for name in directory.glob(f"{stem}-{part}-*.png"):
        top = int(name.stem.rsplit("-", 1)[1])
        with Image.open(name) as picture:
            piece = picture.convert("RGB").crop((0, 0, width, facts["slice"]))
            page.paste(piece, (0, top))
    return page


def ruled_rows(page: Image.Image, column: int, colour: list[int]) -> list[int]:
    """Return the first row of each run of COLOUR in COLUMN of PAGE."""
    pixels, rows, previous = page.load(), [], False
    for row in range(page.height):
        channels = zip(pixels[column, row], colour, strict=True)
        now = all(abs(a - b) <= TOLERANCE for a, b in channels)
        if now and not previous:
            rows.append(row)
        previous = now
    return rows


def cover_of(page: Image.Image, facts: dict) -> Cover:
    """Return a function giving how far a pixel of PAGE is from the paper, 0 to 1."""
    paper = facts["paper"]
    full = sum(abs(a - b) for a, b in zip(paper, facts["ink"], strict=True)) or 1
    pixels = page.load()

    def cover(column: int, row: int) -> float:
        channels = zip(pixels[column, row], paper, strict=True)
        return min(1.0, sum(abs(a - b) for a, b in channels) / full)

    return cover


def letter_rows(
    cover: Cover, letter: list, rows: range, size: tuple[int, int]
) -> dict[int, float]:
    """Return each row's greatest cover over the middle of LETTER's columns."""
    left, right = letter[1], letter[2]
    margin = (right - left) * 0.2
    start, end = max(0, round(left + margin)), min(size[0], round(right - margin))
    if end <= start:
        return {}
    return {
        row: max(cover(column, row) for column in range(start, end))
        for row in range(max(0, rows.start), min(size[1], rows.stop))
    }


def edge(rows: dict[int, float], step: int) -> float | None:
    """Return the edge of the ink in ROWS, walking by STEP, 1 for below, -1 for above.

    The furthest row at half of the peak or more, and what it and its neighbour outward
    add of a row: so an edge inside a row reads inside that row.
    """
    peak = max(rows.values(), default=0)
    inked = [row for row, value in rows.items() if value >= COVERED * peak]
    if peak < FAINT or not inked:
        return None
    last = max(inked) if step > 0 else min(inked)
    share = (rows[last] + rows.get(last + step, 0)) / peak
    return last + share if step > 0 else last + 1 - share


def line_edges(
    line: dict, cover: Cover, facts: dict, size: tuple[int, int]
) -> tuple[float | None, float | None]:
    """Return the median bottom edge of LINE's sitters, and top edge of its toppers."""
    baseline = round(line["y"])
    scale = line["size"] / facts["fontSize"]
    reach = round(facts["interline"] * 0.45 * scale) + 3
    tall = round(facts["interline"] * 1.4 * scale)
    bottoms, tops = [], []
    window = range(baseline - reach, baseline + reach)
    for letter in line["letters"]:
        bottom = edge(letter_rows(cover, letter, window, size), 1)
        # A neighbour's descender runs through a letter inked to the window's end.
        if bottom is None or bottom >= baseline + reach - 1:
            continue
        bottoms.append(bottom)
        if letter[0] in TOPPERS:
            above = range(round(bottom) - tall, round(bottom))
            top = edge(letter_rows(cover, letter, above, size), -1)
            # A slanted ascender beside it runs through to the window's end, and a
            # letter that the DOM places off its ink reads short: neither counts.
            short = bottom - facts["interline"] * scale * 0.6
            if top is not None and above.start + 1 < top < short:
                tops.append(top)
    median = statistics.median
    return median(bottoms) if bottoms else None, median(tops) if tops else None


def judged(directory: Path, stem: str) -> tuple[dict, list[dict], list[int]]:
    """Return the facts of the case STEM, the errors of each line, and thick rows."""
    facts = json.loads((directory / f"{stem}.json").read_text(encoding="utf-8"))
    real = stitched(directory, stem, "real", facts)
    ink = stitched(directory, stem, "ink", facts)
    column = round(facts["bodyLeft"] + 6)
    thick = ruled_rows(real, column, facts["thick"])
    thin = set(ruled_rows(real, column, facts["thin"]))
    cover = cover_of(ink, facts)
    interline = round(facts["interline"])
    lines = []
    for line in facts["lines"]:
        if line["code"] or not line["letters"]:
            continue
        bottom, top = line_edges(line, cover, facts, ink.size)
        if bottom is None or not thick:
            continue
        rule = min(thick, key=lambda row: abs(row - bottom))
        near = range(rule - interline - 1, rule - interline + 2)
        above = next((row for row in near if row in thin), rule - interline)
        body = top is not None and line["kind"] == "body"
        lines.append({
            "text": line["text"][:40],
            "kind": line["kind"],
            "baseline": bottom - rule,
            "x": top - above if body else None,
        })
    return facts, lines, thick


def verdict(stem: str, facts: dict, lines: list[dict], thick: list[int]) -> bool:
    """Say what the case STEM measures; return whether it passes."""
    apart = {b - a for a, b in pairwise(thick)}
    line = round(facts["line"])
    spaced = bool(apart) and all(gap % line == 0 for gap in apart)
    off_grid = [b for b in facts["blocks"] if abs(b % facts["line"]) > ON_THE_GRID]
    heights = [entry for entry in lines if entry["x"] is not None]
    nothing = {"baseline": float("inf"), "x": float("inf"), "text": "no line"}
    base = max(lines, key=lambda entry: abs(entry["baseline"]), default=nothing)
    x = max(heights, key=lambda entry: abs(entry["x"]), default=nothing)
    held = all(abs(e["baseline"]) <= LIMITS.get(e["kind"], LIMIT) for e in lines)
    fine = bool(lines) and held and abs(x["x"]) <= LIMIT
    passed = spaced and not off_grid and fine
    sys.stdout.write(
        f"{'PASS' if passed else 'FAIL'} {stem}: {len(lines)} lines, "
        f"{len(heights)} of the body; baseline worst {base['baseline']:+.2f} "
        f"on {base['text']!r}; x-height worst {x['x']:+.2f} on {x['text']!r}; "
        f"blocks off the grid {len(off_grid)}; thick lines {len(thick)}, "
        f"apart by {sorted(apart)}\n"
    )
    for kind in sorted({entry["kind"] for entry in lines}):
        errors = [abs(e["baseline"]) for e in lines if e["kind"] == kind]
        sys.stdout.write(
            f"  {kind}: {len(errors)} lines, baseline mean "
            f"{statistics.mean(errors):.2f}, worst {max(errors):.2f}\n"
        )
    return passed


def main() -> None:
    """Judge each case named on the command line."""
    directory = Path(sys.argv[1])
    results = [verdict(stem, *judged(directory, stem)) for stem in sys.argv[2:]]
    sys.exit(0 if results and all(results) else 1)


main()

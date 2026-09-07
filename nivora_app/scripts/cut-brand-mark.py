"""Cut assets/brand_mark.png — the N-house alone — out of the full nivoralogo.png lockup.

WHY A SCRIPT AND NOT A ONE-OFF
------------------------------
The first cut of this asset was made by hand with `Image.getbbox()`, and getbbox() is the wrong
instrument for this particular PNG. The source carries a fringe of alpha 1-3 all the way to its
edges — invisible on any screen, and enough for getbbox() to report that every edge is "ink".
The mark therefore shipped with 168px of dead space on each side and 105px on top: 21% of its
width and 20% of its height were nothing at all.

That is not cosmetic. Flutter lays out the IMAGE BOX, so the splash was centring a box whose
left edge stood 13dp clear of anything the eye can see while its right edge did not, and the
finished wordmark sat 7.6dp right of centre. The drawn mark was also a fifth smaller than the
height it was given, which made every proportion derived from that height a lie.

THE RULE: TRIM ON WHAT IS VISIBLE, NOT ON WHAT IS NON-ZERO. Alpha 8 is the threshold — well
above the 1-3 noise floor measured in this file, well below the 27 of the first real edge pixel.
"""

import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "nivoralogo.png")
OUT = os.path.join(ROOT, "nivora_app", "assets", "brand_mark.png")

VISIBLE = 8


def visible_box(img: Image.Image):
    """The bounding box of every pixel a person can actually see."""
    alpha = img.split()[3]
    # point() maps the noise floor to 0 and everything visible to 255, so getbbox() — which is
    # the fast C path — answers the question we actually mean.
    return alpha.point(lambda v: 255 if v >= VISIBLE else 0).getbbox()


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    t = im.crop(visible_box(im))
    w, h = t.size

    # SPLIT THE VERTICAL LOCKUP at its widest band of empty rows: the mark sits above, the
    # "NIVORA" wordmark below. Measured rather than hardcoded, which is the same rule
    # scripts/gen-icons.mjs documents for the launcher icon — so the splash mark and the icon
    # the user tapped are cut from the source the same way.
    alpha = t.split()[3].point(lambda v: 255 if v >= VISIBLE else 0)
    empty = [alpha.crop((0, y, w, y + 1)).getextrema()[1] == 0 for y in range(h)]
    runs, start = [], None
    for y, e in enumerate(empty):
        if e and start is None:
            start = y
        elif not e and start is not None:
            runs.append((start, y))
            start = None
    if start is not None:
        runs.append((start, h))
    assert runs, "no empty band found — nivoralogo.png is not the vertical lockup this expects"
    runs.sort(key=lambda r: r[1] - r[0], reverse=True)

    mark = t.crop((0, 0, w, runs[0][0]))
    mark = mark.crop(visible_box(mark))
    mark.save(OUT)
    print("wrote %s at %sx%s (aspect %.3f)" % (OUT, mark.size[0], mark.size[1],
                                               mark.size[0] / mark.size[1]))


main()

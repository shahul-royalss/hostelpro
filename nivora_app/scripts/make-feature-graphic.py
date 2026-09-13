"""Nivora's Play Store feature graphic: 1024 x 500, built from the real brand artwork.

WHY IT LOOKS LIKE THIS. Play shows this strip above the listing, sometimes cropped at the edges,
and — if a promo video is ever added — with a play button overlaid dead centre. So the composition
is deliberately off-centre: the mark sits left, the words sit right, and nothing that matters is in
the middle where a button would land. Everything stays inside a 72px margin.

The mark is reused from assets/brand_mark.png rather than redrawn, and it sits on the same warm
off-white rounded tile as the launcher icon, so somebody who has seen the icon recognises this in
one glance. The navy and the orange are sampled from that PNG, not picked by eye.
"""
import os
from PIL import Image, ImageDraw, ImageFont

APP = r'C:\Users\shahu\OneDrive\Documents\pg management system\nivora_app'
OUT_DIR = r'C:\Users\shahu\OneDrive\Documents\pg management system\dist'
W, H = 1024, 500

# Sampled from assets/brand_mark.png.
NAVY_DEEP = (5, 26, 49)
NAVY_MID = (17, 49, 84)
ACCENT = (246, 170, 58)
TILE = (245, 243, 238)      # NivoraColors.primaryContainer, the launcher icon's ground
INK = (245, 243, 238)
MUTED = (150, 176, 205)


def font(name, size):
    path = os.path.join(APP, 'google_fonts', name)
    return ImageFont.truetype(path, size)


def rounded_tile(size, radius, colour):
    """A launcher-icon-shaped tile, supersampled so the corners are not jagged."""
    s = 4
    m = Image.new('L', (size * s, size * s), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * s - 1, size * s - 1], radius=radius * s, fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    tile = Image.new('RGBA', (size, size), colour + (255,))
    tile.putalpha(m)
    return tile


def ground():
    """A diagonal navy wash. Drawn per-row then sheared slightly by column so it does not read
    as a flat rectangle at listing size."""
    g = Image.new('RGB', (W, H), NAVY_DEEP)
    d = ImageDraw.Draw(g)
    for y in range(H):
        for_t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(
            round(NAVY_DEEP[i] + (NAVY_MID[i] - NAVY_DEEP[i]) * for_t) for i in range(3)))
    # A soft light source behind the mark, so the tile does not float on dead colour.
    glow = Image.new('L', (W, H), 0)
    gd = ImageDraw.Draw(glow)
    cx, cy = 250, H // 2
    for r in range(340, 0, -4):
        gd.ellipse([cx - r, cy - r * 0.85, cx + r, cy + r * 0.85], fill=int(26 * (1 - r / 340)))
    g = Image.composite(Image.new('RGB', (W, H), (32, 74, 122)), g, glow)
    return g.convert('RGBA')


def draw_tracked(d, xy, text, fnt, fill, tracking):
    """PIL has no letter-spacing. The wordmark is spaced in the app (N I V O R A), so it is
    spaced here too, drawn a glyph at a time."""
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=fnt, fill=fill)
        x += d.textlength(ch, font=fnt) + tracking
    return x - tracking


def tracked_width(d, text, fnt, tracking):
    return sum(d.textlength(c, font=fnt) for c in text) + tracking * (len(text) - 1)


def main():
    img = ground()
    d = ImageDraw.Draw(img)

    # ── The mark, on its launcher tile ────────────────────────────────────────────────────
    tile_size = 268
    tile = rounded_tile(tile_size, 62, TILE)
    mark = Image.open(os.path.join(APP, 'assets', 'brand_mark.png')).convert('RGBA')
    inner = int(tile_size * 0.66)
    scale = min(inner / mark.width, inner / mark.height)
    mark = mark.resize((round(mark.width * scale), round(mark.height * scale)), Image.LANCZOS)

    # OPTICALLY CENTRED, NOT GEOMETRICALLY. The N is a house: a tall solid column on the right,
    # an open arch on the left. Its ink fills the PNG canvas edge to edge, so centring the canvas
    # looks correct and is not — the weighted centre of the alpha sits +33px right and +14.5px
    # down of the middle on the 446x405 original. Measured, then divided by this scale, rather
    # than nudged until it looked right.
    # Half of it, not all of it. The full centre-of-mass correction overshoots: the arch's thin
    # leg drags the average left of where the eye puts the shape, and correcting for all 33px left
    # the mark visibly hugging the tile's left edge. Half lands between the two readings.
    OPTICAL = 0.5
    off_x = round(33.0 * scale * OPTICAL)
    off_y = round(14.5 * scale * OPTICAL)
    tile.alpha_composite(mark, ((tile_size - mark.width) // 2 - off_x,
                                (tile_size - mark.height) // 2 - off_y))

    tile_x, tile_y = 96, (H - tile_size) // 2
    # A soft drop shadow, so the tile sits on the navy rather than being pasted onto it.
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [tile_x + 6, tile_y + 12, tile_x + tile_size + 6, tile_y + tile_size + 12],
        radius=62, fill=(0, 0, 0, 90))
    from PIL import ImageFilter
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    img.alpha_composite(tile, (tile_x, tile_y))

    # ── The words ─────────────────────────────────────────────────────────────────────────
    text_x = tile_x + tile_size + 76
    word_f = font('Inter-Bold.ttf', 88)
    tag_f = font('Inter-Regular.ttf', 34)

    tracking = 13
    word_w = tracked_width(d, 'NIVORA', word_f, tracking)
    tag = 'Run your PG from your phone'
    tag_w = d.textlength(tag, font=tag_f)

    # Vertically centre the pair as one block against the tile.
    block_h = 88 + 26 + 34
    top = (H - block_h) // 2 - 6

    draw_tracked(d, (text_x, top), 'NIVORA', word_f, INK, tracking)

    rule_y = top + 88 + 30
    d.rounded_rectangle([text_x, rule_y, text_x + 74, rule_y + 6], radius=3, fill=ACCENT)

    d.text((text_x, rule_y + 30), tag, font=tag_f, fill=MUTED)

    out = os.path.join(OUT_DIR, 'NIVORA-feature-graphic.png')
    img.convert('RGB').save(out, 'PNG', optimize=True)
    print('WROTE %s  %dx%d  %.0f KB' % (out, W, H, os.path.getsize(out) / 1024))
    print('widest text right edge: %d (must stay under %d)' % (
        text_x + max(word_w, tag_w), W - 72))


main()

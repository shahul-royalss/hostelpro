"""Apnivaas's Play Store feature graphic: 1024 x 500, built from the real brand artwork.

WHY IT LOOKS LIKE THIS. Play shows this strip above the listing, sometimes cropped at the edges,
and — if a promo video is ever added — with a play button overlaid dead centre. So the composition
is deliberately off-centre: the logo sits left, the words sit right, and nothing that matters is in
the middle where a button would land. Everything stays inside a 72px margin.

THE LOGO IS THE ARTWORK, NOT A REDRAWING. It is assets/brand/apnivaas_lockup.png — the A-house
above the "Apnivaas" wordmark, lifted off the owner's 8K mockup by scripts/gen-icons.mjs --cut — on
the same warm beige the launch animation plays on (@color/splash_ground), so the store strip, the
launch and the app all read as one brand.

OUTPUT is a 24-bit PNG with NO alpha channel, which is what Play requires for this slot:
    dist/store-listing/apnivaas-feature-graphic.png   (upload this in Play Console)
    ../public/store/feature-graphic-1024x500.png       (the copy kept in the repository)

    python nivora_app/scripts/make-feature-graphic.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(APP)
OUTS = [
    os.path.join(REPO, 'dist', 'store-listing', 'apnivaas-feature-graphic.png'),
    os.path.join(REPO, 'public', 'store', 'feature-graphic-1024x500.png'),
]
W, H = 1024, 500
MARGIN = 72

GROUND = (0xEB, 0xE3, 0xD8)   # @color/splash_ground — the launch animation's beige
INK = (0x09, 0x33, 0x30)      # the wordmark's ink, sampled off the artwork
MUTED = (0x4A, 0x5E, 0x58)    # INK lightened for the second line; 6.1:1 on GROUND
ACCENT = (0x23, 0x5B, 0x4D)   # the mark's median green (@color/notification_accent)


def font(name, size):
    return ImageFont.truetype(os.path.join(APP, 'google_fonts', name), size)


def main():
    img = Image.new('RGB', (W, H), GROUND)
    d = ImageDraw.Draw(img)

    # ── The logo ────────────────────────────────────────────────────────────────────────────
    lockup = Image.open(os.path.join(APP, 'assets', 'brand', 'apnivaas_lockup.png')).convert('RGBA')
    box_h = H - 2 * 92                       # comfortably inside the margins, top and bottom
    scale = box_h / lockup.height
    logo = lockup.resize((round(lockup.width * scale), box_h), Image.LANCZOS)
    logo_x = 88
    img.paste(logo, (logo_x, (H - logo.height) // 2), logo)

    # ── The words ───────────────────────────────────────────────────────────────────────────
    text_x = logo_x + logo.width + 64
    head_f = font('Inter-Bold.ttf', 44)
    sub_f = font('Inter-Regular.ttf', 26)
    head = ['Run your PG or', 'hostel in one app']
    sub = 'Rooms, rent, staff and residents.'

    line_h = 56
    block_h = len(head) * line_h + 28 + 6 + 28 + 36
    top = (H - block_h) // 2
    for i, line in enumerate(head):
        d.text((text_x, top + i * line_h), line, font=head_f, fill=INK)
    rule_y = top + len(head) * line_h + 28
    d.rounded_rectangle([text_x, rule_y, text_x + 74, rule_y + 6], radius=3, fill=ACCENT)
    d.text((text_x, rule_y + 6 + 28), sub, font=sub_f, fill=MUTED)

    widest = max([d.textlength(t, font=head_f) for t in head] + [d.textlength(sub, font=sub_f)])
    right = text_x + widest
    assert right <= W - MARGIN, 'text runs into the right margin: %d > %d' % (right, W - MARGIN)

    for out in OUTS:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        img.save(out, 'PNG', optimize=True)   # mode RGB: no alpha channel, as Play requires
        print('WROTE %s  %dx%d  %.0f KB' % (out, W, H, os.path.getsize(out) / 1024))
    print('widest text right edge: %d (must stay under %d)' % (right, W - MARGIN))


main()

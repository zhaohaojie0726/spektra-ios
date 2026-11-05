"""Draw a mock of the iOS editor screen, so the layout can be judged before
building it.

    python Tools/mock-ios.py

Output: docs/mock-ios.png (780 x 1688, i.e. 390 x 844 pt at 2x).

It is a drawing, not a screenshot: the type and spacing come from the numbers in
`App/Sources/Theme.swift`, but nothing here is SwiftUI.
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "mock-ios.png"

SCALE = 2
W, H = 390 * SCALE, 844 * SCALE

GROUND = (0x5F, 0x5F, 0x5F)
CARD = (0x2D, 0x2D, 0x2C)
WELL = (0x1A, 0x1A, 0x19)
RULE = (0x3A, 0x3B, 0x39)
TEXT = (0xF9, 0xF7, 0xF3)
SECONDARY = (0xDA, 0xD8, 0xD4)
TERTIARY = (0x89, 0x89, 0x89)
ACCENT = (0xE1, 0xA9, 0x5F)
SELECTION = (0xFF, 0xFF, 0xFF)
DARK_INK = (0x0F, 0x0E, 0x0E)

LATIN = "C:/Windows/Fonts/arialbd.ttf"
LATIN_REGULAR = "C:/Windows/Fonts/arial.ttf"
CJK = "C:/Windows/Fonts/msyhbd.ttc"
CJK_REGULAR = "C:/Windows/Fonts/msyh.ttc"


def font(size: float, bold: bool = False, cjk: bool = False) -> ImageFont.FreeTypeFont:
    path = (CJK if bold else CJK_REGULAR) if cjk else (LATIN if bold else LATIN_REGULAR)
    try:
        return ImageFont.truetype(path, int(size * SCALE))
    except OSError:
        return ImageFont.load_default()


def s(value: float) -> int:
    return int(round(value * SCALE))


def main() -> int:
    image = Image.new("RGB", (W, H), GROUND)
    draw = ImageDraw.Draw(image)

    # --- header -----------------------------------------------------------
    header_h = s(46)
    draw.rectangle([0, 0, W, header_h], fill=CARD)
    draw.text((s(14), s(8)), "Portra 400", font=font(13, True), fill=TEXT)
    draw.text((s(14), s(26)), "Portra Endura", font=font(10), fill=TERTIARY)
    # Three glyphs, drawn rather than typed: photo, flask, check.
    gx = W - s(14) - s(10)
    cy = s(23)
    for index in range(3):
        cx = gx - s(30) * index
        if index == 0:      # check
            draw.line([cx - s(5), cy, cx - s(1), cy + s(4)], fill=SECONDARY, width=s(1.4))
            draw.line([cx - s(1), cy + s(4), cx + s(6), cy - s(4)], fill=SECONDARY, width=s(1.4))
        elif index == 1:    # flask
            draw.line([cx - s(5), cy - s(5), cx - s(5), cy - s(1)], fill=SECONDARY, width=s(1.2))
            draw.line([cx + s(5), cy - s(5), cx + s(5), cy - s(1)], fill=SECONDARY, width=s(1.2))
            draw.polygon([(cx - s(5), cy - s(1)), (cx + s(5), cy - s(1)),
                          (cx + s(2), cy + s(5)), (cx - s(2), cy + s(5))],
                         outline=SECONDARY, width=s(1))
        else:               # photo
            draw.rectangle([cx - s(6), cy - s(5), cx + s(6), cy + s(5)],
                           outline=SECONDARY, width=s(1.2))
            draw.ellipse([cx - s(2), cy - s(3), cx + s(1), cy], outline=SECONDARY, width=s(1))

    # --- stock strip ------------------------------------------------------
    strip_top = header_h
    strip_h = s(40)
    draw.rectangle([0, strip_top, W, strip_top + strip_h], fill=CARD)
    chips = [("Portra 400", True), ("Portra 800", False), ("Ektar 100", False)]
    x = s(12)
    for label, selected in chips:
        f = font(12, True)
        width = draw.textlength(label, font=f) + s(20)
        box = [x, strip_top + s(8), x + width, strip_top + s(32)]
        if selected:
            draw.rectangle(box, fill=SELECTION)
            draw.text((x + s(10), strip_top + s(20)), label, font=f, fill=DARK_INK, anchor="lm")
        else:
            draw.rectangle(box, outline=RULE)
            draw.text((x + s(10), strip_top + s(20)), label, font=f, fill=SECONDARY, anchor="lm")
        x += width + s(6)
    draw.line([0, strip_top + strip_h, W, strip_top + strip_h], fill=RULE, width=s(1))

    # --- canvas -----------------------------------------------------------
    # The panel hugs its content: one open section, one collapsed, the bar.
    panel_h = s(203)
    canvas_top = strip_top + strip_h
    canvas_bottom = H - panel_h
    draw.rectangle([0, canvas_top, W, canvas_bottom], fill=GROUND)

    photo = [s(20), canvas_top + s(26), W - s(20), canvas_bottom - s(26)]
    for y in range(photo[1], photo[3]):
        t = (y - photo[1]) / max(1, photo[3] - photo[1])
        colour = (int(24 + 120 * t), int(40 + 90 * t), int(70 + 60 * t))
        draw.line([photo[0], y, photo[2], y], fill=colour)
    draw.text(((photo[0] + photo[2]) // 2, (photo[1] + photo[3]) // 2),
              "photograph", font=font(11, cjk=True), fill=(200, 205, 210), anchor="mm")
    draw.text((s(12), canvas_bottom - s(20)), "完成", font=font(10, cjk=True), fill=TERTIARY)

    # --- panel ------------------------------------------------------------
    draw.rectangle([0, canvas_bottom, W, H], fill=CARD)
    draw.line([0, canvas_bottom, W, canvas_bottom], fill=RULE, width=s(1))

    y = canvas_bottom + s(1)
    title_font = font(12, True, cjk=True)
    label_font = font(11, True, cjk=True)
    sub_font = font(9, True, cjk=True)
    value_font = font(10.5, True)

    def section_header(text: str, note: str, y: int) -> int:
        draw.polygon([(s(13), y + s(12)), (s(22), y + s(12)), (s(17.5), y + s(18))],
                     outline=TEXT)
        draw.text((s(28), y + s(15)), text, font=title_font, fill=TEXT, anchor="lm")
        if note:
            draw.text((W - s(12), y + s(15)), note, font=font(10), fill=TERTIARY, anchor="rm")
        draw.line([0, y + s(30), W, y + s(30)], fill=RULE, width=s(1))
        return y + s(30)

    def row(label: str, sub: str, value: str, fraction: float, gradient, y: int) -> int:
        draw.text((s(12), y + s(8)), label, font=label_font, fill=TEXT, anchor="lm")
        track_x0 = s(12) + s(78) + s(10)
        track_x1 = W - s(12) - s(58) - s(10)
        track_y = y + s(13)
        if gradient:
            steps = 60
            for i in range(steps):
                x0 = track_x0 + (track_x1 - track_x0) * i // steps
                x1 = track_x0 + (track_x1 - track_x0) * (i + 1) // steps
                t = i / (steps - 1)
                if t < 0.5:
                    k = t * 2
                    colour = tuple(int(gradient[0][c] + (gradient[1][c] - gradient[0][c]) * k) for c in range(3))
                else:
                    k = (t - 0.5) * 2
                    colour = tuple(int(gradient[1][c] + (gradient[2][c] - gradient[1][c]) * k) for c in range(3))
                draw.line([x0, track_y, x1, track_y], fill=colour, width=s(2))
        else:
            draw.line([track_x0, track_y, track_x1, track_y], fill=RULE, width=s(2))
        knob_x = track_x0 + (track_x1 - track_x0) * fraction
        draw.ellipse([knob_x - s(6.5), track_y - s(6.5), knob_x + s(6.5), track_y + s(6.5)],
                     fill=(0xFB, 0xF8, 0xF3))
        draw.text((W - s(12), y + s(8)), value, font=value_font, fill=SECONDARY, anchor="rm")
        draw.text((s(12) + s(88), y + s(24)), sub, font=sub_font, fill=TERTIARY, anchor="lm")
        return y + s(26)

    y = section_header("放大机", "CC", y)
    y = row("黄", "→ 蓝", "+0", 0.5, [(0xB8, 0xA8, 0x60), (0x8A, 0x8A, 0x8A), (0x6F, 0x7F, 0xB0)], y)
    y = row("品红", "→ 绿", "+0", 0.5, [(0xB0, 0x7C, 0xAE), (0x8A, 0x8A, 0x8A), (0x7C, 0xA8, 0x7C)], y)
    y = row("印相", "曝光倍数", "×1.00", 1 / 3, None, y)
    y += s(10)
    y = section_header("胶片曝光", "", y)
    y += s(10)

    # --- action bar -------------------------------------------------------
    bar_top = H - s(52)
    draw.line([0, bar_top, W, bar_top], fill=RULE, width=s(1))
    draw.rectangle([s(12), bar_top + s(10), W // 2 - s(4), bar_top + s(42)], fill=SELECTION)
    draw.text((s(12) + (W // 2 - s(16)) // 2, bar_top + s(26)), "渲染",
              font=font(11, True, cjk=True), fill=DARK_INK, anchor="mm")
    draw.rectangle([W // 2 + s(4), bar_top + s(10), W - s(12), bar_top + s(42)], outline=RULE)
    draw.text((W // 2 + s(4) + (W // 2 - s(16)) // 2, bar_top + s(26)), "全尺寸",
              font=font(11, True, cjk=True), fill=SECONDARY, anchor="mm")

    OUT.parent.mkdir(exist_ok=True)
    image.save(OUT)
    print("wrote", OUT, image.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

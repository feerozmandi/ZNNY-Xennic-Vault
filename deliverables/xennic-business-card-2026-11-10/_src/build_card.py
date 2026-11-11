#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Xennic — کارت ویزیت مهندس احمد فیروزمندی (رو و پشت)
Business card, 85 × 55 mm, 3 mm bleed, built on the blank card template
(deliverables/xennic-stationery-kit-2026-11-10) and the brand palette L1-BRD-001/002.

All Persian / Latin text is converted to vector outlines (see textpath.py) so the
files are font-independent and print-exact. The official logo PNG is embedded.
"""

import base64
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import textpath as T

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_SVG = os.path.normpath(os.path.join(HERE, "..", "svg"))
OUT_PNG = os.path.normpath(os.path.join(HERE, "..", "png"))

LOGO_COLOR = os.path.join(ROOT, "02_PreLaunch/L1-BRD/attachments/xennic-logo-final.png")
LOGO_DARK = os.path.join(ROOT, "02_PreLaunch/L1-BRD/attachments/xennic-logo-website-dark.png")
# Vazirmatn stands in for IRANSans (brand's first choice, not freely redistributable).
#   npm pack vazirmatn && tar xzf vazirmatn-*.tgz      → set VAZIRMATN_DIR
_F = os.environ.get("VAZIRMATN_DIR", "/tmp/fonts/package/fonts/ttf")
FONT_R = os.path.join(_F, "Vazirmatn-Regular.ttf")
FONT_M = os.path.join(_F, "Vazirmatn-Medium.ttf")
FONT_SB = os.path.join(_F, "Vazirmatn-SemiBold.ttf")
FONT_B = os.path.join(_F, "Vazirmatn-Bold.ttf")

# ── brand palette ───────────────────────────────────────────────────────────
NAVY = "#0D1B2A"
NAVY_D = "#08131F"
NAVY_L = "#17304A"
GOLD = "#F5B400"
TEAL = "#0A6F6F"
RED = "#E31E24"
WHITE = "#FFFFFF"
GRAY = "#9E9E9E"

# ── card geometry ───────────────────────────────────────────────────────────
CW, CH, B = 85.0, 55.0, 3.0
M = 7.0                      # side margin
RIGHT = CW - M               # 78 mm — right text edge

# ── copy ────────────────────────────────────────────────────────────────────
TXT_COMPANY = "شرکت زر نور نیرو یکتا"
TXT_SERVICES = "مشاوره، طراحی، اجرا، نظارت"
TXT_NAME = "مهندس احمد فیروزمندی"
TXT_ROLE = "رئیس هیئت مدیره"
TXT_PHONE = "۰۹۱۲۴۵۳۳۸۷۸"
TXT_MAIL1 = "feerozmandiha@gmail.com"
TXT_MAIL2 = "info@xennic.ir"
TXT_SITE = "https://xennic.ir"
QR_URL = "https://xennic.ir"


# ── drawing helpers ─────────────────────────────────────────────────────────
def pt(cx, cy, r, a):
    rad = math.radians(a)
    return cx + r * math.cos(rad), cy + r * math.sin(rad)


def arc(cx, cy, r, a0, a1):
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    large = 1 if abs(a1 - a0) > 180 else 0
    return f"M {x0:.2f} {y0:.2f} A {r:.2f} {r:.2f} 0 {large} 1 {x1:.2f} {y1:.2f}"


def arc_stroke(cx, cy, radii, a0, a1, stroke, color=GOLD, ops=None):
    ops = ops or [1.0, 0.42, 0.20][:len(radii)]
    out = []
    for i, r in enumerate(radii):
        sw = stroke if i == 0 else stroke * 0.22
        out.append(f'<path d="{arc(cx, cy, r, a0, a1)}" fill="none" stroke="{color}" '
                   f'stroke-width="{sw:.3f}" stroke-linecap="butt" opacity="{ops[i]:.2f}"/>')
    return "".join(out)


def streak(x0, y0, x1, y1, w0, w1, color=RED, op=0.96):
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    p = [(x0 + nx * w0 / 2, y0 + ny * w0 / 2), (x1 + nx * w1 / 2, y1 + ny * w1 / 2),
         (x1 - nx * w1 / 2, y1 - ny * w1 / 2), (x0 - nx * w0 / 2, y0 - ny * w0 / 2)]
    d = "M " + " L ".join(f"{x:.2f} {y:.2f}" for x, y in p) + " Z"
    return f'<path d="{d}" fill="{color}" opacity="{op}"/>'


def rule(x, y, w, h, color=GOLD, op=1.0):
    return (f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" '
            f'fill="{color}" opacity="{op}"/>')


def logo(path, x, y, w):
    """Embed the official logo; height follows the file's own 2:1 ratio."""
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    h = w / 2.0
    return (f'<image x="{x}" y="{y}" width="{w}" height="{h}" '
            f'preserveAspectRatio="xMidYMid meet" '
            f'xlink:href="data:image/png;base64,{b64}"/>')


# Feather-style line icons on a 24 × 24 grid (MIT), scaled to a given size.
ICONS = {
    "phone": "M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 "
             "19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 "
             ".7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 "
             "12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z",
    "mail": "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M22 6l-10 7L2 6",
    "globe": "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z M2 12h20 M12 2a15.3 15.3 0 0 1 4 10 "
             "15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z",
}


def icon(name, x_right, cy, size=3.4, color=TEAL, sw=0.24):
    k = size / 24.0
    return (f'<g transform="translate({x_right - size:.2f},{cy - size / 2:.2f}) '
            f'scale({k:.5f})" fill="none" stroke="{color}" stroke-width="{sw / k:.3f}" '
            f'stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="{ICONS[name]}"/></g>')


def qr_module_path(url, size, x, y):
    """QR code as one vector path (no bitmap, print-safe)."""
    import qrcode
    q = qrcode.QRCode(version=None, error_correction=qrcode.constants.ERROR_CORRECT_M,
                      box_size=1, border=0)
    q.add_data(url)
    q.make(fit=True)
    m = q.get_matrix()
    n = len(m)
    c = size / n
    rects = []
    for row in range(n):
        for col in range(n):
            if m[row][col]:
                rects.append(f"M {x + col * c:.3f} {y + row * c:.3f} h {c:.3f} v {c:.3f} "
                             f"h {-c:.3f} Z")
    return "".join(rects), n


# ── artwork: front ──────────────────────────────────────────────────────────
def front():
    s = [f'<rect x="{-B}" y="{-B}" width="{CW + 2 * B}" height="{CH + 2 * B}" fill="url(#navy)"/>']
    s.append(f'<g transform="translate({B},{B})">')
    # spark arc, anchored on the bottom-left corner
    s.append(arc_stroke(-5, 61.0, [23.0, 17.8, 28.0], -100, -22, 1.45))
    # spark streak — a short tapered blade nested in the arcs (logomark gesture)
    s.append(streak(6.0, 54.0, 20.5, 24.0, 0.95, 0.14))
    # official logotype, top-right
    s.append(logo(LOGO_DARK, 52.0, 7.4, 26.0))
    # name + role, right aligned
    name, _ = T.text_svg(TXT_NAME, FONT_B, 4.15, RIGHT, 30.3, WHITE, anchor="end")
    s.append(name)
    role, _ = T.text_svg(TXT_ROLE, FONT_M, 2.70, RIGHT, 35.9, GOLD, anchor="end")
    s.append(role)
    # division rule between logotype and name
    s.append(rule(RIGHT - 20.0, 24.6, 20.0, 0.24, GOLD, 0.9))
    # legal name, held quietly at the foot of the text column
    s.append(T.text_svg(TXT_COMPANY, FONT_R, 2.10, RIGHT, 43.9, WHITE,
                        anchor="end", opacity=0.55)[0])
    s.append("</g>")
    return s


# ── artwork: back ───────────────────────────────────────────────────────────
def back():
    s = [f'<rect x="{-B}" y="{-B}" width="{CW + 2 * B}" height="{CH + 2 * B}" fill="url(#paper)"/>']
    s.append(f'<g transform="translate({B},{B})">')
    # quiet spark echo, top-left corner
    s.append(arc_stroke(0, 0, [11.0, 14.5], 4, 86, 0.40, GOLD, [0.40, 0.18]))
    # company + services
    s.append(T.text_svg(TXT_COMPANY, FONT_B, 3.30, RIGHT, 12.8, NAVY, anchor="end")[0])
    s.append(T.text_svg(TXT_SERVICES, FONT_R, 2.55, RIGHT, 18.6, TEAL, anchor="end")[0])
    s.append(rule(RIGHT - 26.0, 22.4, 26.0, 0.22, GOLD, 0.85))
    # contact rows with line icons
    rows = [(TXT_PHONE, FONT_M, 2.80, 30.4, "phone", 1.0, "ltr"),
            (TXT_MAIL1, FONT_R, 2.30, 36.4, "mail", 0.88, None),
            (TXT_MAIL2, FONT_R, 2.30, 41.8, "mail", 0.88, None)]
    for text, face, size, base, ic, op, d in rows:
        s.append(T.text_svg(text, face, size, 73.4, base, NAVY, anchor="end",
                            opacity=op, direction=d)[0])
        s.append(icon(ic, 78.0, base - size * 0.34, 3.3, TEAL, 0.24))
    # QR to the website
    d, n = qr_module_path(QR_URL, 13.6, 9.0, 28.6)
    s.append(f'<path d="{d}" fill="{NAVY}"/>')
    # footer band with the website
    s.append(f'<rect x="{-B}" y="46.9" width="{CW + 2 * B}" height="{CH + 2 * B - 46.9}" fill="{NAVY}"/>')
    s.append(rule(-B, 46.45, CW + 2 * B, 0.45, GOLD))
    s.append(rule(8.6, 50.6, 13.0, 1.4, TEAL))
    s.append(T.text_svg(TXT_SITE, FONT_R, 2.15, RIGHT, 52.3, WHITE, anchor="end", opacity=0.94)[0])
    s.append("</g>")
    return s


# ── packaging ───────────────────────────────────────────────────────────────
def defs():
    return ('<linearGradient id="navy" x1="0" y1="0" x2="0.85" y2="1">'
            f'<stop offset="0" stop-color="{NAVY_L}"/>'
            f'<stop offset="0.52" stop-color="{NAVY}"/>'
            f'<stop offset="1" stop-color="{NAVY_D}"/></linearGradient>'
            '<linearGradient id="paper" x1="0" y1="0" x2="0.6" y2="1">'
            f'<stop offset="0" stop-color="{WHITE}"/>'
            f'<stop offset="1" stop-color="#F2F3F4"/></linearGradient>')


def crop_marks(tx0, ty0, tx1, ty1, ln=3.0, gap=0.6, sw=0.16, color=GRAY, op=0.6):
    g = [f'<g stroke="{color}" stroke-width="{sw}" opacity="{op}">']
    for x in (tx0, tx1):
        g.append(f'<line x1="{x}" y1="{ty0 - gap}" x2="{x}" y2="{ty0 - gap - ln}"/>')
        g.append(f'<line x1="{x}" y1="{ty1 + gap}" x2="{x}" y2="{ty1 + gap + ln}"/>')
    for y in (ty0, ty1):
        g.append(f'<line x1="{tx0 - gap}" y1="{y}" x2="{tx0 - gap - ln}" y2="{y}"/>')
        g.append(f'<line x1="{tx1 + gap}" y1="{y}" x2="{tx1 + gap + ln}" y2="{y}"/>')
    g.append("</g>")
    return "".join(g)


def emit(name, parts):
    os.makedirs(OUT_SVG, exist_ok=True)
    os.makedirs(OUT_PNG, exist_ok=True)
    body = "".join(parts)
    d = defs()
    head = '<?xml version="1.0" encoding="UTF-8"?>\n'

    m = 5.0
    cw, ch = CW + 2 * B + 2 * m, CH + 2 * B + 2 * m
    print_svg = (head + f'<svg xmlns="http://www.w3.org/2000/svg" '
                 f'xmlns:xlink="http://www.w3.org/1999/xlink" '
                 f'width="{cw}mm" height="{ch}mm" viewBox="0 0 {cw} {ch}">\n'
                 f'<defs>{d}</defs>\n<g transform="translate({m},{m})">{body}</g>\n'
                 + crop_marks(m + B, m + B, m + CW + B, m + CH + B) + "\n</svg>\n")

    prev_svg = (head + f'<svg xmlns="http://www.w3.org/2000/svg" '
                f'xmlns:xlink="http://www.w3.org/1999/xlink" '
                f'width="{CW}mm" height="{CH}mm" viewBox="0 0 {CW} {CH}">\n'
                f'<defs>{d}</defs>\n<g transform="translate({-B},{-B})">{body}</g>\n</svg>\n')

    with open(os.path.join(OUT_SVG, name + ".svg"), "w") as f:
        f.write(print_svg)
    tmp = os.path.join("/tmp", name + ".preview.svg")
    with open(tmp, "w") as f:
        f.write(prev_svg)
    return tmp


if __name__ == "__main__":
    print(emit("xennic-business-card-front", front()))
    print(emit("xennic-business-card-back", back()))

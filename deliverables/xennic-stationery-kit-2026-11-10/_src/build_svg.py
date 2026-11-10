#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Xennic — Stationery & Environmental Graphics Kit
Blank templates: NO wordmark, NO logomark, NO copy on any artwork.
Brand source: L1-BRD-001 (هویت برند) + L1-BRD-002 (راهنمای برند)

Design language (shared by every piece)
  spark arc     — open concentric arcs, butt caps: the golden solar arc of the logomark
  spark streak  — a tapered beam of light, the diagonal needle of the logomark
  chevron ledge — hard 45° cuts borrowed from the X arms (pattern / structure only)
  ledger rule   — hairline rules that leave empty fields for logo, name, contact data

Output: ../svg/*.svg   (print-ready: trim + 3 mm bleed + printer's marks)
        ../png/*.png   (on-screen previews: bleed cropped, marks removed)
"""

import math
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_SVG = os.path.normpath(os.path.join(HERE, "..", "svg"))
OUT_PNG = os.path.normpath(os.path.join(HERE, "..", "png"))

# ── Brand palette (L1-BRD-002 §3) ────────────────────────────────────────────
NAVY = "#0D1B2A"
NAVY_D = "#08131F"
NAVY_L = "#17304A"
GOLD = "#F5B400"
TEAL = "#0A6F6F"
TEAL_D = "#075453"
RED = "#E31E24"
WHITE = "#FFFFFF"
MUTED = "#F5F5F5"
GRAY = "#9E9E9E"
DARK = "#424242"


# ── Geometry helpers ─────────────────────────────────────────────────────────
def pt(cx, cy, r, a):
    rad = math.radians(a)
    return cx + r * math.cos(rad), cy + r * math.sin(rad)


def arc(cx, cy, r, a0, a1, sweep=1):
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    large = 1 if abs(a1 - a0) > 180 else 0
    return (f"M {x0:.2f} {y0:.2f} A {r:.2f} {r:.2f} 0 {large} {sweep} "
            f"{x1:.2f} {y1:.2f}")


def arc_stroke(cx, cy, radii, a0, a1, stroke, color=GOLD, ops=None):
    """Concentric open arcs. radii[0] is the main (thick) arc."""
    if ops is None:
        ops = [1.0, 0.5, 0.28][:len(radii)]
    out = []
    for i, r in enumerate(radii):
        sw = stroke if i == 0 else stroke * 0.22
        out.append(
            f'<path d="{arc(cx, cy, r, a0, a1)}" fill="none" stroke="{color}" '
            f'stroke-width="{sw:.3f}" stroke-linecap="butt" opacity="{ops[i]:.2f}"/>'
        )
    return "".join(out)


def streak(x0, y0, x1, y1, w0, w1, color=RED, op=1.0):
    """Tapered beam from (x0,y0) w=w0 to (x1,y1) w=w1."""
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    p = [(x0 + nx * w0 / 2, y0 + ny * w0 / 2),
         (x1 + nx * w1 / 2, y1 + ny * w1 / 2),
         (x1 - nx * w1 / 2, y1 - ny * w1 / 2),
         (x0 - nx * w0 / 2, y0 - ny * w0 / 2)]
    d = "M " + " L ".join(f"{x:.2f} {y:.2f}" for x, y in p) + " Z"
    return f'<path d="{d}" fill="{color}" opacity="{op:.2f}"/>'


def rule(x, y, w, h, color=GOLD, op=1.0):
    return f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" fill="{color}" opacity="{op:.2f}"/>'


def chevron(cx, cy, w, h, thick, color=NAVY, op=1.0, direction=1):
    """Angular arrow/chevron (X-arm vocabulary), pointing right (direction=1)."""
    d = (f"M {cx - w/2:.2f} {cy - h/2:.2f} L {cx - w/2 + thick:.2f} {cy - h/2:.2f} "
         f"L {cx + w/2:.2f} {cy:.2f} L {cx - w/2 + thick:.2f} {cy + h/2:.2f} "
         f"L {cx - w/2:.2f} {cy + h/2:.2f} L {cx - w/2 + thick:.2f} {cy:.2f} Z")
    if direction < 0:
        d = (f"M {cx + w/2:.2f} {cy - h/2:.2f} L {cx + w/2 - thick:.2f} {cy - h/2:.2f} "
             f"L {cx - w/2:.2f} {cy:.2f} L {cx + w/2 - thick:.2f} {cy + h/2:.2f} "
             f"L {cx + w/2:.2f} {cy + h/2:.2f} L {cx + w/2 - thick:.2f} {cy:.2f} Z")
    return f'<path d="{d}" fill="{color}" opacity="{op:.2f}"/>'


def crop_marks(tx0, ty0, tx1, ty1, ln=3.0, gap=0.6, sw=0.16, color=GRAY, op=0.6):
    """Printer's crop marks around the trim box (tx0,ty0)-(tx1,ty1)."""
    g = [f'<g stroke="{color}" stroke-width="{sw}" opacity="{op}">']
    for x in (tx0, tx1):
        g.append(f'<line x1="{x}" y1="{ty0 - gap}" x2="{x}" y2="{ty0 - gap - ln}"/>')
        g.append(f'<line x1="{x}" y1="{ty1 + gap}" x2="{x}" y2="{ty1 + gap + ln}"/>')
    for y in (ty0, ty1):
        g.append(f'<line x1="{tx0 - gap}" y1="{y}" x2="{tx0 - gap - ln}" y2="{y}"/>')
        g.append(f'<line x1="{tx1 + gap}" y1="{y}" x2="{tx1 + gap + ln}" y2="{y}"/>')
    g.append("</g>")
    return "".join(g)


# ── Shared paint definitions ─────────────────────────────────────────────────
def defs_common():
    return (
        '<linearGradient id="navy" x1="0" y1="0" x2="0.85" y2="1">'
        f'<stop offset="0" stop-color="{NAVY_L}"/>'
        f'<stop offset="0.52" stop-color="{NAVY}"/>'
        f'<stop offset="1" stop-color="{NAVY_D}"/></linearGradient>'
        '<linearGradient id="paper" x1="0" y1="0" x2="0.6" y2="1">'
        f'<stop offset="0" stop-color="{WHITE}"/>'
        f'<stop offset="1" stop-color="#F2F3F4"/></linearGradient>'
        '<radialGradient id="goldpool" cx="0.5" cy="0.5" r="0.5">'
        f'<stop offset="0" stop-color="{GOLD}" stop-opacity="0.30"/>'
        f'<stop offset="1" stop-color="{GOLD}" stop-opacity="0"/></radialGradient>'
    )


# ═══════════════════════════════════════════════════════════════════════════
#  ARTWORK DEFINITIONS
#  each returns dict(body=..., defs=..., w=, h=, bleed=, unit=)
# ═══════════════════════════════════════════════════════════════════════════

CARD_W, CARD_H = 85.0, 55.0          # ISO/credit-card standard, print spec §6.3


def card_front():
    B = 3.0
    W, H = CARD_W + 2 * B, CARD_H + 2 * B
    s = []
    s.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="url(#navy)"/>')
    s.append(f'<g transform="translate({B},{B})">')
    # spark arc — anchored on the bottom-left corner, opening to the upper right
    s.append(arc_stroke(-2.5, 61.5, [22.0, 17.4, 27.2], -100, -22, 1.5, GOLD,
                        [1.0, 0.42, 0.22]))
    # spark streak — the needle, rising from the arc toward the top right
    s.append(streak(31.0, 58.5, 79.0, 9.0, 0.40, 1.10, RED, 0.96))
    # teal chip, cut by the trim edge on purpose
    s.append(rule(77.4, 45.4, 7.6, 3.0, TEAL))
    s.append("</g>")
    return dict(body="".join(s), defs=defs_common(), w=W, h=H, bleed=B)


def card_back():
    B = 3.0
    W, H = CARD_W + 2 * B, CARD_H + 2 * B
    s = []
    s.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="url(#paper)"/>')
    s.append(f'<g transform="translate({B},{B})">')
    # quiet spark-arc echo, sitting on the footer band
    s.append(arc_stroke(77.5, 43.0, [15.0, 11.5], -180, -90, 0.45, GOLD, [0.40, 0.22]))
    s.append(arc_stroke(77.5, 43.0, [7.8], -180, -90, 0.95, GOLD, [0.85]))
    # footer band
    s.append(f'<rect x="{-B}" y="42.6" width="{W}" height="15.4" fill="{NAVY}"/>')
    s.append(rule(-B, 42.15, W, 0.45, GOLD))
    s.append(rule(9.0, 48.4, 15.0, 1.3, TEAL))
    s.append(rule(66.0, 48.4, 10.0, 1.3, GOLD, 0.85))
    # micro-accents on the working surface
    s.append(rule(9.0, 8.4, 6.4, 0.95, RED, 0.95))
    s.append(rule(9.0, 11.6, 24.0, 0.18, NAVY, 0.16))
    s.append("</g>")
    return dict(body="".join(s), defs=defs_common(), w=W, h=H, bleed=B)


REG = {}


def register(fn, name):
    REG[name] = fn


register(card_front, "02-business-card-front")
register(card_back, "03-business-card-back")


# ── Emitters ────────────────────────────────────────────────────────────────
def emit(name, fn):
    art = fn()
    w, h, b = art["w"], art["h"], art["bleed"]
    unit = art.get("unit", "mm")
    defs = art.get("defs", "")
    body = art["body"]

    os.makedirs(OUT_SVG, exist_ok=True)
    os.makedirs(OUT_PNG, exist_ok=True)

    head = '<?xml version="1.0" encoding="UTF-8"?>\n'

    if b:
        m = 5.0                                  # margin reserved for printer marks
        cw, ch = w + 2 * m, h + 2 * m
        marks = crop_marks(m + b, m + b, m + w - b, m + h - b)
        print_svg = (head + f'<svg xmlns="http://www.w3.org/2000/svg" width="{cw}{unit}" '
                     f'height="{ch}{unit}" viewBox="0 0 {cw} {ch}">' + "\n" +
                     f'<defs>{defs}</defs>' + "\n" +
                     f'<g transform="translate({m},{m})">{body}</g>' + "\n" +
                     marks + "\n</svg>\n")
    else:
        print_svg = (head + f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}{unit}" '
                     f'height="{h}{unit}" viewBox="0 0 {w} {h}">' + "\n" +
                     f'<defs>{defs}</defs>' + "\n" + body + "\n</svg>\n")

    # preview artwork: bleed cropped away, no marks
    pw, ph = w - 2 * b, h - 2 * b
    prev_svg = (head + f'<svg xmlns="http://www.w3.org/2000/svg" width="{pw}{unit}" '
                f'height="{ph}{unit}" viewBox="0 0 {pw} {ph}">' + "\n" +
                f'<defs>{defs}</defs>' + "\n" +
                f'<g transform="translate({-b},{-b})">{body}</g>' + "\n</svg>\n")

    with open(os.path.join(OUT_SVG, name + ".svg"), "w") as f:
        f.write(print_svg)
    with open(os.path.join("/tmp", name + ".preview.svg"), "w") as f:
        f.write(prev_svg)
    return (os.path.join("/tmp", name + ".preview.svg"),
            os.path.join(OUT_PNG, name + ".png"))


def build(names=None):
    targets = [(n, REG[n]) for n in (names or REG)]
    jobs = []
    for name, fn in targets:
        jobs.append(emit(name, fn))
    return jobs




# ═══════════════════════════════════════════════════════════════════════════
#  05 — LETTERHEAD  (A4 210 × 297 mm, 3 mm bleed)
# ═══════════════════════════════════════════════════════════════════════════
def letterhead():
    B = 3.0
    TW, TH = 210.0, 297.0
    W, H = TW + 2 * B, TH + 2 * B
    hdr_h = 36.0
    ftr_y = 279.0
    defs = defs_common() + (
        f'<clipPath id="hdrClip"><rect x="{-B}" y="{-B}" width="{W}" height="{hdr_h + B}"/></clipPath>'
        f'<clipPath id="ftrClip"><rect x="{-B}" y="{ftr_y}" width="{W}" height="{H - ftr_y}"/></clipPath>'
    )
    s = []
    s.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#FFFFFF"/>')
    s.append(f'<g transform="translate({B},{B})">')
    s.append(f'<rect x="{-B}" y="{-B}" width="{W}" height="{hdr_h + B}" fill="url(#navy)"/>')
    s.append('<g clip-path="url(#hdrClip)">')
    # sunrise: the golden spark arc left in the band
    s.append(arc_stroke(0, 36, [34.0, 28.0, 40.5], -90, -16, 1.8, GOLD, [1.0, 0.30, 0.14]))
    s.append("</g>")
    s.append(rule(-B, hdr_h, W, 0.45, GOLD))
    # the writing surface is deliberately left completely empty
    # footer
    s.append(f'<rect x="{-B}" y="{ftr_y}" width="{W}" height="{H - ftr_y}" fill="{NAVY}"/>')
    s.append(rule(-B, ftr_y - 0.42, W, 0.42, GOLD))
    s.append('<g clip-path="url(#ftrClip)">')
    s.append(rule(196, ftr_y + 8.5, 3.0, 9.0, TEAL, 0.95))
    s.append("</g>")
    s.append(rule(14, 287.5, 16, 1.5, TEAL))
    s.append(rule(14, 291.4, 52, 0.22, WHITE, 0.22))
    s.append("</g>")
    return dict(body="".join(s), defs=defs, w=W, h=H, bleed=B)



# ═══════════════════════════════════════════════════════════════════════════
#  06 / 07 — OFFICIAL CORRESPONDENCE ENVELOPE  (DL 220 × 110 mm, 3 mm bleed)
# ═══════════════════════════════════════════════════════════════════════════
ENV_W, ENV_H = 220.0, 110.0


def envelope_front():
    B = 3.0
    W, H = ENV_W + 2 * B, ENV_H + 2 * B
    defs = defs_common() + (
        f'<clipPath id="panelClip"><rect x="{-B}" y="{-B}" width="{54 + B}" height="{H}"/></clipPath>'
    )
    s = []
    s.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#FFFFFF"/>')
    s.append(f'<g transform="translate({B},{B})">')
    s.append(f'<rect x="{-B}" y="{-B}" width="{54 + B}" height="{H}" fill="url(#navy)"/>')
    s.append('<g clip-path="url(#panelClip)">')
    s.append(arc_stroke(8, 118, [42.0, 34.5, 49.0], -100, -20, 1.55, GOLD, [1.0, 0.40, 0.18]))
    s.append(streak(41, 118, 12, -6, 0.45, 1.20, RED, 0.95))
    s.append("</g>")
    s.append(rule(53.6, -B, 0.40, H, GOLD))
    # address field — layout rules only, no type
    s.append(rule(78, 48.0, 84, 0.16, NAVY, 0.10))
    s.append(rule(78, 64.0, 84, 0.16, NAVY, 0.10))
    # stamp window guide, top right
    s.append(f'<rect x="180" y="12" width="28" height="33" fill="none" stroke="{GRAY}" '
             f'stroke-width="0.25" opacity="0.45"/>')
    s.append("</g>")
    return dict(body="".join(s), defs=defs, w=W, h=H, bleed=B)

def envelope_back():
    B = 3.0
    W, H = ENV_W + 2 * B, ENV_H + 2 * B
    defs = defs_common()
    s = []
    s.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="url(#paper)"/>')
    s.append(f'<g transform="translate({B},{B})">')
    apex_y, shoulder_y = 50.0, 16.0
    flap = (f"M {-B} {-B} L {ENV_W + B} {-B} L {ENV_W + B} {shoulder_y} "
            f"L {ENV_W / 2} {apex_y} L {-B} {shoulder_y} Z")
    s.append(f'<path d="{flap}" fill="url(#navy)"/>')
    # gold trim along the two folded edges
    s.append(f'<path d="M {-B} {shoulder_y} L {ENV_W / 2} {apex_y} L {ENV_W + B} {shoulder_y}" '
             f'fill="none" stroke="{GOLD}" stroke-width="0.50"/>')
    # inner trim, 5 mm up the flap
    s.append(f'<path d="M {-B} {shoulder_y - 5.5} L {ENV_W / 2} {apex_y - 8.2} '
             f'L {ENV_W + B} {shoulder_y - 5.5}" fill="none" stroke="{GOLD}" '
             f'stroke-width="0.22" opacity="0.45"/>')
    s.append(rule(ENV_W / 2 - 4.5, apex_y + 9.0, 9.0, 1.9, TEAL, 0.95))
    s.append("</g>")
    return dict(body="".join(s), defs=defs, w=W, h=H, bleed=B)



# ═══════════════════════════════════════════════════════════════════════════
#  04 — ADVERTISING BANNER / ROLL-UP  (850 × 2000 mm, 20 mm bleed)
# ═══════════════════════════════════════════════════════════════════════════
def banner():
    B = 20.0
    TW, TH = 850.0, 2000.0
    W, H = TW + 2 * B, TH + 2 * B
    defs = defs_common()
    s = []
    s.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="url(#navy)"/>')
    s.append(f'<g transform="translate({B},{B})">')
    # the horizon arc: a long, calm sweep of brand gold through the lower third
    s.append(arc_stroke(-600, 4200, [3000, 2870, 3130], -80, -50, 26, GOLD,
                        [0.95, 0.30, 0.16]))
    # spark streak, rising across the composition
    s.append(streak(262, 1815, 722, 318, 30, 5, RED, 0.95))
    # contact platform
    s.append(f'<rect x="{-B}" y="1800" width="{W}" height="{H - 1800}" fill="{TEAL}"/>')
    s.append(rule(-B, 1797.2, W, 2.8, GOLD))
    s.append(rule(86, 1940, 220, 1.5, WHITE, 0.26))
    s.append(rule(86, 1972, 96, 1.6, GOLD, 0.80))
    s.append("</g>")
    return dict(body="".join(s), defs=defs, w=W, h=H, bleed=B)

register(letterhead, "05-letterhead-a4")
register(envelope_front, "06-envelope-dl-front")
register(envelope_back, "07-envelope-dl-back")
register(banner, "04-rollup-banner")




# ═══════════════════════════════════════════════════════════════════════════
#  SCENE HELPERS  (px canvases: presentation pieces, no trim marks)
# ═══════════════════════════════════════════════════════════════════════════
def p_shadow(id_, dx=0, dy=14, blur=22, op=0.20):
    return (f'<filter id="{id_}" x="-40%" y="-40%" width="180%" height="180%">'
            f'<feDropShadow dx="{dx}" dy="{dy}" stdDeviation="{blur}" '
            f'flood-color="#0D1B2A" flood-opacity="{op}"/></filter>')


def p_navy(id_):
    return (f'<linearGradient id="{id_}" x1="0" y1="0" x2="0.8" y2="1">'
            f'<stop offset="0" stop-color="#1A3350"/>'
            f'<stop offset="0.5" stop-color="{NAVY}"/>'
            f'<stop offset="1" stop-color="#08131F"/></linearGradient>')


# ═══════════════════════════════════════════════════════════════════════════
#  01 — OFFICE STATIONERY SET  (flat-lay, 1600 × 1200 px)
# ═══════════════════════════════════════════════════════════════════════════
def stationery_set():
    W, H = 1600, 1200
    defs = (p_navy("nvA") + p_navy("nvB") + p_navy("nvC") +
            p_shadow("shA", 0, 18, 26, 0.22) + p_shadow("shB", 0, 12, 18, 0.20) +
            p_shadow("shC", 0, 10, 14, 0.18) + p_shadow("shD", 0, 8, 12, 0.16) +
            '<radialGradient id="tableG" cx="0.42" cy="0.36" r="0.85">'
            '<stop offset="0" stop-color="#FCFCFB"/>'
            '<stop offset="0.65" stop-color="#F2F2EF"/>'
            '<stop offset="1" stop-color="#E6E6E2"/></radialGradient>'
            '<linearGradient id="tealG" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{TEAL}"/><stop offset="1" stop-color="{TEAL_D}"/></linearGradient>'
            f'<linearGradient id="penG" x1="0" y1="0" x2="1" y2="0">'
            f'<stop offset="0" stop-color="#08131F"/><stop offset="0.4" stop-color="{NAVY_L}"/>'
            f'<stop offset="0.6" stop-color="{NAVY}"/><stop offset="1" stop-color="#050C14"/></linearGradient>'
            f'<clipPath id="foldClip"><rect x="800" y="120" width="560" height="780"/></clipPath>'
            f'<clipPath id="bookClip"><rect x="230" y="300" width="400" height="570" rx="6"/></clipPath>'
            f'<clipPath id="envClip"><rect x="150" y="900" width="540" height="250"/></clipPath>'
            f'<clipPath id="cardClip0"><rect x="1050" y="895" width="270" height="185"/></clipPath>')
    s = [f'<rect width="{W}" height="{H}" fill="url(#tableG)"/>']

    # ── A4 folder ──────────────────────────────────────────────────────────
    s.append('<g filter="url(#shA)" transform="rotate(-1.2 1080 510)">')
    s.append(f'<rect x="800" y="120" width="560" height="780" rx="3" fill="url(#nvA)"/>')
    s.append('<g clip-path="url(#foldClip)">')
    s.append(arc_stroke(806, 900, [250, 285, 218], -100, -14, 14, GOLD, [1.0, 0.30, 0.14]))
    s.append(streak(1010, 900, 1300, 210, 5, 16, RED, 0.92))
    s.append("</g>")
    s.append(rule(800, 120, 22, 780, TEAL))
    s.append(rule(822, 120, 1.6, 780, GOLD, 0.55))
    # blank label block
    s.append('<g filter="url(#shD)"><rect x="856" y="176" width="212" height="74" rx="2" fill="#FFFFFF"/></g>')
    s.append(rule(856, 176, 212, 3.0, GOLD))
    s.append(rule(1130, 840, 190, 1.6, WHITE, 0.20))
    s.append("</g>")

    # ── A5 notebook ────────────────────────────────────────────────────────
    s.append('<g filter="url(#shB)" transform="rotate(-6 430 585)">')
    s.append(f'<rect x="230" y="300" width="400" height="570" rx="6" fill="url(#nvB)"/>')
    s.append('<g clip-path="url(#bookClip)">')
    s.append(arc_stroke(232, 880, [200, 232, 170], -100, -16, 11, GOLD, [1.0, 0.28, 0.12]))
    s.append(streak(400, 878, 600, 300, 4, 12, RED, 0.90))
    s.append(f'<rect x="230" y="812" width="400" height="58" fill="url(#tealG)"/>')
    s.append("</g>")
    s.append(rule(230, 300, 400, 1.6, WHITE, 0.14))
    s.append(rule(258, 352, 120, 1.8, GOLD, 0.85))
    s.append(rule(230, 810, 400, 2.2, GOLD))
    s.append("</g>")

    # ── DL envelope ────────────────────────────────────────────────────────
    s.append('<g filter="url(#shC)" transform="rotate(3.5 420 1025)">')
    s.append('<rect x="150" y="900" width="540" height="250" fill="#FFFFFF"/>')
    s.append('<g clip-path="url(#envClip)">')
    s.append(f'<rect x="150" y="900" width="132" height="250" fill="url(#nvC)"/>')
    s.append(arc_stroke(152, 1155, [96, 78], -100, -24, 7.5, GOLD, [1.0, 0.30]))
    s.append(streak(196, 1152, 268, 895, 2.5, 8, RED, 0.92))
    s.append("</g>")
    s.append(rule(281, 900, 1.4, 250, GOLD))
    s.append(rule(330, 1000, 300, 1.6, NAVY, 0.10))
    s.append(rule(330, 1042, 300, 1.6, NAVY, 0.10))
    s.append("</g>")

    # ── business cards ─────────────────────────────────────────────────────
    s.append('<g filter="url(#shC)" transform="rotate(-9 1240 1010)">')
    s.append('<rect x="1120" y="930" width="250" height="162" rx="2" fill="#FFFFFF"/>')
    s.append(rule(1120, 930, 250, 162, WHITE))
    s.append("</g>")
    s.append('<g filter="url(#shD)" transform="rotate(5 1180 985)">')
    s.append(f'<rect x="1060" y="905" width="250" height="162" rx="2" fill="url(#nvB)"/>')
    s.append('<g clip-path="url(#cardClip0)">')
    s.append(arc_stroke(1062, 1075, [86, 72], -100, -22, 5, GOLD, [1.0, 0.35]))
    s.append(streak(1140, 1068, 1280, 900, 1.6, 5, RED, 0.92))
    s.append("</g>")
    s.append("</g>")

    # ── pen ────────────────────────────────────────────────────────────────
    s.append('<g filter="url(#shD)" transform="translate(1290 1140) rotate(-34)">')
    s.append('<rect x="0" y="-15" width="330" height="30" rx="12" fill="url(#penG)"/>')
    s.append(rule(0, -15, 16, 30, "#050C14"))
    s.append(rule(96, -15, 9, 30, GOLD))
    s.append(rule(120, -15, 4, 30, TEAL))
    s.append('<path d="M 330 -15 L 372 -5 L 372 5 L 330 15 Z" fill="url(#tealG)"/>')
    s.append('<path d="M 372 -5 L 392 0 L 372 5 Z" fill="#C9CDD2"/>')
    s.append("</g>")
    return dict(body="".join(s), defs=defs, w=W, h=H, bleed=0, unit="")


# ═══════════════════════════════════════════════════════════════════════════
#  08 — ENVIRONMENTAL GRAPHICS  (elevation view, 1600 × 1200 px)
# ═══════════════════════════════════════════════════════════════════════════
def environmental():
    W, H = 1600, 1000
    FLOOR = 830
    defs = (p_navy("envA") + p_navy("envB") + p_navy("envC") +
            p_shadow("wallA", 0, 18, 24, 0.24) + p_shadow("wallB", 0, 12, 16, 0.20) +
            p_shadow("wallC", 0, 9, 12, 0.16) +
            '<linearGradient id="wall" x1="0" y1="0" x2="0.15" y2="1">'
            '<stop offset="0" stop-color="#FAFAF8"/>'
            '<stop offset="0.62" stop-color="#F1F1ED"/>'
            '<stop offset="1" stop-color="#E8E8E3"/></linearGradient>'
            '<linearGradient id="ceil" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#0D1B2A" stop-opacity="0.09"/>'
            '<stop offset="1" stop-color="#0D1B2A" stop-opacity="0"/></linearGradient>'
            '<linearGradient id="floor" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#DCDCD6"/><stop offset="1" stop-color="#C8C8C2"/></linearGradient>'
            '<linearGradient id="alu" x1="0" y1="0" x2="1" y2="0.5">'
            '<stop offset="0" stop-color="#FFFFFF"/><stop offset="0.55" stop-color="#F2F3F4"/>'
            '<stop offset="1" stop-color="#E1E3E5"/></linearGradient>'
            '<clipPath id="pan1"><rect x="70" y="150" width="900" height="380"/></clipPath>'
            '<clipPath id="pan2"><rect x="1090" y="170" width="300" height="172"/></clipPath>'
            '<clipPath id="plateBand"><rect x="1090" y="170" width="54" height="172"/></clipPath>'
            '<clipPath id="pan3"><rect x="1010" y="430" width="440" height="185"/></clipPath>'
            '<clipPath id="pan4"><rect x="1470" y="380" width="120" height="450"/></clipPath>')
    s = [f'<rect width="{W}" height="{H}" fill="url(#wall)"/>']
    s.append(f'<rect x="0" y="0" width="{W}" height="150" fill="url(#ceil)"/>')
    s.append(f'<rect x="0" y="{FLOOR}" width="{W}" height="{H-FLOOR}" fill="url(#floor)"/>')
    s.append(f'<rect x="0" y="{FLOOR-4}" width="{W}" height="4" fill="#BEBEB8"/>')

    # ── reception backwall ────────────────────────────────────────────────
    s.append('<g filter="url(#wallA)">')
    s.append(f'<rect x="70" y="150" width="900" height="380" fill="url(#envA)"/>')
    s.append('<g clip-path="url(#pan1)">')
    s.append(arc_stroke(78, 560, [240, 274, 205], -101, -20, 12.5, GOLD, [1.0, 0.26, 0.12]))
    s.append(streak(615, 548, 1030, 168, 6, 15, RED, 0.90))
    s.append("</g>")
    s.append('</g>')

    # ── door plate (brushed aluminium) ────────────────────────────────────
    s.append('<g filter="url(#wallB)">')
    s.append('<rect x="1090" y="170" width="300" height="172" fill="url(#alu)"/>')
    s.append('<g clip-path="url(#plateBand)">')
    s.append(f'<rect x="1090" y="170" width="54" height="172" fill="url(#envB)"/>')
    s.append(arc_stroke(1094, 344, [68, 54], -100, -26, 4.5, GOLD, [1.0, 0.30]))
    s.append("</g>")
    s.append('</g>')

    # ── wayfinding panel ──────────────────────────────────────────────────
    s.append('<g filter="url(#wallC)">')
    s.append(f'<rect x="1010" y="430" width="440" height="185" fill="url(#envC)"/>')
    s.append('<g clip-path="url(#pan3)">')
    s.append(arc_stroke(1016, 622, [130, 156], -100, -24, 8.5, GOLD, [0.95, 0.24]))
    s.append("</g>")
    s.append('</g>')
    s.append(chevron(1290, 522, 36, 44, 10, GOLD, 1.0))
    s.append(chevron(1344, 522, 36, 44, 10, GOLD, 0.50))

    # ── reception counter (scale reference, no brand colour) ──────────────
    s.append('<g filter="url(#wallB)">')
    s.append('<rect x="170" y="700" width="540" height="130" fill="#ECECE7"/>')
    s.append('<rect x="170" y="700" width="540" height="22" fill="#F9F9F5"/>')
    s.append('</g>')
    s.append('<rect x="170" y="722" width="540" height="3" fill="#CBCBC5"/>')
    s.append('<rect x="200" y="752" width="480" height="1.5" fill="#DADAD4"/>')
    s.append('<rect x="170" y="826" width="540" height="4" fill="#C4C4BE"/>')

    # ── floor totem ───────────────────────────────────────────────────────
    s.append('<g filter="url(#wallA)">')
    s.append(f'<rect x="1470" y="380" width="120" height="450" fill="url(#envA)"/>')
    s.append('<g clip-path="url(#pan4)">')
    s.append(arc_stroke(1476, 830, [110, 134], -100, -22, 6, GOLD, [1.0, 0.24]))
    s.append(streak(1520, 820, 1584, 392, 2.2, 7, RED, 0.92))
    s.append(f'<rect x="1470" y="758" width="120" height="72" fill="{TEAL}"/>')
    s.append("</g>")
    s.append('</g>')
    return dict(body="".join(s), defs=defs, w=W, h=H, bleed=0, unit="")

register(stationery_set, "01-office-stationery-set")
register(environmental, "08-environmental-graphics")

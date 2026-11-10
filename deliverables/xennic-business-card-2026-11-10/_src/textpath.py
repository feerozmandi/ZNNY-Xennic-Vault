#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Persian/Latin text → outlined SVG paths (HarfBuzz shaping + fontTools outlines).

Why out­lines: the delivered artwork must look identical on any machine, without
depending on an installed font. Vazirmatn is used as the stand-in for IRANSans
(the brand's first choice, which is not freely redistributable) — see README.
"""

import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.misc.transform import Transform

_CACHE = {}


def _load(font_path):
    if font_path not in _CACHE:
        blob = hb.Blob.from_file_path(font_path)
        face = hb.Face(blob)
        font = hb.Font(face)
        tt = TTFont(font_path)
        _CACHE[font_path] = (face, font, tt.getGlyphSet(), tt.getGlyphOrder())
    return _CACHE[font_path]


def measure(text, font_path, size, tracking=0.0, features=None, direction=None):
    """Advance width of the shaped run, in millimetres."""
    face, font, gs, order = _load(font_path)
    s = size / face.upem
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    if direction:
        buf.direction = direction
    hb.shape(font, buf, features or {})
    n = len(buf.glyph_positions)
    return sum(p.x_advance for p in buf.glyph_positions) * s + tracking * max(0, n - 1)


def text_path(text, font_path, size, x, y, anchor="start", tracking=0.0,
              features=None, decimals=3, direction=None):
    """Return (svg path data, advance width in mm) for a shaped text run.

    (x, y) is the baseline anchor in millimetres; anchor ∈ {start, middle, end}.
    """
    face, font, gs, order = _load(font_path)
    s = size / face.upem
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    if direction:
        buf.direction = direction
    hb.shape(font, buf, features or {})
    infos, poss = buf.glyph_infos, buf.glyph_positions
    width = sum(p.x_advance for p in poss) * s + tracking * max(0, len(poss) - 1)
    if anchor == "end":
        pen_x = x - width
    elif anchor == "middle":
        pen_x = x - width / 2
    else:
        pen_x = x
    pen_y = y
    chunks = []
    for info, pos in zip(infos, poss):
        glyph = gs[order[info.codepoint]]
        try:
            spen = SVGPathPen(gs, ntos=lambda v: f"{v:.{decimals}f}")
        except TypeError:                      # older fontTools
            spen = SVGPathPen(gs)
        tp = TransformPen(spen, Transform(s, 0, 0, -s,
                                          pen_x + pos.x_offset * s,
                                          pen_y - pos.y_offset * s))
        glyph.draw(tp)
        cmd = spen.getCommands()
        if cmd:
            chunks.append(cmd)
        pen_x += pos.x_advance * s + tracking
    return " ".join(chunks), width


def text_svg(text, font_path, size, x, y, fill, anchor="start", tracking=0.0,
             features=None, opacity=None, extra="", direction=None):
    d, width = text_path(text, font_path, size, x, y, anchor, tracking, features,
                          direction=direction)
    op = f' opacity="{opacity}"' if opacity is not None else ""
    return (f'<path d="{d}" fill="{fill}"{op}{extra}/>', width)

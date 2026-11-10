#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Presentation board: the two card sides side by side on a neutral surface."""

import base64
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "png"))


def data_uri(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def board(front_svg, back_svg):
    W, H = 1680, 900
    cw, ch = 640.0, 640.0 * 55 / 85
    x1, x2, y = 110.0, 1680 - 110 - cw, (900 - 640 * 55 / 85) / 2
    f = data_uri(front_svg)
    b = data_uri(back_svg)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
 width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <radialGradient id="bg" cx="0.45" cy="0.35" r="0.85">
    <stop offset="0" stop-color="#FCFCFA"/><stop offset="0.62" stop-color="#F2F2EF"/>
    <stop offset="1" stop-color="#E6E6E2"/></radialGradient>
  <filter id="sh" x="-25%" y="-25%" width="150%" height="150%">
    <feDropShadow dx="0" dy="16" stdDeviation="18" flood-color="#0D1B2A" flood-opacity="0.26"/>
  </filter>
  <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.10"/>
    <stop offset="1" stop-color="#000000" stop-opacity="0.06"/></linearGradient>
</defs>
<rect width="{W}" height="{H}" fill="url(#bg)"/>
<g filter="url(#sh)">
  <image x="{x1}" y="{y}" width="{cw}" height="{ch}" xlink:href="data:image/svg+xml;base64,{f}"/>
</g>
<g filter="url(#sh)">
  <image x="{x2}" y="{y}" width="{cw}" height="{ch}" xlink:href="data:image/svg+xml;base64,{b}"/>
</g>
<rect width="{W}" height="{H}" fill="url(#edge)"/>
</svg>
'''


if __name__ == "__main__":
    front = os.path.join("/tmp", "xennic-business-card-front.preview.svg")
    back = os.path.join("/tmp", "xennic-business-card-back.preview.svg")
    out = os.path.join("/tmp", "card-pair.preview.svg")
    with open(out, "w") as fp:
        fp.write(board(front, back))
    print(out)

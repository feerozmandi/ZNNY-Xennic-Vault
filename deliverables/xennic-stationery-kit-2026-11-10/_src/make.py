#!/usr/bin/env python3
"""Build every artwork: python3 make.py && node render.mjs"""
import build_svg as B

if __name__ == "__main__":
    for name, fn in B.REG.items():
        src, png = B.emit(name, fn)
        print(f"svg  -> ../svg/{name}.svg")
        print(f"prev -> {src}")

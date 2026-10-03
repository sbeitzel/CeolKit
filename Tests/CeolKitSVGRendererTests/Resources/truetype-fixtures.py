#!/usr/bin/env python3
"""Builds the TrueType fixtures for `TrueTypeOutlineTests` (issue #189).

Every outline here is drawn for the test and is CeolKit's own, so the fixtures carry no
third-party licence. Run from this directory with fontTools installed:

    python3 truetype-fixtures.py

It writes:

  CeolKitTest-Short.ttf   one face, `loca` in the short format
  CeolKitTest-Long.ttf    the same glyphs, `loca` in the long format
  CeolKitTest.ttc         a collection of two faces: CeolKitTest-Regular (fsType 0) and
                          CeolKitTest-Restricted (fsType 0x0002, restricted embedding)
  truetype-reference.json each glyph's outline as fontTools draws it: the oracle the Swift
                          parser is checked against

The reference is fontTools' reading of the same bytes, with quadratic runs split into
single `Q` segments and the implied on-curve points between consecutive off-curve points
made explicit, which is what `OpenTypeFont` emits.
"""

import json
from array import array

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import (
    Glyph, GlyphComponent, GlyphCoordinates, flagOnCurve,
)
from fontTools.ttLib.tables import ttProgram
from fontTools.ttLib.ttCollection import TTCollection

ON, OFF = flagOnCurve, 0


def simple(contours, program=b""):
    """A simple glyph from contours of (x, y, on_curve) points."""
    g = Glyph()
    points, flags, ends = [], [], []
    for contour in contours:
        for x, y, on in contour:
            points.append((x, y))
            flags.append(ON if on else OFF)
        ends.append(len(points) - 1)
    g.coordinates = GlyphCoordinates(points)
    g.flags = array("B", flags)
    g.endPtsOfContours = ends
    g.numberOfContours = len(contours)
    g.program = ttProgram.Program()
    g.program.fromBytecode(program)
    return g


def component(name, dx=0, dy=0, transform=None, points=None):
    c = GlyphComponent()
    c.glyphName = name
    c.flags = 0
    if points is not None:
        c.firstPt, c.secondPt = points
    else:
        c.x, c.y = dx, dy
    if transform is not None:
        c.transform = transform
    return c


def composite(*components):
    g = Glyph()
    g.numberOfContours = -1
    g.components = list(components)
    return g


def glyphs(program):
    # A triangle of on-curve points only, with a counter.
    a = simple([
        [(0, 0, True), (300, 700, True), (600, 0, True)],
        [(200, 100, True), (400, 100, True), (300, 400, True)],
    ], program=program)
    # On-curve start, then a run of four off-curve points: three implied midpoints.
    d = simple([[(100, 0, True), (100, 700, True), (400, 700, False), (700, 500, False),
                 (700, 200, False), (400, 0, False)]])
    # Every point off-curve: the contour starts at an implied point.
    o = simple([[(300, 0, False), (0, 350, False), (300, 700, False), (600, 350, False)]])
    # Starts off-curve, but has on-curve points further round.
    c = simple([[(500, 700, False), (100, 700, True), (100, 0, True), (500, 0, False),
                 (600, 350, True)]])
    acute = simple([[(0, 0, True), (150, 150, True), (100, 0, True)]])
    return {
        ".notdef": simple([[(0, 0, True), (0, 700, True), (500, 700, True), (500, 0, True)]]),
        "space": simple([]),
        "A": a, "D": d, "O": o, "C": c, "acute": acute,
        # Byte offsets, and a word offset: 750 does not fit a signed byte.
        "Aacute": composite(component("A"), component("acute", 250, 750)),
        # WE_HAVE_A_SCALE.
        "Adieresis": composite(component("A", 10, -5, transform=[[0.5, 0], [0, 0.5]])),
        # WE_HAVE_AN_X_AND_Y_SCALE.
        "Aring": composite(component("A", 0, 0, transform=[[1.25, 0], [0, 0.75]])),
        # WE_HAVE_A_TWO_BY_TWO.
        "AE": composite(component("A", 100, 0, transform=[[1, 0.25], [-0.5, 1]])),
        # A composite of a composite.
        "Aringacute": composite(component("Aacute", 0, 0), component("acute", 0, 900)),
        # Point matching: read as a diagnostic-free skip of that component.
        "Egrave": composite(component("A"), component("acute", points=(2, 1))),
    }


CMAP = {
    0x20: "space", 0x41: "A", 0x44: "D", 0x4F: "O", 0x43: "C", 0xB4: "acute",
    0xC1: "Aacute", 0xC4: "Adieresis", 0xC5: "Aring", 0xC6: "AE", 0x1FA: "Aringacute",
    0xC8: "Egrave",
}
ORDER = [".notdef", "space", "A", "D", "O", "C", "acute", "Aacute", "Adieresis", "Aring",
         "AE", "Aringacute", "Egrave"]


def build(ps_name, style, fs_type=0, program=b""):
    """`program` is hinting bytecode for "A": never run, only there to be skipped, and the
    way the long-`loca` face gets an odd glyph length — which fontTools can only store in
    long offsets."""
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(ORDER)
    fb.setupCharacterMap(CMAP)
    fb.setupGlyf(glyphs(program))
    if program:
        fb.font["glyf"].padding = 0  # never pad, so an odd-length glyph stays odd
    # Left side bearings equal to each glyph's xMin, as a real face has them: fontTools
    # draws a glyph shifted by the difference, and the oracle must be the raw outline.
    glyf = fb.font["glyf"]
    for name in ORDER:
        glyf[name].recalcBounds(glyf)
    fb.setupHorizontalMetrics({n: (700 if n != "space" else 250,
                                   getattr(glyf[n], "xMin", 0)) for n in ORDER})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "CeolKitTest", "styleName": style, "psName": ps_name})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200,
                fsType=fs_type)
    fb.setupPost()
    return fb.font


class Recorder(BasePen):
    """Records an outline as explicit M/L/Q/Z segments."""

    def __init__(self, glyph_set):
        super().__init__(glyph_set)
        self.out = []

    def _moveTo(self, p):
        self.out.append(["M", *p])

    def _lineTo(self, p):
        self.out.append(["L", *p])

    def _qCurveToOne(self, p1, p2):
        self.out.append(["Q", *p1, *p2])

    def _curveToOne(self, p1, p2, p3):
        raise AssertionError("no cubic outlines in these fixtures")

    def _closePath(self):
        self.out.append(["Z"])


def reference(path):
    font = TTFont(path)
    glyph_set = font.getGlyphSet()
    out = {
        "unitsPerEm": font["head"].unitsPerEm,
        "indexToLocFormat": font["head"].indexToLocFormat,
        "fsType": font["OS/2"].fsType,
        "postScriptName": font["name"].getDebugName(6),
        "glyphs": {},
    }
    for code, name in CMAP.items():
        if name == "Egrave":
            continue  # point matching: fontTools resolves it, CeolKit skips it
        pen = Recorder(glyph_set)
        glyph_set[name].draw(pen)
        out["glyphs"][str(code)] = {"name": name, "advance": glyph_set[name].width,
                                    "segments": pen.out}
    return out


build("CeolKitTest-Regular", "Regular").save("CeolKitTest-Short.ttf")
# SVTCA[0] instructions (0x00): one or two of them, whichever leaves "A" an odd length.
for program in (b"\x00", b"\x00\x00"):
    build("CeolKitTest-Regular", "Regular", program=program).save("CeolKitTest-Long.ttf")
    if TTFont("CeolKitTest-Long.ttf")["head"].indexToLocFormat == 1:
        break

collection = TTCollection()
collection.fonts = [build("CeolKitTest-Regular", "Regular"),
                    build("CeolKitTest-Restricted", "Restricted", fs_type=0x0002)]
collection.save("CeolKitTest.ttc")

refs = {name: reference(name) for name in ["CeolKitTest-Short.ttf", "CeolKitTest-Long.ttf"]}
for path in refs:
    assert refs[path]["indexToLocFormat"] == (1 if "Long" in path else 0), path
with open("truetype-reference.json", "w") as f:
    json.dump(refs, f, indent=1, sort_keys=True)

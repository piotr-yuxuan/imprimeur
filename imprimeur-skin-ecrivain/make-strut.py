# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
"""Give the skin's two spaces the vertical metrics of a strut.

    make-strut.py FILE

The first available font of a stack decides each line box's strut, whichever font
draws the letters.  With an ascent equal to its descent, a line of height L has its
baseline at exactly L / 2, at any font size, in any hand, in Chromium and in WebKit:
each engine rounds the two alike.

They are 0.518 em, and not next to nothing.  With none, inline text has a box of no
height: WebKit then paints a selection half a line off, hit-tests a drag into the next
line, gives Range rectangles of nothing, and its find highlight, which the xwidget's
search uses, shows nothing at all.

Why 0.518 and no round half.  On Linux each engine moves a pixel from the ascent to the
descent when the descent has rounded down, which would lift the line by that pixel.  The
sheet sets its block sizes as a whole number of pixels over 0.519, the hands' x-height,
so that 0.518 of each lands just under a whole number, rounds up, and never does so.
"""

import sys

from fontTools.ttLib import TTFont

SHARE = 0.518
USE_TYPO_METRICS = 1 << 7

path = sys.argv[1]
font = TTFont(path, recalcTimestamp=False)
unit = round(font["head"].unitsPerEm * SHARE)
hhea, os2 = font["hhea"], font["OS/2"]
hhea.ascent, hhea.descent, hhea.lineGap = unit, -unit, 0
os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = unit, -unit, 0
os2.usWinAscent, os2.usWinDescent = unit, unit
os2.fsSelection |= USE_TYPO_METRICS
font.save(path)

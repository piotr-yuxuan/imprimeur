# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
"""Cut a static face from a font, under a new family name.

    make-cut.py SOURCE OUT FAMILY LABEL WEIGHT ITALIC [AXIS=VALUE ...]

An installed variable font exposes no axes on Linux, so each setting of the axes that
the sheet needs is a family of its own, and each weight a face in it.  ITALIC is 0 or 1.
Copyright, licence and their URLs stay as the source has them; every other record that
names the source's family names FAMILY, as a font may reserve its name.
"""

import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

NOTICES = (0, 7, 13, 14)
REPLACED = (1, 2, 3, 4, 6, 16, 17, 21, 22, 25)
FIRST_INSTANCE_NAME = 256
ITALIC_BIT, REGULAR_BIT = 1 << 0, 1 << 6
MAC_ITALIC = 1 << 1

source, out, family, label, weight, italic, *axes = sys.argv[1:]
font = TTFont(source, recalcTimestamp=False)
if "fvar" in font:
    settings = (setting.split("=") for setting in axes)
    pinned = {axis: float(value) for axis, value in settings}
    font = instancer.instantiateVariableFont(font, pinned, inplace=False)

names = font["name"]
old = names.getDebugName(16) or names.getDebugName(1)
old_compact, new_compact = old.replace(" ", ""), family.replace(" ", "")
for record in list(names.names):
    if record.nameID in REPLACED or record.nameID >= FIRST_INSTANCE_NAME:
        names.removeNames(nameID=record.nameID)
    elif record.nameID not in NOTICES:
        text = record.toUnicode().replace(old, family).replace(old_compact, new_compact)
        names.setName(
            text, record.nameID, record.platformID, record.platEncID, record.langID
        )
compact = f"{new_compact}-{label}"
for name_id, text in {
    1: f"{family} {label}",
    2: "Italic" if italic == "1" else "Regular",
    3: compact,
    4: f"{family} {label}",
    6: compact,
    16: family,
    17: label,
}.items():
    names.setName(text, name_id, 3, 1, 0x409)

os2, head = font["OS/2"], font["head"]
os2.usWeightClass = int(weight)
if italic == "1":
    os2.fsSelection = (os2.fsSelection | ITALIC_BIT) & ~REGULAR_BIT
    head.macStyle |= MAC_ITALIC
else:
    os2.fsSelection &= ~ITALIC_BIT
    head.macStyle &= ~MAC_ITALIC
font.save(out)

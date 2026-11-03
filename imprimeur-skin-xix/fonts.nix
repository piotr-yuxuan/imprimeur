# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of the skin XIX, for fonts.packages or home.packages.  Every face that a
# text stack names holds smcp and c2sc but Theano Didot, whose small capitals come from
# Bodoni Moda.  The attribute oldstandard is 2.2, without them: it must not be used here.
{pkgs}: [
  # About eighty cuts under one family name; the sheet takes Regular and Italic by name.
  pkgs.junicode # Junicode: text, titles, lettrine and their ligatures. OFL-1.1
  pkgs.bodoni-moda # Bodoni Moda: a text face, and next in the stack. OFL-1.1
  pkgs.theano # Theano Didot: a text face. OFL-1.1
  pkgs.eb-garamond # EB Garamond 12: a text face. OFL-1.1
  pkgs.courier-prime # Courier Prime: code. OFL-1.1
  pkgs.dejavu_fonts # DejaVu Sans Mono: the arrows, Greek and box drawing of code.
  pkgs.libertinus # Libertinus Serif: a text face, floor of the stack, narrow space; Math. OFL-1.1
]

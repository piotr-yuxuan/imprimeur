# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of Briefing, for fonts.packages or home.packages.  Code asks first for the
# family of Emacs's default face, so these give it a face only when Emacs names none.
{pkgs}: [
  pkgs.inter # Inter, Inter Display: text, tables, labels, chips; the title and first-level headings. OFL-1.1
  pkgs.fira-math # Fira Math: MathML, the one sans face with a MATH table. OFL-1.1
  pkgs.adwaita-fonts # Adwaita Mono: code when Emacs names no family; it brings Adwaita Sans. OFL-1.1
]

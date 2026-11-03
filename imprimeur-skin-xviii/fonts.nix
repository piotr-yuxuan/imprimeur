# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of the skin XVIII, for fonts.packages or home.packages.  nixpkgs has no
# attribute for Baskervville alone, so its files come one by one, by hash, from the
# revision of google/fonts that nixpkgs pins.
{pkgs}: let
  revision = "5174b3333331c966c38f4355d50b03ca1c1df2f9";
  fetched = name: file: hash:
    pkgs.fetchurl {
      inherit name hash;
      url = "https://raw.githubusercontent.com/google/fonts/${revision}/ofl/baskervville/${file}";
    };
  roman = fetched "Baskervville-wght.ttf" "Baskervville%5Bwght%5D.ttf" "sha256-oIvPmIODs0Sqz9NDZajNQIpKlmXKrxncDXFqk4M6D6c=";
  italic = fetched "Baskervville-Italic-wght.ttf" "Baskervville-Italic%5Bwght%5D.ttf" "sha256-J5/1PtXHM++rsgY0Wvh/rOHBN7irJmcpjWzyKOv/vwE=";
  licence = fetched "OFL.txt" "OFL.txt" "sha256-k+aNWqdLHTGUomw61AA7FAWKpIjEhhQWutgSWpbc8dk=";
  baskervville = pkgs.runCommandLocal "baskervville-1.100" {} ''
    install -Dm444 ${roman} "$out/share/fonts/truetype/Baskervville[wght].ttf"
    install -Dm444 ${italic} "$out/share/fonts/truetype/Baskervville-Italic[wght].ttf"
    install -Dm444 ${licence} "$out/share/licenses/baskervville/OFL.txt"
  '';
in [
  baskervville # Baskervville: text, titles and lettrines by default. OFL-1.1
  pkgs.junicode # Junicode: the other face, with long s; the signs Baskervville lacks. OFL-1.1
  pkgs.courier-prime # Courier Prime: code. OFL-1.1
  pkgs.libertinus # Libertinus Math: maths; Libertinus Serif: floor of the stack. OFL-1.1
]

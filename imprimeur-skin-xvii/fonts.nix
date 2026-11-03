# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of the skin XVII, for fonts.packages or home.packages.  nixpkgs has no
# attribute for IM Fell alone, so its files come one by one, by hash, from the revision
# of google/fonts that nixpkgs pins.
{pkgs}: let
  revision = "5174b3333331c966c38f4355d50b03ca1c1df2f9";
  fetched = family: file: hash:
    pkgs.fetchurl {
      inherit hash;
      name = file;
      url = "https://raw.githubusercontent.com/google/fonts/${revision}/ofl/${family}/${file}";
    };
  englishRoman = fetched "imfellenglish" "IMFeENrm28P.ttf" "sha256-/pcFu95Rr4AnGSRtRgjQjTe96VarmdmlkNqZalIhokw=";
  englishItalic = fetched "imfellenglish" "IMFeENit28P.ttf" "sha256-R8113OVLHy4IMTWdItXmiPUZ1orkVwa2ZP0xD9DjzPc=";
  englishSmallCapitals = fetched "imfellenglishsc" "IMFeENsc28P.ttf" "sha256-ECMk+1Q0u12nljUzQmsK1EyFu8nndVBnU1ydEUZKF2s=";
  canonRoman = fetched "imfellfrenchcanon" "IMFeFCrm28P.ttf" "sha256-P+p2kypi/5T/k/HPlbM4MwZ0347NFulhEWo0amSQDdM=";
  canonItalic = fetched "imfellfrenchcanon" "IMFeFCit28P.ttf" "sha256-xS4ewnJRtM1mY+OEFTgEBOzzmyzutVNdQFmFkKUR5Fk=";
  licence = fetched "imfellenglish" "OFL.txt" "sha256-KjylAfxNXvytl5hTHj4GliseIMYORk9svWwXYwESx3M=";
  imFell = pkgs.runCommandLocal "im-fell-3.00" {} ''
    install -Dm444 ${englishRoman} $out/share/fonts/truetype/IMFeENrm28P.ttf
    install -Dm444 ${englishItalic} $out/share/fonts/truetype/IMFeENit28P.ttf
    install -Dm444 ${englishSmallCapitals} $out/share/fonts/truetype/IMFeENsc28P.ttf
    install -Dm444 ${canonRoman} $out/share/fonts/truetype/IMFeFCrm28P.ttf
    install -Dm444 ${canonItalic} $out/share/fonts/truetype/IMFeFCit28P.ttf
    install -Dm444 ${licence} $out/share/licenses/im-fell/OFL.txt
  '';
  # nixpkgs leaves this font inside TeX Live, off fontconfig's path.
  garamondMath = pkgs.runCommandLocal "garamond-math" {} ''
    install -Dm444 ${pkgs.texlivePackages.garamond-math.tex}/fonts/opentype/public/garamond-math/Garamond-Math.otf \
      $out/share/fonts/opentype/Garamond-Math.otf
  '';
in [
  imFell # IM Fell English and its small capitals: text; IM Fell French Canon: titles. OFL-1.1
  pkgs.eb-garamond # EB Garamond 12: the other face, figures, flowers; EB Garamond Initials. OFL-1.1
  pkgs.garamond-libre # Garamond Libre: the plain face. X11
  pkgs.courier-prime # Courier Prime: code. OFL-1.1
  garamondMath # Garamond-Math: mathematics. OFL-1.1
  pkgs.libertinus # Libertinus Serif: narrow space, floor of the stack; Libertinus Math. OFL-1.1
]

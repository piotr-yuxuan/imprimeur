# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of the skin XIX, for fonts.packages or home.packages.  Every face that a
# text stack names holds smcp and c2sc but Theano Didot, whose small capitals come from
# Bodoni Moda.  The attribute oldstandard is 2.2, without them: it must not be used here.
#
# An installed variable font exposes no axes on Linux, so Bodoni Moda's optical sizes are
# three families cut by make-cut.py, one for each size that the sheet draws.
#
# nixpkgs has neither Playfair nor Playfair Display alone, so they come from the google/fonts
# revision that nixpkgs's own google-fonts pins, file by file, rather than through
# google-fonts.override, which would fetch that whole repository.
{pkgs}: let
  revision = "5174b3333331c966c38f4355d50b03ca1c1df2f9";
  google = directory: file: hash:
    pkgs.fetchurl {
      inherit hash;
      name = builtins.replaceStrings ["[" "]" ","] ["-" "" "-"] file;
      url = "https://raw.githubusercontent.com/google/fonts/${revision}/ofl/${directory}/${builtins.replaceStrings ["[" "]"] ["%5B" "%5D"] file}";
    };
  python = pkgs.python3.withPackages (packages: [packages.fonttools]);

  # A family as google/fonts has it: its directory, its licence, and its files by hash.
  fetched = directory: family: licence: files:
    pkgs.runCommandLocal "imprimeur-font-${directory}" {} (
      ''
        install -Dm444 ${google directory "OFL.txt" licence} "$out/share/licenses/${family}/OFL.txt"
      ''
      + pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList (file: hash: ''
          install -Dm444 ${google directory file hash} "$out/share/fonts/truetype/${file}"
        '')
        files)
    );

  bodoniLicence = google "bodonimoda" "OFL.txt" "sha256-kx3+LgzTyUQylfXB11S4qEA78GDfUMHVkAJnreg9AEY=";
  bodoni = "${pkgs.bodoni-moda}/share/fonts/truetype";
in [
  # About eighty cuts under one family name; the sheet takes Regular and Italic by name.
  pkgs.junicode # Junicode: text, titles, lettrine and their ligatures. OFL-1.1
  pkgs.bodoni-moda # Bodoni Moda: a text face, and next in the stack. OFL-1.1
  # XIX Bodoni 40, 20 and 17: the title, the text, and notes and captions under the
  # optical text face. OFL-1.1, from Bodoni Moda
  (pkgs.runCommandLocal "imprimeur-font-xix-bodoni" {nativeBuildInputs = [python];} (
    ''
      install -Dm444 ${bodoniLicence} "$out/share/licenses/XIX Bodoni/OFL.txt"
      mkdir -p "$out/share/fonts/truetype"
    ''
    + pkgs.lib.concatMapStrings (size: ''
      python3 -I ${./make-cut.py} "${bodoni}/BodoniModa[opsz,wght].ttf" \
        "$out/share/fonts/truetype/XIXBodoni${size}-Regular.ttf" \
        "XIX Bodoni ${size}" Regular 400 0 opsz=${size} wght=400
      python3 -I ${./make-cut.py} "${bodoni}/BodoniModa-Italic[opsz,wght].ttf" \
        "$out/share/fonts/truetype/XIXBodoni${size}-Italic.ttf" \
        "XIX Bodoni ${size}" Italic 400 1 opsz=${size} wght=400
    '') ["40" "20" "17"]
  ))
  # Playfair: a text face. OFL-1.1
  (fetched "playfair" "Playfair" "sha256-fRa7sXN1vu+qTR0lxB+GDLFhyeYUtEr3kJg6n9cQJic=" {
    "Playfair[opsz,wdth,wght].ttf" = "sha256-M8/svJlIz56v5U3J820ZoDs5PPEiIbIL4jWSbRyh22E=";
    "Playfair-Italic[opsz,wdth,wght].ttf" = "sha256-rg16cqk4BJJQQMJ3tM1+Bgf0i7aNu85w49prWUn5Eco=";
  })
  # Playfair Display: a text face. OFL-1.1
  (fetched "playfairdisplay" "Playfair Display" "sha256-VmvoFPjpbpPfoWEBMxVX62tUZ+ngP2J8CRD+k8oSMA4=" {
    "PlayfairDisplay[wght].ttf" = "sha256-xA8ik3ZqUDvHDM6eUS74RKTMt8vN55L+LqMdGRkX2NY=";
    "PlayfairDisplay-Italic[wght].ttf" = "sha256-peJtxeLnf7KAOgvwL9T4HuE27I3qhjzNsMWaJjshN4s=";
  })
  # Old Standard 2.7a: a text face. TeX Live keeps it outside share/fonts. OFL-1.1, in
  # each font's own name table
  (pkgs.runCommandLocal "imprimeur-font-old-standard" {} ''
    install -Dm444 -t "$out/share/fonts/opentype" \
      ${pkgs.texlivePackages.oldstandard.tex}/fonts/opentype/public/oldstandard/*.otf
  '')
  pkgs.theano # Theano Didot: a text face. OFL-1.1
  pkgs.eb-garamond # EB Garamond 12: a text face. OFL-1.1
  pkgs.courier-prime # Courier Prime: code. OFL-1.1
  pkgs.dejavu_fonts # DejaVu Sans Mono: the arrows, Greek and box drawing of code.
  pkgs.libertinus # Libertinus Serif: a text face, floor of the stack, narrow space; Math. OFL-1.1
]

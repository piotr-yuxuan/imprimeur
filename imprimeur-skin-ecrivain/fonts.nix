# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of Écrivain, for fonts.packages or home.packages.  An installed variable font
# exposes no axes on Linux, so each setting of the axes that the sheet needs is a family
# here, cut by make-cut.py under a name of its own, and each weight a face in it.  Nothing
# is served.  Ecrivain Espace, two spaces whose vertical metrics make it the strut of every
# line, is what the letters' alignment with the ruling hangs on (make-strut.py).
#
# nixpkgs has none of Playwrite FR or Caveat alone, so they come from the google/fonts
# revision that nixpkgs's own google-fonts pins, file by file, rather than through
# google-fonts.override, which would fetch that whole repository (2.95 GB, measured).
{pkgs}: let
  revision = "5174b3333331c966c38f4355d50b03ca1c1df2f9";
  google = family: file: hash:
    pkgs.fetchurl {
      inherit hash;
      name = builtins.replaceStrings ["[" "]"] ["-" ""] file;
      url = "https://raw.githubusercontent.com/google/fonts/${revision}/ofl/${family}/${builtins.replaceStrings ["[" "]"] ["%5B" "%5D"] file}";
    };
  python = pkgs.python3.withPackages (packages: [packages.fonttools]);

  # A family: its licence, and each cut of SOURCE as a label, a weight, 0 or 1 for italic,
  # and the settings of its axes.
  cuts = family: licence: source: list:
    pkgs.runCommandLocal "imprimeur-font-${pkgs.lib.toLower (builtins.replaceStrings [" "] ["-"] family)}" {nativeBuildInputs = [python];} (
      ''
        install -Dm444 ${licence} "$out/share/licenses/${family}/OFL.txt"
        mkdir -p "$out/share/fonts/truetype"
      ''
      + pkgs.lib.concatMapStrings (cut: ''
        python3 -I ${./make-cut.py} "${source}" \
          "$out/share/fonts/truetype/${builtins.replaceStrings [" "] [""] family}-${cut.label}.ttf" \
          "${family}" ${cut.label} ${toString cut.weight} ${toString cut.italic} ${pkgs.lib.concatStringsSep " " cut.axes}
      '')
      list
    );
  cut = label: weight: italic: axes: {inherit label weight italic axes;};

  moderne = google "playwritefrmoderne" "PlaywriteFRModerne[wght].ttf" "sha256-isKBPbfeEpNblecSfIWpLmlLAwg743nbfOs6wgKw1QA=";
  trad = google "playwritefrtrad" "PlaywriteFRTrad[wght].ttf" "sha256-DyDdALpjncGekJXoI5p2Z9kpIsL9a2m9P/tgC5CuSEU=";
  caveat = google "caveat" "Caveat[wght].ttf" "sha256-C9trZgSC0xUxs5RYSfulkWs++GldpwJKnmue48QVeYg=";
  shantell = "${pkgs.shantell-sans}/share/fonts/truetype/ShantellSans[BNCE,INFM,SPAC,ital,wght].ttf";
  radon = "${pkgs.monaspace.variable}/share/fonts/truetype/Monaspace Radon Var.ttf";

  moderneLicence = google "playwritefrmoderne" "OFL.txt" "sha256-A3D1lGAghGsMpl5ElQ0RQR6jvTxMDXVZFkcPn5bNjLg=";
  tradLicence = google "playwritefrtrad" "OFL.txt" "sha256-A3D1lGAghGsMpl5ElQ0RQR6jvTxMDXVZFkcPn5bNjLg=";
  caveatLicence = google "caveat" "OFL.txt" "sha256-H52B0JQnPYLziYoe6LWYpxfQUOy/X/e+3hBbcEiAFXs=";
  shantellLicence = google "shantellsans" "OFL.txt" "sha256-6/zn0QTVl8OFtx6fv48OIDTnMyD4VwhhBdwmW4LAXKo=";
  radonLicence = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/githubnext/monaspace/v1.400/LICENSE";
    hash = "sha256-DoTl991vBedKAPL7goykPkidlU9VCf8PpDnqGMDTX+k=";
  };
  libertinusLicence = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/alerque/libertinus/v7.051/OFL.txt";
    hash = "sha256-mu7MgQfEiewewAaLAxPlMadg7fNJNwWzKrirghWoeU4=";
  };

  # The hand of Carnet or Ardoise: its axes, with a face and its italic for each weight.
  informal = family: axes: weights:
    cuts family shantellLicence shantell (pkgs.lib.concatMap (weight: [
        (cut "W${toString weight}" weight 0 (axes ++ ["wght=${toString weight}" "ital=0"]))
        (cut "W${toString weight}I" weight 1 (axes ++ ["wght=${toString weight}" "ital=1"]))
      ])
      weights);
in [
  # Cahier, the default: text 360, strong and headings 400. OFL-1.1
  (cuts "Ecrivain Cahier" moderneLicence moderne [
    (cut "W360" 360 0 ["wght=360"])
    (cut "W400" 400 0 ["wght=400"])
  ])
  # Cahier, the older school hand. OFL-1.1
  (cuts "Ecrivain Trad" tradLicence trad [
    (cut "W360" 360 0 ["wght=360"])
    (cut "W400" 400 0 ["wght=400"])
  ])
  # Carnet. OFL-1.1, from Shantell Sans
  (informal "Ecrivain Carnet" ["INFM=50" "BNCE=35" "SPAC=0"] [400 580 680])
  # Ardoise. OFL-1.1, from Shantell Sans
  (informal "Ecrivain Ardoise" ["INFM=60" "BNCE=45" "SPAC=0"] [400 580 720])
  # Notes; quotations, captions, notes and leaf numbers everywhere. OFL-1.1, from Caveat
  (cuts "Ecrivain Note" caveatLicence caveat [
    (cut "W500" 500 0 ["wght=500"])
    (cut "W600" 600 0 ["wght=600"])
    (cut "W700" 700 0 ["wght=700"])
  ])
  # All code; inline in Cahier 300; comments slanted. OFL-1.1, from Monaspace Radon, whose
  # reserved name a cut may not keep.
  (cuts "Ecrivain Code" radonLicence radon [
    (cut "W300" 300 0 ["wght=300" "wdth=100" "slnt=0"])
    (cut "W400" 400 0 ["wght=400" "wdth=100" "slnt=0"])
    (cut "W400I" 400 1 ["wght=400" "wdth=100" "slnt=-9"])
  ])
  # The strut of every line, and U+2002 and U+202F. OFL-1.1, from Libertinus Serif
  (pkgs.runCommandLocal "imprimeur-font-ecrivain-espace" {nativeBuildInputs = [python];} ''
    install -Dm444 ${libertinusLicence} "$out/share/licenses/Ecrivain Espace/OFL.txt"
    mkdir -p "$out/share/fonts/opentype"
    python3 -I -m fontTools.subset "${pkgs.libertinus}/share/fonts/opentype/LibertinusSerif-Regular.otf" \
      --unicodes=U+2002,U+202F --name-IDs='*' --output-file=strut.otf
    python3 -I ${./make-cut.py} strut.otf "$out/share/fonts/opentype/EcrivainEspace-Regular.otf" \
      "Ecrivain Espace" Regular 400 0
    python3 -I ${./make-strut.py} "$out/share/fonts/opentype/EcrivainEspace-Regular.otf"
  '')
  pkgs.fira-math # MathML: no hand holds a MATH table. OFL-1.1
]

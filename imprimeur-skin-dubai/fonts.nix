# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of Dubai, for fonts.packages or home.packages.  None is Dubai Font, whose licence
# forbids passing it on.
#
# Noto Kufi Arabic, Alexandria and Kufam are variable fonts that nixpkgs has as no attribute
# of their own: noto-fonts.override would give a Kufi with no Latin and fetch the whole Noto
# release, and google-fonts.override fetches that whole repository (2.95 GB).  So each comes
# file by file, whole, with its licence, from the google/fonts revision that nixpkgs's own
# google-fonts pins.  An installed variable font exposes no axes on Linux, so make-cut.py
# cuts each into the static weights that skin.css names, as a family of its own, which is
# what the sheet's local() asks for.
{pkgs}: let
  revision = "5174b3333331c966c38f4355d50b03ca1c1df2f9";
  google = directory: file: hash:
    pkgs.fetchurl {
      inherit hash;
      name = builtins.replaceStrings ["[" "]"] ["-" ""] file;
      url = "https://raw.githubusercontent.com/google/fonts/${revision}/ofl/${directory}/${builtins.replaceStrings ["[" "]"] ["%5B" "%5D"] file}";
    };
  python = pkgs.python3.withPackages (packages: [packages.fonttools]);

  # A family named FAMILY, cut from the variable FILE of DIRECTORY, with the licence beside
  # it: each cut a label and a weight, upright.
  cuts = family: directory: file: hash: licence: list:
    pkgs.runCommandLocal "imprimeur-font-${pkgs.lib.toLower (builtins.replaceStrings [" "] ["-"] family)}" {nativeBuildInputs = [python];} (
      ''
        install -Dm444 ${google directory "OFL.txt" licence} "$out/share/licenses/${family}/OFL.txt"
        mkdir -p "$out/share/fonts/truetype"
      ''
      + pkgs.lib.concatMapStrings (cut: ''
        python3 -I ${./make-cut.py} "${google directory file hash}" \
          "$out/share/fonts/truetype/${builtins.replaceStrings [" "] [""] family}-${cut.label}.ttf" \
          "${family}" ${cut.label} ${toString cut.weight} 0 wght=${toString cut.weight}
      '')
      list
    );
  cut = label: weight: {inherit label weight;};
in [
  # Dubai Kufi: Arabic text, from Noto Kufi Arabic 2.109 by the Monotype Design Team, David
  # Williams and Khaled Hosny. OFL-1.1
  (cuts "Dubai Kufi" "notokufiarabic" "NotoKufiArabic[wght].ttf"
    "sha256-SU9rYUadegKi1j8PxJMLsAc4jYz+VR3l65g1ThAIifM="
    "sha256-B/xwv+uYXMGoeoWH0KDIC6sRyGydw/2VtvDLMy+YPpY=" [
      (cut "Regular" 400)
      (cut "Bold" 700)
    ])
  # Dubai Alexandria: Arabic headings, from Alexandria 5.100 by Mohamed Gaber. OFL-1.1
  (cuts "Dubai Alexandria" "alexandria" "Alexandria[wght].ttf"
    "sha256-24rgO2LVWmWqTgQweHjfjADW5TiOSABjXL4OIrZBG2Q="
    "sha256-Vjcq7RnCcB9Q5ueEEQr1W/h5btUWSIBTJK0a2wo4YLs=" [
      (cut "SemiBold" 600)
      (cut "Bold" 700)
    ])
  # Dubai Kufam: the masthead, labels and key figures, from Kufam 1.301 by Wael Morcos
  # (Arabic) and Artur Schmal (Latin); its italic file is left out, as no role needs it.
  # OFL-1.1
  (cuts "Dubai Kufam" "kufam" "Kufam[wght].ttf"
    "sha256-8XqJtRjIM94olZjQZiu5oH0JzH11tweaFfEwX2JLvNo="
    "sha256-K3mhnUxhGEniMsNHH8oDVekJUmou2OBKyrkz1RaKAfE=" [
      (cut "Medium" 500)
      (cut "Bold" 700)
    ])
  pkgs.inter # Inter: Latin text, roman and italic. OFL-1.1
  # IBM Plex Sans Arabic and IBM Plex Sans 1.1.0: the face plex, static and hinted. OFL-1.1
  (pkgs.ibm-plex.override {families = ["sans-arabic" "sans"];})
  # Noto Sans Arabic: the Arabic-Indic digits under plex, and a fallback; the package is
  # not overridden, so that the binary cache has it. OFL-1.1
  pkgs.noto-fonts
  pkgs.cascadia-code # Cascadia Mono: code when Emacs names no family, Arabic included. OFL-1.1
  pkgs.fira-math # Fira Math: MathML. OFL-1.1
]

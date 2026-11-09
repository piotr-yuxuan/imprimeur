# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of Yaqut, for fonts.packages or home.packages.  About 230 MB, most of it Cascadia's
# and Noto's.  Every face is installed whole, as it is fetched, with its licence: nothing here
# cuts or changes one.
#
# Katibeh and Qahiri come from the google/fonts revision that XIX takes its faces from, file by
# file, rather than through google-fonts.override, which would fetch that whole repository.
# Raqq comes from its release by Alif Type.  Aref Ruqaa, chosen first for the glosses, is
# left out: the WebKit of an Emacs window draws it without its letters' dots.
{pkgs}: let
  revision = "5174b3333331c966c38f4355d50b03ca1c1df2f9";
  google = directory: file: hash:
    pkgs.fetchurl {
      inherit hash;
      url = "https://raw.githubusercontent.com/google/fonts/${revision}/ofl/${directory}/${file}";
    };

  # A family of one file as google/fonts has it, with its licence.
  fetched = directory: family: file: fontHash: licenceHash:
    pkgs.runCommandLocal "imprimeur-font-${directory}" {} ''
      install -Dm444 ${google directory "OFL.txt" licenceHash} "$out/share/licenses/${family}/OFL.txt"
      install -Dm444 ${google directory file fontHash} "$out/share/fonts/truetype/${file}"
    '';
in [
  # Amiri, Amiri Quran Colored: text, Latin, tables, glosses and the colophon; what the author
  # encloses in ﴿ ﴾. OFL-1.1
  pkgs.amiri
  # Katibeh: thuluth titles and headings. OFL-1.1
  (fetched "katibeh" "Katibeh" "Katibeh-Regular.ttf"
    "sha256-M07q21jrRCc0/n3qh0Esu9jD/QApQlJyOq3xmoUM8R8="
    "sha256-JR9lKC/0in6O8/tmH8mSVNmzsMNoQnyYse2/5Mpm6Ig=")
  # Qahiri: Kufic titles under the option title=kufi. OFL-1.1
  (fetched "qahiri" "Qahiri" "Qahiri-Regular.ttf"
    "sha256-aOMaJFqGE9i0nVX3zv/diLJvKrrOKp3QlKB2149TogM="
    "sha256-DxBx71fPPtBZcrR8yXnta7nOMjNC9KB9/RiOSe+uMZA=")
  # Raqq: Kufic titles under the option title=raqq.  AGPL-3.0-or-later, with no font exception:
  # its README says what that means for a document that embeds it.  Installed as released, its
  # licence and README beside it.
  (pkgs.stdenvNoCC.mkDerivation {
    pname = "imprimeur-font-raqq";
    version = "2.00";
    src = pkgs.fetchurl {
      url = "https://github.com/aliftype/raqq/releases/download/v2.00/Raqq-2.00.zip";
      hash = "sha256-uP3rF6aJq7FeJuoEsRxX8cDoi7ukFiZOsOcj9+VCHP4=";
    };
    nativeBuildInputs = [pkgs.unzip];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm444 -t "$out/share/fonts/truetype/raqq" Raqq.ttf LICENSE README.txt
      runHook postInstall
    '';
    meta = {
      description = "Raqq, a manuscript Kufic of the IIIrd century AH, by Alif Type";
      homepage = "https://aliftype.com/raqq";
      license = pkgs.lib.licenses.agpl3Plus;
      platforms = pkgs.lib.platforms.all;
    };
  })
  pkgs.noto-fonts # Noto Nastaliq Urdu: Persian under persian; Noto Naskh Arabic: a fallback. OFL-1.1
  pkgs.cascadia-code # Cascadia Mono: code, Arabic in code included. OFL-1.1
]

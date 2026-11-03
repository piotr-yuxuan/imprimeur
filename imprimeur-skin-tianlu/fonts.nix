# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The fonts of Tianlu, for fonts.packages or home.packages.  About 580 MB, most of it
# I.Ming's, LXGW's and TW-Kai's sets.
{pkgs}: let
  # A font of the Ministry of Education, one whole file, installed as it is fetched: CC BY-ND
  # 3.0 Taiwan, https://creativecommons.org/licenses/by-nd/3.0/tw/, credit 中華民國教育部.
  # Nothing may be derived from it, so nothing here touches it.  nixpkgs has only the unported
  # cc-by-nd-30, which it marks unfree, so a configuration needs a predicate for these names.
  moe = {
    name,
    version,
    rev,
    file,
    hash,
    description,
    homepage,
  }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "imprimeur-font-${name}";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/Jiehong/TW-fonts/${rev}/${file}";
        inherit hash;
      };
      dontUnpack = true;
      installPhase = ''
        runHook preInstall
        install -Dm644 "$src" "$out/share/fonts/truetype/${file}"
        runHook postInstall
      '';
      meta = {
        inherit description homepage;
        license = pkgs.lib.licenses.cc-by-nd-30;
        platforms = pkgs.lib.platforms.all;
      };
    };
in [
  # MOESongUN: traditional text under the preset song and the face moe, not set small.
  (moe {
    name = "moe-song";
    version = "2020-11-14";
    rev = "2020-11-14";
    file = "eduSong_Unicode.ttf";
    hash = "sha256-4aSOM1l8C5bDLS3ZbdzX1d1uS6Y/MXv+Edxfi6oVvOA=";
    description = "教育部標準宋體UN, the Song of the Ministry of Education, credit 中華民國教育部";
    homepage = "https://language.moe.gov.tw/material/info?m=9fe3fc3b-7fb3-4692-b6f0-7fe176d86ccb";
  })
  # TW-MOE-Std-Kai: traditional text under the preset siku and the face kai.
  (moe {
    name = "moe-kai";
    version = "5.1";
    rev = "2026-05-11";
    file = "edukai-5.1_20251208.ttf";
    hash = "sha256-4raxvR1jA2cqaNUFeh8eS1Nh49iEI3P/O9HHH7nqm5g=";
    description = "教育部標準楷書, the Kai of the Ministry of Education, credit 中華民國教育部";
    homepage = "https://language.moe.gov.tw/material/info?m=9fe3fe82-8bbf-44c0-961d-873ea079e284";
  })
  # Zhuque Fangsong (technical preview): simplified text under song, and the face fang.
  # OFL-1.1.  The family's name will change with a release.
  (pkgs.stdenvNoCC.mkDerivation {
    pname = "imprimeur-font-zhuque-fangsong";
    version = "0.212";
    src = pkgs.fetchzip {
      url = "https://github.com/TrionesType/zhuque/releases/download/v0.212/ZhuqueFangsong-v0.212.zip";
      stripRoot = false;
      hash = "sha256-see78H4ClZON4pujyUxvCjphFrKG73qBVEyhRoSxZ0Y=";
    };
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      find . -name '*.ttf' -exec install -Dm644 -t "$out/share/fonts/truetype" {} +
      runHook postInstall
    '';
    meta = {
      description = "Zhuque Fangsong, a technical preview";
      homepage = "https://github.com/TrionesType/zhuque";
      license = pkgs.lib.licenses.ofl;
      platforms = pkgs.lib.platforms.all;
    };
  })
  pkgs.cns11643-kai # TW-Kai: small text under the Song, what MOE Kai lacks, 注音. OFL-1.1
  pkgs.i-dot-ming # I.MingCP: text under juzhen and ming, marks over Fangsong. IPA v1.0
  pkgs.lxgw-wenkai # LXGW WenKai: simplified text under siku and kai. OFL-1.1
  pkgs.noto-fonts-cjk-serif # Noto Serif CJK: simplified Song, and what the Song lacks. OFL-1.1
  pkgs.noto-fonts-cjk-sans # Noto Sans Mono CJK: code. OFL-1.1
  pkgs.libertinus # Libertinus Serif and Math: Latin and mathematics. OFL-1.1
]

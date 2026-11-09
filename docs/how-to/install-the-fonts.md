# Install the fonts

A skin names fonts and ships none. Without them the page falls back through its stacks, and
nothing fails. Minitel asks for none: it takes Emacs's default family. Each `fonts.nix` was built
for the gallery, through `nix build`, on a scratch font path; the NixOS and Home Manager modules
below have not been switched to on a machine for this page.

## Under NixOS or Home Manager

1. Add this repository as a flake input. Its flake exports no packages, so it is a plain source:

   ```nix
   inputs.imprimeur = { url = "github:piotr-yuxuan/imprimeur"; flake = false; };
   ```

2. List the skins you want. Under NixOS:

   ```nix
   fonts.packages = lib.concatMap
     (skin: import "${inputs.imprimeur}/imprimeur-skin-${skin}/fonts.nix" { inherit pkgs; })
     [ "xix" "xviii" "xvii" "briefing" "ecrivain" "dubai" ];
   ```

   Under Home Manager, the same list goes in `home.packages`, with
   `fonts.fontconfig.enable = true`.

3. For Tianlu, add `"tianlu"` to the list, and allow the Ministry's two faces, which nixpkgs
   calls unfree. Read their terms first, in [its README](../../imprimeur-skin-tianlu/README.md#fonts).
   Its fonts take about 580 MB.

   ```nix
   nixpkgs.config.allowUnfreePredicate = pkg:
     builtins.elem (lib.getName pkg) [ "imprimeur-font-moe-song" "imprimeur-font-moe-kai" ];
   ```

4. For Yaqut, add `"yaqut"` to the list. Its fonts take about 230 MB. Raqq, which only its option
   `title` at `raqq` names, is under the AGPL: read [its README](../../imprimeur-skin-yaqut/README.md#fonts)
   before you embed it in a file.

5. Rebuild, then check a family: `fc-list | grep -i junicode` must name a file.

Écrivain's fonts take minutes to build once, for about 9 MB, since its cuts are made from their
variable fonts. Dubai's take seconds, and bring nixpkgs's `noto-fonts`, about 50 MB, for the
Arabic-Indic digits of its face `plex`.

## Without Nix

1. Look up the skin's families, in the table "Fonts" of its README:
   [XIX](../../imprimeur-skin-xix/README.md#fonts),
   [XVIII](../../imprimeur-skin-xviii/README.md#fonts),
   [XVII](../../imprimeur-skin-xvii/README.md#fonts),
   [Briefing](../../imprimeur-skin-briefing/README.md#fonts),
   [Écrivain](../../imprimeur-skin-ecrivain/README.md#fonts),
   [Tianlu](../../imprimeur-skin-tianlu/README.md#fonts),
   [Dubai](../../imprimeur-skin-dubai/README.md#fonts) or
   [Yaqut](../../imprimeur-skin-yaqut/README.md#fonts).
2. Install each by your system's means, under the family that the table names.
3. Check each with `fc-list`, and open a page in that skin.

Some cannot come this way as they stand: XIX's optical Bodoni, all of Écrivain's families and
Dubai's Kufi, Alexandria and Kufam are cut by `fonts.nix`, with `make-cut.py` beside it. Without
Ecrivain Espace, the letters of Écrivain do not sit on the ruling.

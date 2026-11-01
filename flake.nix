# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
{
  description = "Development shell of imprimeur and sommaire";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/31ecbaca1bdefa45dffc409f0250bd8039ea0010";
    # Emacs 29.1 and 30.1, the packages' minimum versions, which nixpkgs
    # no longer carries.
    emacs-ci.url = "github:purcell/nix-emacs-ci";
  };

  # The binary cache of nix-emacs-ci; without it, `nix develop` builds
  # Emacs 29.1 and 30.1 from source.  Taken with --accept-flake-config.
  nixConfig = {
    extra-substituters = "https://emacs-ci.cachix.org";
    extra-trusted-public-keys = "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4=";
  };

  outputs = { nixpkgs, emacs-ci, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      emacs = pkgs.emacs-pgtk.pkgs.withPackages (epkgs: [
        epkgs.package-lint
        epkgs.relint
      ]);
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          emacs
          pkgs.pandoc
          pkgs.chromium
          pkgs.nodejs_24
          pkgs.mermaid-cli
          pkgs.ffmpeg
          pkgs.git
        ];
        # The fonts of the test on mathematics, whatever the machine has.
        IMPRIMEUR_TEST_FONTS = "${pkgs.dejavu_fonts}/share/fonts/truetype";
        IMPRIMEUR_EMACS_29 = "${emacs-ci.packages.${system}.emacs-29-1}/bin/emacs";
        IMPRIMEUR_EMACS_30 = "${emacs-ci.packages.${system}.emacs-30-1}/bin/emacs";
      };
    };
}

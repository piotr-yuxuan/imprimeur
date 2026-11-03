# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
{
  description = "Development shell of imprimeur and sommaire";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/31ecbaca1bdefa45dffc409f0250bd8039ea0010";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      emacs = pkgs.emacs-pgtk.pkgs.withPackages (epkgs: [
        epkgs.package-lint
        epkgs.relint
        # For the test that loads the README's configuration.
        epkgs.straight
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
          pkgs.luajitPackages.luacheck
          # For the tests of scripts/release.py, and for the workflows.
          pkgs.python3
          pkgs.actionlint
          # For `make smoke-xwidget' with no display of its own, as in CI.
          pkgs.xvfb
          pkgs.xvfb-run
        ];
        # The only fonts of a scratch home, whatever the machine has.
        IMPRIMEUR_TEST_FONTS = "${pkgs.dejavu_fonts}/share/fonts/truetype";
        # The plugins of the second run of `make smoke-xwidget', those of the
        # WebKit that this Emacs links to.
        IMPRIMEUR_SMOKE_GST_PLUGINS = pkgs.lib.makeSearchPath "lib/gstreamer-1.0"
          (with pkgs.gst_all_1; [ gstreamer.out gst-plugins-base gst-plugins-good ]);
      };
    };
}

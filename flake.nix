# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
{
  description = "Development shell of imprimeur and sommaire";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/31ecbaca1bdefa45dffc409f0250bd8039ea0010";
  };

  outputs = { nixpkgs, ... }:
    let
      linux = nixpkgs.legacyPackages.x86_64-linux;
      darwin = nixpkgs.legacyPackages.aarch64-darwin;
      emacsFrom = base: base.pkgs.withPackages (epkgs: [
        epkgs.package-lint
        epkgs.relint
        # For the test that loads the README's configuration.
        epkgs.straight
      ]);
      common = pkgs: [
        pkgs.pandoc
        pkgs.nodejs_24
        pkgs.ffmpeg
        pkgs.git
        pkgs.luajitPackages.luacheck
        # For the tests of scripts/release.py, and for the workflows.
        pkgs.python3
        pkgs.actionlint
      ];
    in
    {
      devShells.x86_64-linux.default = linux.mkShell {
        packages = common linux ++ [
          (emacsFrom linux.emacs-pgtk)
          linux.chromium
          linux.mermaid-cli
          # For `make smoke-xwidget' with no display of its own, as in CI.
          linux.xvfb
          linux.xvfb-run
        ];
        # The only fonts of a scratch home, whatever the machine has.
        IMPRIMEUR_TEST_FONTS = "${linux.dejavu_fonts}/share/fonts/truetype";
        # The plugins of the second run of `make smoke-xwidget', those of the
        # WebKit that this Emacs links to.
        IMPRIMEUR_SMOKE_GST_PLUGINS = linux.lib.makeSearchPath "lib/gstreamer-1.0"
          (with linux.gst_all_1; [ gstreamer.out gst-plugins-base gst-plugins-good ]);
      };

      # No Chromium nor Xvfb in nixpkgs here: what needs no page, as CI's job for macOS runs.
      devShells.aarch64-darwin.default = darwin.mkShell {
        packages = common darwin ++ [ (emacsFrom darwin.emacs) ];
        IMPRIMEUR_TEST_FONTS = "${darwin.dejavu_fonts}/share/fonts/truetype";
      };
    };
}

# Write a skin

These steps make a skin named `demo` in a package of its own. [The skin API](../reference/skin-api.md)
gives every key, and `imprimeur-skin-xix/` is a whole example.

1. Make a directory that holds the package and its assets:

   ```sh
   mkdir -p imprimeur-skin-demo/assets
   ```

2. Write `imprimeur-skin-demo/assets/skin.css`, with your rules in the layer `skin`:

   ```css
   @layer skin {
     [data-skin="demo"] {
       --imp-background: light-dark(#fffff0, #101014);
       --imp-font-body: Georgia, serif;
       --imp-measure: 34rem;
     }
     [data-skin="demo"][data-demo-tone="warm"] {
       --imp-background: light-dark(#fff4e0, #1c1410);
     }
   }
   ```

3. Write `imprimeur-skin-demo/imprimeur-skin-demo.el`, whose manifest registers it:

   ```elisp
   ;;; imprimeur-skin-demo.el --- A skin of imprimeur  -*- lexical-binding: t; -*-

   (require 'imprimeur-skin)

   (imprimeur-skin-define 'demo
     :title "Demo"
     :directory (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
     :stylesheets '("skin.css")
     :options '((tone :label "Tone" :default "plain"
                      :choices (("plain" . "Plain") ("warm" . "Warm")))))

   ;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-demo: %S" (require 'imprimeur-skin-demo)))

   (provide 'imprimeur-skin-demo)
   ```

4. Try it, from a clone of this repository:

   ```sh
   emacs -L imprimeur -L imprimeur-skin-demo -l imprimeur -l imprimeur-skin-demo
   ```

   Open a document, type `M-x imprimeur-mode`, then press `M-g s` and pick `demo` in the menu, and `M-g o`
   to try its tone. If the manifest is refused, `*Warnings*` says why.

5. Add a pandoc filter if the sheet cannot do it alone: put `filter.lua` in `assets`, and write
   `:filters '(common "filter.lua")`. It runs after the core's filter and before the last, and
   may do no input or output.

6. Add a module if the page must act: put `page.mjs` in `assets`, with a default export taking
   `{ signal, option, key, hold, latest, goToLine }`, and write `:module "page.mjs"`. List in
   `:keys` any key that it takes, and undo what it added when `signal` aborts.

7. Name its fonts in the sheet's stacks, and list them in `fonts.nix` beside the package:

   ```nix
   { pkgs }: [ pkgs.libertinus ]
   ```

8. Install it like any skin: a recipe with `:files ("imprimeur-skin-demo/*.el" "imprimeur-skin-demo/assets")`.

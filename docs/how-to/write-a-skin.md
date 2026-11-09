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

## A skin for a right-to-left language

The core sets `dir="rtl"` on the page when the primary subtag of the document's language is one of
`ar fa ur ps ckb sd ug he yi dv ota`, and `dir="ltr"` otherwise: a skin sets no direction of its own,
and the language chooses no skin. Code, maths and diagrams stay left to right, as do the page's own
words, which are English; the minitoc's closed triangle and the arrow back from a note turn. A
display equation scrolls sideways by itself, and so does its paragraph, as the page cannot scroll
to what passes its right edge: both are scroll boxes, so a margin of the equation stays inside its
paragraph.

1. Write the sheet in logical properties, such as `margin-inline-start` and `inset-inline-end`
   rather than `margin-left` and `right`, so that it holds in both directions, and select with
   `:dir(rtl)` what must differ. A heading's minitoc button is left to right in any heading, for
   its English label, so its logical properties never turn: select it by its heading's direction,
   `:dir(rtl) > .imprimeur-minitoc-button`, as the base sheet does.

2. In Arabic script, change only the colour inside a word: a change of weight, size or style there
   breaks the joins in WebKit (W3C ALReq-gap §4.4).

3. Never put a `dir` attribute or a `<bdi>` inside a word.

4. Set `letter-spacing: normal` on Arabic text.

5. Promise no kashida justification. WebKitGTK 2.54 justifies only at spaces: its `text-justify`
   is behind a flag that is off by default and has no `kashida` value, and
   [WebKit bug 6203](https://bugs.webkit.org/show_bug.cgi?id=6203) has been open since 2005.
   Chromium 156 opens no cursive run to justification either. A face such as Amiri still draws
   the tatweels that an author types, as a curved kashida.

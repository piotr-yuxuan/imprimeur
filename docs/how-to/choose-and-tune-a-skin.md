# Choose and tune a skin

You have imprimeur and at least one skin installed, as
[the README's configuration](../../README.md#configuration) shows.

1. Open the page: type `M-x imprimeur-mode` in an Org or Markdown buffer.
2. Choose a skin: press `M-g s`, in the source or in the page's Emacs window, and press a skin's
   key in the menu, which stays open so that you can try another, or
   `base` for the plain page. The page changes in place and keeps your place. The choice lasts
   as long as the mode.
3. Tune it: press `M-g o`, and pick an option and a value. The page changes at once, and the
   echo area gives the entry that keeps your choice.
4. Keep the choice: put what the echo area said in your configuration, and name the skin that
   every page starts in.

   ```elisp
   ;; Every page starts in XIX.
   (setq imprimeur-skin 'xix
         ;; By skin, then by option: a column of 28 rem, not 30.  `M-g o' says what
         ;; to write here, and an entry that the skin does not register warns once.
         imprimeur-skin-options '((xix (measure . "28"))))
   ```

5. Turn skins off: set `imprimeur-skin` to `base`, and every page starts plain.

Each skin's README lists its options and what each does. To see the faces a skin asks for,
[install its fonts](install-the-fonts.md). A document cannot choose a skin for itself:
[why](../explanation/why-these-skins-and-faces.md#why-no-document-chooses).

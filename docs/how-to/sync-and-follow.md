# Sync and follow

The source and the page follow each other's scrolling from the moment the page opens. These
steps change that, and move between the two. The double-clicks here were checked by a
synthetic event: a person's hand has not tried them in an Emacs window.

1. Send the page to point: press `M-g v` in the source. Point's block comes to the top of the
   page and is marked for a moment; the source does not move.
2. Send the source to the page: double-click a paragraph on the page. Point goes to that line, and
   a fold around it opens. Or press `M-g v` in the page's Emacs window, which selects the source
   at the line of the page's top block.
3. Stop following for this buffer: type `M-x imprimeur-follow-mode`. Neither moves for the other,
   and the page still shows your text. The same command turns it on again, and the page goes at
   once to where the source is.
4. Have only the page follow, or nothing by default: set `imprimeur-scroll-sync` to `to-preview`,
   or to `nil`.
5. Bring back a page you hid: press `M-g v`, or type `M-x imprimeur-show`.
6. Put the page elsewhere: set `imprimeur-display-buffer-action`, which
   [the options](../reference/options.md#imprimeur) describe. To have the page take the source's
   Emacs window:

   ```elisp
   (setopt imprimeur-display-buffer-action '((display-buffer-same-window)))
   ```

7. Show the page in a browser as well: type `M-x imprimeur-browse`. Following holds there too. To
   open it there always, set `imprimeur-target` to `browser`.

[The reference](../reference/commands-and-keys.md#what-folds-and-following-do) says what folds do
meanwhile.

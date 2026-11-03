# Your first preview

In this lesson you go from a clone of this repository to a typeset page beside its source, and
change how it looks. It takes about five minutes on a machine with Nix and a graphic display.
Nothing is installed: your own Emacs configuration stays out of it.

## 1. Get the clone and the tools

```sh
git clone https://github.com/piotr-yuxuan/imprimeur
cd imprimeur
nix develop
```

**Check:** `emacs --version` starts with `GNU Emacs 31.1`, and `pandoc --version` with
`pandoc 3`.

## 2. Start a separate Emacs

```sh
emacs -Q -L imprimeur -L imprimeur-skin-minitel -L imprimeur-skin-xix \
  --eval "(require 'imprimeur)" \
  --eval "(require 'imprimeur-skin-minitel)" --eval "(require 'imprimeur-skin-xix)" \
  examples/minitel/robida.org
```

**Check:** an Emacs frame opens on a French text about the telephonoscope, in Org mode: the mode
line says `Org`.

## 3. Turn on the page

Type `M-x imprimeur-mode`.

**Check:** a second Emacs window opens on the right, and the mode line of the first says
`Imprimeur`. Within a few seconds the same text shows there, set in one monospace family in a thin
frame, with a bar of keys at its foot. That is the skin Minitel. If you are on a text terminal, the
page opens in a desktop window of Chromium instead, and the rest holds there too.

## 4. Type

Go to the end of the first paragraph on the left and type a few words, without saving.

**Check:** a moment after you stop, your words are on the page. Only that block changed, and the
page kept your place.

## 5. Move between the two

Move point to a heading in the middle of the source, and press `M-g v`.

**Check:** that heading comes to the top of the page and is outlined for a moment. Now scroll the
source with `C-v`.

**Check:** the page follows.

## 6. Change the skin

Press `M-g s` and choose `xix`.

**Check:** the page becomes a French book with a red title, in the same place in the text. Its
fonts may be a fallback, as this lesson installs none.

## 7. Tune it

Press `M-g o`, choose `measure`, then `24`.

**Check:** the column narrows, and the echo area gives the entry that keeps the choice:
`(xix (measure . "24"))`.

## 8. End it

Type `M-x imprimeur-mode` again.

**Check:** the page and its Emacs window go, and the source is as you left it, with your unsaved
words.

## Where next

You have seen a page follow its source, in two skins. To keep this in your own Emacs, use
[the README's configuration](../../README.md#configuration). [The gallery](../../README.md#gallery)
shows the other skins, and [the examples](../../examples/README.md) a document for each.

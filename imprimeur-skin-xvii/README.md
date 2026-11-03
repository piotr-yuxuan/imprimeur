# imprimeur-skin-xvii

The skin XVII of [imprimeur](../README.md#skins): a French book of the
XVII<sup>th</sup> century. IM Fell English with long s and historical ligatures, a
red and black title page, woodcut bands, three-line block initials, manchettes, and
paper or candlelight as the Emacs theme's appearance says. `../examples/xvii/` holds a
French sample and an English one, with their sources.

## Fonts

The skin names fonts and ships none. `fonts.nix` lists them, and the page falls
back through its stacks on what is missing.

| Family                     | Role                                                       | Source                                                    | Licence |
|----------------------------|------------------------------------------------------------|-----------------------------------------------------------|---------|
| IM FELL English            | Text by default                                            | [`google/fonts`](https://github.com/google/fonts/tree/5174b3333331c966c38f4355d50b03ca1c1df2f9/ofl/imfellenglish), two files | OFL-1.1 |
| IM FELL English SC         | Its small capitals, a family of their own                  | [`google/fonts`](https://github.com/google/fonts/tree/5174b3333331c966c38f4355d50b03ca1c1df2f9/ofl/imfellenglishsc), one file | OFL-1.1 |
| IM FELL French Canon       | Titles, and the letter of a stand-in initial               | [`google/fonts`](https://github.com/google/fonts/tree/5174b3333331c966c38f4355d50b03ca1c1df2f9/ofl/imfellfrenchcanon), two files | OFL-1.1 |
| EB Garamond 12             | The other face; under IM Fell, a table's figures, an address, the flowers. Write this name: the bare EB Garamond is the 8-point cut | nixpkgs `eb-garamond` | OFL-1.1 |
| EB Garamond Initials       | Block initials: A D F G L N O Q T X                        | nixpkgs `eb-garamond`                                     | OFL-1.1 |
| EB Garamond Initials Fill1 | The foliage behind a stand-in initial                      | nixpkgs `eb-garamond`                                     | OFL-1.1 |
| Garamond Libre             | The plain face                                             | nixpkgs `garamond-libre`                                  | X11     |
| Courier Prime              | Code                                                       | nixpkgs `courier-prime`                                   | OFL-1.1 |
| Garamond-Math              | Maths                                                      | nixpkgs `texlivePackages.garamond-math`                   | OFL-1.1 |
| Libertinus Serif           | The narrow no-break space, and the end of the stack        | nixpkgs `libertinus`                                      | OFL-1.1 |

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in
`imprimeur-skin-options`.

| Option       | Values                                    | Default   |
|--------------|-------------------------------------------|-----------|
| `face`       | `im-fell`, `eb-garamond`, `garamond-libre` | `im-fell` |
| `long-s`     | `on`, `off`                               | `on`      |
| `ligatures`  | `on`, `off`                               | `on`      |
| `manchettes` | `on`, `off`                               | `on`      |

- **`face`:** the text. IM Fell English is a real type of the century, from Fell's
  matrices, darker and rougher than the revivals; EB Garamond 12 is a Garamond revival;
  Garamond Libre a plain Garamond for long reading. Titles stay in IM Fell French Canon
  and initials in EB Garamond Initials, whichever is chosen.
- **`long-s`:** a font feature, so that copying and searching still see an s. IM Fell
  sets it before any letter, with its ties to h, i, l, t and another long s; EB Garamond 12
  where its own context places it. A hyphen and the end of a word keep the s round. Garamond
  Libre has none to give, so this changes nothing under it.
- **`ligatures`:** under IM Fell, the ct tie and the tied long s with a round one; the ties
  of the long s with t, i, l, h and itself stay, as the font keeps them in one feature with
  fi, ff and fl, so a few words on a screen change. Under EB Garamond 12, the ct and st ties.
  Garamond Libre's take ch along, which is no tie of the period, so they stay off.
- **`manchettes`:** on, notes stand in the margin beside the line that calls them, and the
  call is a letter that leads nowhere. Off, they go to the end of the section with a live
  link, and the column returns to the middle of the Emacs window. A document with no note
  stays in the middle either way. Below 736 CSS px there is no margin, so they go to the end
  of the section whichever is set; a note called from a heading, a table, a figure or a verse
  stays there too.

```elisp
;; Every page starts in XVII.
(setq imprimeur-skin 'xvii
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((xvii (face . "im-fell")
                                     (long-s . "on")
                                     (ligatures . "on")
                                     (manchettes . "on"))))
```

## Limits

Capitals come from the small capitals that the engine synthesises from a face with none, so
that the selection, copying and search keep the document's case; another engine than Blink
and WebKit may scale them otherwise. The letters of an initial's first word and of a
century stay in the line at no size: they copy and are found, but show no highlight. Words
break by the shared filter `hyphenate`, in French and English, never after an s, between c
and t, or between f and f, i or l, which is what keeps IM Fell's long s and ties in WebKit;
a document with no language counts as English, takes no running marks and numbers no plate
without a caption, and any other language stays whole and ragged. English on a narrow column
stays plainly looser than French. Tried in WebKit at scale 1 on a virtual display and in
headless Chromium, not on a real Wayland session or on a Mac.

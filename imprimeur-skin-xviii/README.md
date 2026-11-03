# imprimeur-skin-xviii

The skin XVIII of [imprimeur](../README.md#skins): a French book of the
XVIII<sup>th</sup> century, after Fournier and Barbou. Baskervville with no long s,
a red title in spaced capitals, fleuron bands, framed two-line lettrines, notes
called (a), running guillemets, and paper or candlelight as the Emacs theme's
appearance says. `../examples/xviii/` holds a French sample and an English one, with
their sources.

## Fonts

The skin names fonts and ships none. `fonts.nix` lists them, and the page falls
back through its stacks on what is missing.

| Family          | Role                                              | Source                                                    | Licence |
|-----------------|---------------------------------------------------|-----------------------------------------------------------|---------|
| Baskervville    | Text, titles and lettrines by default             | [`google/fonts`](https://github.com/google/fonts/tree/5174b3333331c966c38f4355d50b03ca1c1df2f9/ofl/baskervville), two files, version 1.100 | OFL-1.1 |
| Junicode        | The other face, with long s; the signs Baskervville lacks | nixpkgs `junicode`                                | OFL-1.1 |
| Courier Prime   | Code                                              | nixpkgs `courier-prime`                                   | OFL-1.1 |
| Libertinus Math | Maths                                             | nixpkgs `libertinus`                                      | OFL-1.1 |
| Libertinus Serif | End of the stack                                 | nixpkgs `libertinus`                                      | OFL-1.1 |

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in
`imprimeur-skin-options`.

| Option   | Values                                                | Default        |
|----------|-------------------------------------------------------|----------------|
| `face`   | `baskervville`, `junicode`                            | `baskervville` |
| `long-s` | `off`, `on`                                           | `off`          |
| `bands`  | `fleurons`, `rinceau`, `entrelacs`, `perles`, `filet` | `fleurons`     |

- **`face`:** one family for text, titles and lettrines. Baskervville is the ANRT's
  revival of a Baskerville cut in Strasbourg; Junicode is an old-style cut after
  Oxford's of about 1700.
- **`long-s`:** a font feature of Junicode, so it applies to Junicode only, and
  Baskervville, which has no long s, is unchanged by it. Copying and searching still
  see an s.
- **`bands`:** above the title and each chapter, a whole number of tiles at any width.
  Fleurons are a palmette on two scrolls between lozenges, in Fournier's manner;
  rinceau a running vine; entrelacs a guilloche; perles lozenges and pearls; filet no
  ornament, a thick and a thin rule. They were drawn for this skin, and copy no printer's
  ornament.

```elisp
;; Every page starts in XVIII, rather than in Minitel.
(setq imprimeur-skin 'xviii
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((xviii (face . "baskervville")
                                      (long-s . "off")
                                      (bands . "fleurons"))))
```

## Limits

Baskervville has no long s, no small capitals in italic, and no old-style figures of
even width, so tables have lining figures; its hairlines are thinner than Junicode's. Its
narrow space comes from Junicode in WebKit, where it is wider. Words break by the shared
filter `hyphenate`, in French and English: a document with no language counts as English,
takes no running marks and numbers no plate without a caption, and any other language
stays whole and ragged. Tried in WebKit at scale 1 on a virtual display and in headless
Chromium, not on a real Wayland session or on a Mac, where a Baskerville of Apple's stands
second in the stack and the frame of a lettrine is tuned for Baskervville.

# imprimeur-skin-ecrivain

The skin Écrivain of [imprimeur](../README.md#gallery): handwriting on paper. Cahier by
default, the French school hand Playwrite FR Moderne on Seyès paper, with each baseline on a
thick line and the x-height on the first thin line above it. Playwrite FR Trad is one choice
away, and Carnet, Notes and Ardoise the other papers. One long sheet by default, or leaves of
a notebook. `../examples/ecrivain/` holds a notebook in French and in English, written to try
the skin, with their sources.

## Fonts

The skin names fonts and ships none. An installed variable font exposes no axes on Linux, so
`fonts.nix` builds static cuts under names of their own, and the sheet asks for those. It
takes minutes once, for about 9 MB:

```nix
fonts.packages = import "${imprimeur}/imprimeur-skin-ecrivain/fonts.nix" {inherit pkgs;};
```

**Without Ecrivain Espace the letters do not sit on the ruling.** It is two spaces whose
ascent equals their descent, and the first available font of every stack, so a line's baseline
is at half its height whatever hand draws the letters. The page stays readable without it,
through the rest of each stack, but its baselines then fall where each fallback puts them.

| Family                  | Role                                                                | Made from                                                              | Licence |
|-------------------------|---------------------------------------------------------------------|------------------------------------------------------------------------|---------|
| Ecrivain Espace         | The strut of every line; U+2002 and U+202F                          | Libertinus Serif, `make-cut.py` then `make-strut.py`                   | OFL-1.1 |
| Ecrivain Cahier         | Cahier, the default: 360 for text, 400 for strong and headings      | Playwrite FR Moderne, from google/fonts, `wght`                        | OFL-1.1 |
| Ecrivain Trad           | Cahier, the older school hand                                       | Playwrite FR Trad, from google/fonts, `wght`                           | OFL-1.1 |
| Ecrivain Carnet         | Carnet: 400, 580, 680, each with its italic                         | Shantell Sans, nixpkgs `shantell-sans`, `INFM` 50, `BNCE` 35           | OFL-1.1 |
| Ecrivain Ardoise        | Ardoise: 400, 580, 720, each with its italic                        | Shantell Sans, `INFM` 60, `BNCE` 45                                    | OFL-1.1 |
| Ecrivain Note           | Notes; quotations, captions, notes and leaf numbers everywhere      | Caveat, from google/fonts, `wght`                                      | OFL-1.1 |
| Ecrivain Code           | All code: 300 inline in Cahier, 400, and a slanted 400 for comments | Monaspace Radon Var, nixpkgs `monaspace.variable`, under another name as Monaspace reserves its own | OFL-1.1 |
| Fira Math               | MathML: no hand holds a MATH table                                  | nixpkgs `fira-math`                                                    | OFL-1.1 |

Each stack then goes on to the source families, should they be installed, and to other
handwriting. A diagram writes in the page's hand, as the core draws it in the family of the
text.

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in
`imprimeur-skin-options`.

| Option    | Values                                                | Default    |
|-----------|-------------------------------------------------------|------------|
| `variant` | `cahier`, `carnet`, `notes`, `ardoise`                | `cahier`   |
| `hand`    | `moderne`, `trad`                                     | `moderne`  |
| `ink`     | `variante`, `bleu-noir`, `bleu`, `noir`, `violet`, `sepia` | `variante` |
| `sheet`   | `pageless`, `pages`                                   | `pageless` |

- **`variant`:** the whole hand and its paper; code stays in Radon throughout. Cahier is
  Playwrite on Seyès paper, each baseline on a thick line: only the ink varies, pooled, and the
  hand is the same from letter to letter. Carnet is Shantell Sans, where repeated letters differ
  and the page stays orderly, on a dot grid with a red margin. Notes is Caveat on small squares,
  whose alternates change the shapes of repeated letters most. Ardoise is Shantell in chalk: a
  green board by day, charcoal by night, and ink on white on paper.
- **`hand`:** Cahier only. Moderne is the hand named. A school's Seyès asks ascenders of 3
  interlines and descenders of 2, and this font's own are 2.15 and 1.18. Trad, the older school
  hand with looped ascenders and rounder capitals, has the same x-height, with 2.75 and 1.78,
  closer to the school's; its capital I reads as J, so "Il" reads "Jl".
- **`ink`:** the colour of the text. Headings and rules follow; the red, green and blue pens
  stay, and so does the black pen of highlighted words. On dark paper and on the slate, each is
  the gel or chalk nearest that ink. Carnet's own is blue-black, so by day that choice changes
  nothing there.
- **`sheet`:** pageless is one continuous sheet, as a preview follows the source by scrolling.
  Pages are leaves of a school notebook, each with its ruling, its red margin, a whole number of
  lines and a number, and a paragraph runs on across a leaf's end. An Emacs window or a browser
  viewport narrower than 720 CSS pixels has no room for a leaf, and stays pageless. The toggle
  changes one attribute, with nothing to load, and you keep your place.

```elisp
;; Every page starts in Écrivain, rather than in Minitel.
(setq imprimeur-skin 'ecrivain
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((ecrivain (variant . "cahier")
                                         (hand . "moderne")
                                         (ink . "variante")
                                         (sheet . "pageless"))))
```

## Writing for it

- `#+AUTHOR:` and `#+DATE:`, or `author:` and `date:`, stand under the title, as written.
- Under `lang: fr` or `#+LANGUAGE: fr`, headings take the outline I. A. 1. a) and paragraphs an
  alinéa; any other language keeps its headings as written, with a line between paragraphs.
- Blocks stay whole on the grid, and in pages a whole block goes to the next leaf, which can
  leave blank lines at a leaf's foot. A listing over 36 lines or a table over 18 rows flows
  around the leaf's end, and gives up its frame; so does a quotation or an alert over 1000
  letters.

## The check of the ruling

`tests/imprimeur-skin-ecrivain/align`, run by hand in `nix develop`, builds `fonts.nix`, opens
the French sample in Chromium and in an xwidget on an Xvfb of its own, and measures by pixels,
at scale 1. The text's baselines lie on their thick lines and its x-heights on the first thin
lines above them, within half a device pixel. It holds headings and notes to one: a large size
keeps the overshoot of the font's outlines, which the hinter flattens at the text's size, and
Caveat's letters do not keep one baseline. Moderne's headings read up to 0.54 of a pixel below
the line, Trad's title 0.95, and notes up to 0.53.

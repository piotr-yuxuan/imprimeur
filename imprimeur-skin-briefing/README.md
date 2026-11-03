# imprimeur-skin-briefing

The skin Briefing of [imprimeur](../README.md#gallery): a modern business memo, read rather
than presented. Inter, one accent, colour otherwise only for status, and the answer first:
a bottom line, callouts, chips over action titles, and columns of figures on the right.
`../examples/briefing/` holds two briefs from real texts, a reserve policy from Bagehot's
*Lombard Street* of 1873 and Jefferson's instructions to Lewis of 1803, with their sources.

## Fonts

The skin names fonts and ships none. `fonts.nix` lists them, and the page falls back through
its stacks on what is missing: to Adwaita Sans or the system's sans, and a generic mono.

| Family                | Role                                                            | Source                                         | Licence |
|-----------------------|-----------------------------------------------------------------|------------------------------------------------|---------|
| Inter, Inter Display  | Text, tables, labels, chips; the title and first-level headings | nixpkgs `inter`, the rsms/inter release        | OFL-1.1 |
| Fira Math             | MathML, the one sans face with a MATH table                     | nixpkgs `fira-math`, firamath/firamath         | OFL-1.1 |
| Adwaita Mono          | Code, when Emacs's default face names no family; it brings Adwaita Sans | nixpkgs `adwaita-fonts`, GNOME's adwaita-fonts | OFL-1.1 |

Code asks first for the family of Emacs's default face.

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in
`imprimeur-skin-options`.

| Option    | Values                                 | Default   |
|-----------|----------------------------------------|-----------|
| `accent`  | `blue`, `teal`, `aubergine`, `graphite` | `blue`   |
| `density` | `compact`, `regular`, `airy`           | `compact` |
| `skim`    | `off`, `on`                            | `off`     |

- **`accent`:** the bottom line's rule, links, Decision callouts, ticks and code keywords.
  Status colours stay as they are, at least 25 (CIE76) from every accent, so there is no warm
  accent: it would lie beside Risk or Ask. Graphite is the ink itself: Decision keeps its
  label and rule and loses its colour, and code keywords and links read as text, so links take
  a full underline.
- **`density`:** compact is line height 1.42, code 1.4, and 0.7 of the space around blocks, in
  table rows and at the head of the page; regular 1.55, 1.5 and the full space; airy 1.72, 1.6
  and 1.35 times the space.
- **`skim`:** only the masthead, the bottom line, the titles to level three and the callouts.
  The memo's link beside its date flips the page at once, and the next option chosen in Emacs
  sets it again as the session holds it.

```elisp
;; Every page starts in Briefing.
(setq imprimeur-skin 'briefing
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((briefing (accent . "blue")
                                         (density . "compact")
                                         (skim . "off"))))
```

## Writing for it

| To show                 | In Org                                         | In Markdown                                         |
|-------------------------|------------------------------------------------|-----------------------------------------------------|
| Masthead                | `#+TITLE:`, `#+SUBTITLE:`, `#+AUTHOR:`, `#+DATE:`, `#+STATUS:` | `title:`, `subtitle:`, `author:`, `date:`, `status:` in the front matter |
| Bottom line             | A section named Summary, Executive summary, TL;DR, Bottom line, Résumé, Synthèse or L'essentiel | The same; or `<div class="summary">`, which takes its label from the skin |
| Callout                 | `#+begin_decision`, `ask`, `risk`, `note`      | `> [!IMPORTANT]` is Decision, `[!WARNING]` Ask, `[!CAUTION]` Risk, `[!NOTE]` and `[!TIP]` Note |
| Its label               | A leading `*Ask:*` names it                    | A leading `**Ask:**` names it                       |
| An action title's chips | `* TODO [#A] Title :tag:`, a planning line under `#+OPTIONS: p:t`, and an `:OWNER:` property | `## TODO: [#A] Title :tag:`, and a line `DEADLINE: 2026-11-02, OWNER: Name` under it. The colon is what tells `## NEXT STEPS` from a keyword |
| Figures on the right    | A column at least half of whose filled cells are quantities: `412,880`, `£84,000`, `3.5k`, `12%`, a true minus; not `1.2.3` or `2026-11-02` | The same |
| Captions                | `#+CAPTION:`                                   | `Table:` before a table, `Figure:` after a diagram  |

A document whose language starts with `fr` takes French labels, dates and spacing.

## Print

A4, in the light palette from either palette, with what `details` holds open, by the module.
From a dark page, flowcharts and sequence diagrams print light by the sheet; another kind of
diagram may keep its dark fills.

## Limits

A heading keeps the document's marks at no size, so that selecting it copies `TODO [#A] Title`
and search finds those words; a search for a word that a chip draws finds nothing, and a screen
reader may read both. The skim view hides a block at no height and not by `display: none`, as
the page's map of lines needs its box: search finds words in a hidden block with nothing to
show, Tab can reach a hidden link, and a screen reader still reads hidden blocks. A true minus
copied to a spreadsheet is text. Raw HTML keeps its own spacing in French. Whole-word wrapping
covers plain blocks only, and the hanging indent is a fixed 4 columns. A picture cannot follow
the palette, so it dims in dark, at `brightness(0.85)`. A film has no codecs in the WebKit of
an Emacs window here, which offers a link to open it instead. Tried in WebKit at scale 1 on a
virtual display and in headless Chromium, not on a real Wayland session or on a Mac.

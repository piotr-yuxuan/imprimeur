# imprimeur-skin-dubai

The skin Dubai of [imprimeur](../README.md#gallery): an Arabic business memo, Briefing's sibling,
set right to left. It gives the answer first: a bottom line, callouts, chips over action titles,
key figures, and columns of figures. `../examples/dubai/` holds two briefs from real texts, the
Dubai budget laws No. 23 of 2024 and No. 15 of 2025, with their sources.

**No affiliation.** The skin has no relation to the Government of Dubai, uses no emblem and no
flag colours, and does not use Dubai Font: that font's licence forbids passing it on, combining it
with other programs and using it in open source (clauses 3.1 d, i and j). Its name says only that
it follows the pairing of faces of the UAE Design System.

## Fonts

The skin names fonts and ships none. `fonts.nix` lists them, and the page falls back through its
stacks on what is missing. Noto Kufi Arabic, Alexandria and Kufam are variable fonts: `fonts.nix`
fetches each whole, with its licence, from google/fonts at `5174b333`, and cuts it into static
weights under a family of its own, as an installed variable font exposes no axes on Linux.

| Family | Role | Source | Designers | Licence |
|---|---|---|---|---|
| Dubai Kufi, cut from Noto Kufi Arabic 2.109 | Arabic text, 400 and 700 | google/fonts `5174b333` | Monotype Design Team, David Williams, Khaled Hosny | OFL-1.1 |
| Dubai Alexandria, cut from Alexandria 5.100 | Arabic headings, 600 and 700 | google/fonts `5174b333` | Mohamed Gaber, with Julieta Ulanovsky | OFL-1.1 |
| Dubai Kufam, cut from Kufam 1.301 | The masthead, the labels, the chips and the key figures, under every face, 500 and 700 | google/fonts `5174b333`, its italic file left out | Wael Morcos (Arabic), Artur Schmal (Latin), Original Type | OFL-1.1 |
| Inter | Latin text, roman and true italic | nixpkgs `inter` | Rasmus Andersson | OFL-1.1 |
| IBM Plex Sans Arabic, IBM Plex Sans | The face `plex`: eight static, hinted weights | nixpkgs `ibm-plex` 1.1.0 | Mike Abbink, Paul van der Laan, Pieter van Rosmalen, Wael Morcos, Khajak Apelian, Bold Monday | OFL-1.1 |
| Noto Sans Arabic | The Arabic-Indic digits under `plex`, and a fallback | nixpkgs `noto-fonts`, not overridden, so that the binary cache has it | Monotype Design Team, Nadine Chahine, Nizar Qandah, Khaled Hosny | OFL-1.1 |
| Cascadia Mono | Code, Arabic included, when Emacs's default face names no family | nixpkgs `cascadia-code` | Aaron Bell, Mohamad Dakak (Arabic), Microsoft | OFL-1.1 |
| Fira Math | MathML | nixpkgs `fira-math` | Xiangdong Zeng | OFL-1.1 |

- **Text: one family, `dubai-text`.** Noto Kufi Arabic holds Latin letters but no italic, so a plain
  stack would slant its Latin by synthesis. The sheet builds `dubai-text` from `local()` and
  `unicode-range` rules: the Arabic blocks from Dubai Kufi, everything else from Inter. Arabic has
  no italic, so an emphasis in Arabic stays upright.
- **Headings: Alexandria, for Arabic alone.** Its Arabic digits are proportional, and no feature
  makes them tabular, so it sets nothing but headings; their Latin is Inter.
- **Kufam: the masthead and the labels.** It was drawn for the Khatt Foundation's *Typographic
  Matchmaking in the City*, whose brief asked that the fonts "function within the Western
  (Amsterdam) and Eastern (Dubai) modern urban context", by its README; its Arabic follows the
  Kufic inscriptions of the VII<sup>th</sup> century. It is meant for signage and wayfinding, so
  it sets headings and labels, and stays out of running text. Latin labels take its true small
  capitals.
- **Figures.** Noto Kufi's Arabic-Indic and Persian digits are tabular, as are its Western ones;
  Inter has `tnum`, which tables turn on. Kufam's Western digits are tabular lining ones by
  default; its Arabic-Indic digits are proportional, and its `tnum` and `lnum`, which the key
  figures ask for, leave them so.
- **Caveat for the reader to judge.** Google describes Noto Kufi Arabic as "mainly for texts in
  larger font sizes". The UAE Design System still sets content in it on a 16 px base; the skin
  sets it at 17 px.

Code asks first for the family of Emacs's default face.

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in `imprimeur-skin-options`.

| Option    | Values                                  | Default   |
|-----------|-----------------------------------------|-----------|
| `accent`  | `teal`, `blue`, `aubergine`, `graphite` | `teal`    |
| `density` | `compact`, `regular`, `airy`            | `compact` |
| `skim`    | `off`, `on`                             | `off`     |
| `face`    | `kufi`, `plex`                          | `kufi`    |
| `hijri`   | `off`, `on`                             | `off`     |

- **`accent`:** the bottom line's rule, links, Decision callouts, ticks and code keywords: Briefing's
  validated set. Status colours stay as they are, at least 25 (CIE76) from every accent; each
  accent clears 4.5:1 on the ground and on its own tint. Graphite is the ink itself.
- **`density`:** compact is line height 1.6, regular 1.75 and airy 1.9, higher than Briefing's,
  as the UAE Design System asks for at least 1.5; code and the space around blocks follow.
- **`skim`:** only the masthead, the bottom line, the titles to level three and the callouts. The
  memo's link beside its date flips the page at once.
- **`face`:** `kufi` is Noto Kufi Arabic, Alexandria and Inter. `plex` is IBM Plex Sans Arabic with
  Plex Sans for Latin, in text and headings, with the Arabic-Indic digits of Noto Sans Arabic, as
  Plex's are proportional. Plex's Arabic stands low beside its Latin, a heh of 6.6 px against an
  x-height of 8.3 px at 16 px, so `plex` gives it `size-adjust: 125%`. Kufam keeps the masthead
  and labels under both.
- **`hijri`:** the Umm al-Qura date beside the masthead's Gregorian one, which the page computes
  with the calendar `islamic-umalqura`, always named in full, as WebKit takes a plain `islamic`
  for `islamic-tbla`.

```elisp
;; Every page starts in Dubai.
(setq imprimeur-skin 'dubai
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((dubai (accent . "teal")
                                      (density . "compact")
                                      (skim . "off")
                                      (face . "kufi")
                                      (hijri . "off"))))
```

## Writing for it

| To show | In Org | In Markdown |
|---|---|---|
| Masthead | `#+TITLE:`, `#+SUBTITLE:`, `#+AUTHOR:`, `#+DATE:`, `#+STATUS:` | `title:`, `subtitle:`, `author:`, `date:`, `status:` in the front matter |
| Arabic labels | `#+LANGUAGE: ar` | `lang: ar` |
| Bottom line | A section named الخلاصة or الملخص التنفيذي, or Summary, Executive summary, TL;DR or Bottom line | The same; or `<div class="summary">`, which takes its label from the skin |
| Callout | `#+begin_decision`, `ask`, `risk`, `note`: قرار, طلب, مخاطرة, ملاحظة | `> [!IMPORTANT]` is Decision, `[!WARNING]` Ask, `[!CAUTION]` Risk, `[!NOTE]` and `[!TIP]` Note |
| Its label | A leading `*قرار:*` names it | A leading `**قرار:**` names it |
| Key figure | A strong phrase of the bottom line that begins with a quantity, `*272 مليار درهم*` or `*AED 5 bn*`, and not `*سنة 2025:*`; a space or ASCII punctuation follows the closing `*`, since Org leaves the asterisks before an Arabic comma | `**272 مليار درهم**` |
| An action title's chips | `* TODO [#A] العنوان :وسم:`, with the keywords in ASCII, a planning line under `#+OPTIONS: p:t`, and an `:OWNER:` property | `## TODO: [#A] العنوان :وسم:`, and a line `DEADLINE: 2026-11-02, OWNER: Name` under it |
| Figures on the right | A column at least half of whose filled cells are quantities: `412,880`, `١٬٢٥٠٫٥`, `AED 1,250.00`, `1,250 د.إ`, `١٢٪`, `3.5k`, a true minus; not `1.2.3`, `2024-10-22` or `٢٢/١٠/٢٠٢٤` | The same |
| A total | A row named الإجمالي, المجموع, or Total | The same |
| Captions | `#+CAPTION:` | `جدول:` or `Table:` before a table, `شكل:` or `Figure:` after a diagram |

The author's digits are rendered as typed: the skin rewrites no digit, as that would change what a
reader copies, and offers no option of digits. The masthead's date, written `2024-10-22` or
`٢٠٢٤-١٠-٢٢`, takes CLDR's `ar-AE` month names, in the digits it was typed in, and so does its
Umm al-Qura date. The skin never writes U+FDFC, the rial sign. A document in any language but
Arabic takes English labels.

## Print

A4, in the light palette from either palette, with what `details` holds open, by the module. The
page number stands at the bottom left.

## Limits

What Briefing's README says of a heading's marks, the skim view, a true minus, whole-word wrapping,
pictures and films holds here. Text is ragged at its end, `text-align: start`: WebKitGTK justifies
only at spaces, so a justified Arabic line would open rivers, and no engine here draws kashida
justification. Within Arabic text the spaces and the Latin punctuation are Inter's, as the sheet
takes only the Arabic blocks from Noto Kufi. `make smoke-xwidget` checks that WebKitGTK keeps
`size-adjust`; with this skin's fonts installed, on a virtual display, Plex's Arabic stood 1.25
times as wide in `dubai-plex` as in its own family, and every face of the sheet loaded, in WebKit
as in Chromium. Tried in headless Chromium and in WebKit on a virtual display, not on a real
Wayland session or on a Mac, and not by eye.

## What only a reader of Arabic can judge

These stay open: no reader of Arabic has checked the skin.

- Every label: the statuses, callouts, chips, captions, the reading time and the Skim link.
- Whether Noto Kufi Arabic holds up at body size, and whether `plex` reads as more business-like.
- Whether Kufam's masthead sits well over Alexandria's headings.
- Whether the samples are transcribed faithfully.

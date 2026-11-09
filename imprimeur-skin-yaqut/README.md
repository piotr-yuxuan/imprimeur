# imprimeur-skin-yaqut

The skin Yaqut of [imprimeur](../README.md#gallery): an Arabic manuscript page. It is named after
Yaqut al-Musta'simi, who died in 1298 and was the cynosure of calligraphers; the Persian and Ottoman
schools followed his six pens, and his name means ruby, the colour of a rubric. The text stands in a
jadwal, ruled frames of gold, under an illuminated headpiece, the 'unwan, which holds the title. Headings
and emphasis are rubrics in vermilion and gold, notes stand in the margin as glosses, the hashiya, and a
colophon closes the text, its words in a triangle with the apex down, dated in the Hijri calendar, with a
seal. `../examples/yaqut/` holds al-Hariri's *al-Maqama al-San'aniyya* and two stories of Sa'di's
*Golestan*, with their sources. No reader of Arabic or Persian has checked them.

The skin has no affiliation with any institution that holds the manuscripts it evokes, and uses
neither the sign U+06DD END OF AYAH nor U+06DE START OF RUB EL HIZB, which are Qur'anic, nor any figural
ornament.

## Fonts

The skin names fonts and ships none. `fonts.nix` lists them, about 230 MB, most of it Cascadia's and
Noto's, and the page falls back through its stacks on what is missing.

| Family | Role | Source | Licence |
|---|---|---|---|
| Amiri | Text, Latin with true italics, tables; glosses and the colophon in its slanted face | nixpkgs `amiri` 1.003 | OFL-1.1 |
| Amiri Quran Colored | What the author encloses in ﴿ ﴾ | nixpkgs `amiri` | OFL-1.1 |
| Katibeh | Thuluth titles and headings | google/fonts at `5174b333` | OFL-1.1 |
| Qahiri | Kufic titles under `title` `kufi` | google/fonts at `5174b333` | OFL-1.1 |
| Raqq | Kufic titles under `title` `raqq`, never by default | Alif Type's release v2.00, installed as released | AGPL-3.0-or-later |
| Noto Nastaliq Urdu | Persian and Urdu text, titles and glosses under `persian` | nixpkgs `noto-fonts` | OFL-1.1 |
| Noto Naskh Arabic | What Amiri lacks | nixpkgs `noto-fonts` | OFL-1.1 |
| Cascadia Mono | Code, Arabic in code included | nixpkgs `cascadia-code` | OFL-1.1 |

```nix
# With inputs.imprimeur.flake = false.  Under Home Manager: home.packages, and fonts.fontconfig.enable = true.
fonts.packages = import "${inputs.imprimeur}/imprimeur-skin-yaqut/fonts.nix" {inherit pkgs;};
```

**Raqq is under the AGPL**, version 3 or later, with no font exception. Showing a page in it is using the
font. A PDF or any other file that embeds it, whole or as a subset, is a work that conveys the font, so it
carries the AGPL's terms: its licence and the offer of its source. Under the default `title` no page names
Raqq. `fonts.nix` installs `Raqq.ttf` as Alif Type released it, with its `LICENSE` and `README.txt` beside
it, in `share/fonts/truetype/raqq/`.

**Aref Ruqaa is left out**, though it was chosen first for the glosses and the colophon, as Ruqaa is
the hand of glosses. The WebKit of an Emacs window, WebKitGTK 2.54.1, draws it without its letters' dots, so
that غرب reads as عرب: in both its release 1.008 and the build 1.003 of google/fonts, in Arabic, Urdu and
no language, with or without `text-rendering`, kerning and feature settings. Chromium 156 draws it whole.
The glosses and the colophon take Amiri's slanted face instead.

## Colour fonts

Before the skin relied on them, a probe rendered four lines at 64 px, `﴿كَتَبَ ٱلْكَاتِبُ﴾` and
`كَتَبَ ٱلْكَاتِبُ` in each face, and counted the reddish pixels of each line: in headless Chromium
156.0.8078.47, through the tests' DevTools client, and in an xwidget of Emacs 31.1, WebKitGTK 2.54.1, on an
Xvfb, as `make gallery` takes its pictures.

| Face | Chromium | WebKit of an Emacs window |
|---|---|---|
| Amiri Quran Colored, COLRv0 | Its marks in red, in place: 608 px | The same: 581 px |
| Raqq, COLRv0 and SVG | Its vowels as red dots, above, below and before their letters: 466 px | In colour, but its dots stand on the baseline, partly under the letters: 232 px |
| Aref Ruqaa Ink, COLRv1 | Red gradients, with blue marks in place: 2,250 px | In colour, with its marks out of place and its dots missing |
| Amiri, for comparison | None | None |

WebKit's `CSS.supports('font-tech(color-COLRv0)')` and `font-tech(color-COLRv1)` are both true. Both
colour faces stay, as neither is a default: Amiri Quran Colored draws as it should in
both, and Raqq, which `title` `raqq` alone names, misplaces its dots in an Emacs window. Reem Kufi Ink and
Aref Ruqaa Ink, which waited for this probe, stay out.

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in `imprimeur-skin-options`.

| Option | Values | Default |
|---|---|---|
| `preset` | `mamluk`, `ottoman`, `persian` | `mamluk` |
| `title` | `auto` follows the preset, `thuluth` Katibeh, `kufi` Qahiri, `raqq` Raqq, under the AGPL | `auto` |
| `notes` | `auto` follows the preset, `margin`, `oblique`, `foot` | `auto` |
| `calendar` | `umalqura` Umm al-Qura, `civil` the tabular civil calendar | `umalqura` |

```elisp
;; Every page starts in Yaqut.
(setq imprimeur-skin 'yaqut
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((yaqut (preset . "mamluk")
                                      ;; auto, thuluth, kufi or raqq.
                                      (title . "auto")
                                      ;; auto, margin, oblique or foot.
                                      (notes . "auto")
                                      ;; umalqura or civil.
                                      (calendar . "umalqura"))))
```

What each preset evokes and fixes:

| | Evokes | Text | Titles and headings | Glosses, under `auto` | Rules |
|---|---|---|---|---|---|
| `mamluk` | Baybars II's Qur'an at the British Library | Amiri | Katibeh, gold outlined in black; headings vermilion | Amiri slanted, in the margin | Gold, outlined in black |
| `ottoman` | Şeyh Hamdullah's school | Amiri | Katibeh in vermilion | Amiri slanted, in the margin | A gold cedvel between black, red and blue rules |
| `persian` | Hafiz's Divan, Walters W.631 | Noto Nastaliq Urdu under `fa` and `ur`, Amiri under `ar` | White Nastaliq on lapis | Nastaliq, oblique in the margin | Blue, gold, red and black, with wider margins |

There is no Kufic preset, as every Kufic model is a Qur'an: Kufic stays a title face. A page narrower than
600 px sets its notes at the foot, whatever `notes` says.

## Writing for it

| To show | In Org | In Markdown |
|---|---|---|
| Colophon, Hijri date, seal | `#+COLOPHON:`, `#+HIJRI:`, `#+SEAL:` | `colophon:`, `hijri:`, `seal:` in the front matter |
| A date for the colophon in the Hijri calendar | `#+DATE: 2026-11-09` | `date: 2026-11-09` |
| A gloss in the margin | `[fn::...]` | `[^1]` |
| A rubric, in vermilion and in gold | `/words/`, `*words*` | `*words*`, `**words**` |
| A commented base text, overlined in red | `#+begin_quote` | `> ` |
| A quotation in Amiri Quran Colored | `﴿...﴾` | `﴿...﴾` |

The colophon's date is `#+HIJRI:` as written, with the year sign U+0601 set before its last run of digits,
the year; or else `#+DATE`, when it opens with a date written `YYYY-MM-DD`, which the page writes in the
calendar of the option `calendar`, as day, month and year in Arabic with Arabic-Indic digits, the year
after the year sign. A seal alone, with no colophon, still closes the page. In Org, an emphasis needs a
space or an ASCII sign after its closing mark, so `/words/،` is no emphasis: write `/words/ ،` or put the
comma inside.

## Limits

- **WebKit and Chromium.** Tried in WebKit at scale 1 on a virtual display and in headless Chromium, not on a
  real Wayland session or on a Mac. Raqq misplaces its dots in an Emacs window, as the table above says.
- **No kashida.** WebKitGTK 2.54 justifies only at spaces, and Chromium 156 opens no cursive run to
  justification either. Amiri draws the tatweels an author types, as the maqama's verse has them.
- **Glosses.** They stand at the start of the block that holds their notes, one block of glosses for one
  block of text, as Chromium places floats anchored on one line out of their order. A heading's stand in a
  block of their own just before it, so that its title in a minitoc is its own: they start in the space above
  it, beside its rosette when it has one, and a minitoc reads them as text of the section before. A note in a
  table cell floats from the cell. A copy of a block in the margin holds its glosses before its text. The
  footnotes' numbers are pandoc's, in ASCII digits.
- **Colophon.** Its triangle is as many lines as the module counts, at most 40; longer words run on below.
- **Later.** Leaves with their limits every 13, 15 or 14 lines, catchwords, and a kashida experiment, are
  for a later version.

## What only a reader of Arabic or Persian can judge

These stay open:

- every label and every word that the skin writes, such as the month names, which Intl gives;
- whether Katibeh passes for thuluth;
- whether the gold outlines and the oblique glosses read as refined or as kitsch;
- whether justifying only at spaces leaves rivers in Amiri;
- whether Amiri's slanted face serves glosses where a Ruqaa would;
- whether the samples are transcribed faithfully, and whether their colophons, seals and headings, which are
  the editor's, are written correctly.

# Why these skins and faces

A plain page would do. The skins exist because a document's look carries part of what it says: a
French book of the XVIII<sup>th</sup> century and a business memo answer different questions at a
glance, and the same engine can set both. Each one is a whole convention, with what it brings and
what it gives up, and not a set of colours.

## Why packages

A skin is a package of its own, so that you install what you want and nothing else: Tianlu's fonts
alone take about 580 MB. Installing one is installing code: its stylesheet and its module run in
the page, its filters in pandoc, and its package with your rights. imprimeur requires no skin, and a
skin requires `imprimeur-skin` alone, so either side can change without the other's internals.

## Why a manifest of data

`imprimeur-skin-define` takes data, which `imprimeur-skin-parse-manifest` judges. A key that it
does not know is refused, so that a key added later is additive. What reaches the page or pandoc
from a skin is what was registered, compared as whole strings, so nothing from a page or a
document becomes a path, a pandoc argument or an attribute.

## Why no document chooses

A hostile document that could choose a skin or an option would choose what meets it. So the choice
is yours, in Emacs: `M-g s`, `M-g o` and your configuration. An option is also one type alone, a
choice among registered values, which the root carries as an attribute and which only the sheet
reads, so that no document can set it and nothing renders when it changes.

## Why faces are named and never served

A skin names fonts and ships none. Fonts have licences of their own, and the Ministry of Education's
two under Tianlu allow no derived work, so `fonts.nix` fetches each whole and installs it unchanged.
Raqq, under Yaqut, is under the AGPL with no font exception, so it is installed as released and no
page names it by default.
A page also loads nothing from the network by itself, a font included. So the page falls back through its
stacks on what is missing: a reader without the fonts still reads, in other faces. The look is
then lost, and on Écrivain so is the ruling, as its letters sit on it by a strut that is a font.

`fonts.nix` cuts some faces itself, as an installed variable font exposes no axes on Linux. That is why
Dubai's Kufi, Alexandria and Kufam, XIX's optical Bodoni and Écrivain's hands are families under names
of their own, and why installing them without Nix is harder.

## Why these Arabic faces

Each face was checked for its licence, its packaging at the pinned nixpkgs, and the features that
the skin relies on, against the font files where possible.

**Dubai** follows the pairing of the UAE Design System: Noto Kufi Arabic for text, Alexandria for
headings, Inter for Latin. Not Dubai Font itself, whose licence forbids passing it on, combining it
with other programs and using it in open source. A memo lines up figures: Noto Kufi's Arabic-Indic
digits are tabular, and Alexandria's are proportional, with no feature to change them, so
Alexandria sets headings alone. Kufam, drawn for the Khatt Foundation's brief of fonts for the
Dubai urban context, sets the masthead and the labels, as it was meant for signage, and gives Latin
labels true small capitals. The face `plex` swaps in IBM Plex Sans Arabic and Plex Sans: eight
static, hinted weights, with a Latin drawn to match. Set aside:

- Readex Pro, Almarai, Tajawal and Cairo, which have no tabular figures;
- Fustat, Mada and Cairo, which exist only as variable fonts; Fustat, which has tabular figures, is
  the next candidate if Noto Kufi does not hold up at body size;
- Vazirmatn, drawn to Persian proportions; Rubik, whose Arabic is upright only; Google Sans, which
  carries trademark limits; Alyamama, which is young.

**Yaqut** sets Amiri, a revival of the Bulaq type and the most literary free Naskh, with a Latin of
its own in true italics, a slanted face and the year sign. Katibeh, the only open approximation of
thuluth, sets titles and headings, and Qahiri, a manuscript Kufic, sets them under `title` `kufi`.
Raqq, a Kufic of the III<sup>rd</sup> century AH with red vowel dots, is offered and never a
default, as it is under the AGPL. Persian takes Noto Nastaliq Urdu, which has a Persian language
system: Gulzar is archived, and Awami needs Graphite. Amiri Quran Colored, the only coloured Naskh,
sets only what an author encloses in ﴿ ﴾. Set aside:

- Aref Ruqaa, chosen first for the glosses, as Ruqaa is their hand: the WebKit of an Emacs window
  draws it without its letters' dots, so Amiri's slanted face stands in;
- Scheherazade New, whose strength is the breadth of its languages, where Amiri is more literary;
  Markazi Text, a contemporary Naskh; Noto Naskh Arabic as a body face, as its OpenType is plain;
  Mirza, unmaintained since 2016;
- DigitalKhatt, which lacks Arabic punctuation and needs a fork of HarfBuzz; Kitab, which has no
  release; Qashib, Astrolabe and Rana Kufi, under the AGPL and for display only;
- Reem Kufi Ink and Aref Ruqaa Ink, which waited for a probe of colour fonts and stay out: WebKit
  set Aref Ruqaa Ink's marks out of place;
- DecoType, Diwan Mishafi, Arabic Typesetting, Aldhabi and Boutros Thuluth, which are proprietary,
  and KFGQPC Uthmanic Hafs, whose licence contradicts itself and which is for the Qur'an alone.

Both skins set code in Cascadia Mono, whose upright faces hold Arabic; Kawkab Mono has not changed
since 2016.

## What each skin gives up

- **Tianlu** sets vertical text in bands that still scroll down, as a preview follows by scrolling, so
  it is not a true page of leaves. Code, diagrams and pictures are horizontal plates. Its sample
  essays have not been checked by a reader of Chinese.
- **Dubai** answers first, as Briefing does, right to left. Its text stays ragged, as WebKitGTK
  justifies only at spaces and no engine here draws kashida, and it rewrites no digit, as that would
  change what a reader copies. A document in any language but Arabic takes English labels. Its
  samples and labels have not been checked by a reader of Arabic.
- **Yaqut** keeps a manuscript's frames, glosses and colophon on a page that scrolls, with no leaves
  or catchwords yet. It justifies at spaces alone, with no kashida. It has no Kufic preset, as every
  Kufic model is a Qur'an, and no figural ornament. Its samples have not been checked by a reader of
  Arabic or Persian.
- **Minitel** takes every colour from your theme and Emacs's own family, so it looks like your
  Emacs. It takes keys from the page's Emacs window, so `q` does not quit there.
- **XIX**, **XVIII** and **XVII** have colours of their own, not your theme's, as a book of a
  century has its paper. They set French and English: any other language stays whole and ragged.
  XVII's long s and ties are font features, so that a copy or a search still sees an s.
- **Briefing** answers first, with a bottom line and callouts, so a document must be written for it
  to gain most. It stays ragged, as a memo does.
- **Écrivain** keeps letters on a ruling, so blocks stay whole on the grid and leave blank lines at a
  leaf's foot.

Each skin's README has its full list under "Limits". All of them have run in WebKit at scale 1 on a
virtual display and in headless Chromium, not on a real Wayland session or on a Mac.

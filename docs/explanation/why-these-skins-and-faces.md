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
A page also loads nothing from the network by itself, a font included. So the page falls back through its
stacks on what is missing: a reader without the fonts still reads, in other faces. The look is
then lost, and on Écrivain so is the ruling, as its letters sit on it by a strut that is a font.

`fonts.nix` cuts some faces itself, as an installed variable font exposes no axes on Linux. That is why
XIX's optical Bodoni and Écrivain's hands are families under names of their own, and why installing
them without Nix is harder.

## What each skin gives up

- **Tianlu** sets vertical text in bands that still scroll down, as a preview follows by scrolling, so
  it is not a true page of leaves. Code, diagrams and pictures are horizontal plates. Its sample
  essays have not been checked by a reader of Chinese.
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

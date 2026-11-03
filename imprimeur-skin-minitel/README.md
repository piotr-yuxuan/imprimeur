# imprimeur-skin-minitel

The skin Minitel of [imprimeur](../README.md#skins): a tribute to the terminal, not a costume
of it. An 80-column block of one monospace family, in a thin rounded frame that stays on the
screen; row 0 above it, in the mode line's colours; the terminal's keys below. The terminal's
own attributes make the hierarchy: double size, double height, an inverse band, then underline
and bold, and separated sextants, its mosaics, are the rules. Every colour is your Emacs theme's
by default. No scanlines, no dithering, no curved screen. `../examples/minitel/` holds two real
texts, Robida's telephonoscope of 1883 and Wells's Babble Machines of 1899, with their sources.

With this package installed, `imprimeur-skin` at its default, `auto`, starts every page here.

## Fonts

The skin vendors none and installs none, so it has no `fonts.nix`: it asks for the family of
Emacs's default face, then `monospace`. Its rules are the mosaics of U+1CE51 to U+1CE8F, which
Iosevka holds; a family without them shows its fallback there. Its 1.25 of line height is what
lets those mosaics and the frame meet.

## Keys

Each key of the bar answers to its name below, or a click on it. In an Emacs window, a view hands
these to the page by a map of its own, and takes them back when you choose another skin. Their
case is exact.

| Key | On the bar | What it does |
|---|---|---|
| `s` | SOMMAIRE | The headings, chosen by number, Enter or a click |
| Esc | ANNULATION | Closes the screen, clears the choice |
| `p` | RETOUR | The previous heading |
| `g` | RÉPÉTITION | Makes the page again; at F, the latest revision, staying at F |
| `?` | GUIDE | The list of these |
| `e` | CORRECTION | Rubs out a digit of the choice; otherwise goes to the source |
| `n` | SUITE | The next heading |
| RET | ENVOI | Confirms the choice, or the entry that has the focus |
| `q` | CONNEXION/FIN | Follow Emacs, or stop: C or F in row 0 |

The letter in row 0 is C while the page follows Emacs, its revisions and its scrolling, and F
while it holds where it is; a click on it is the same as `q`. Once the session has ended F stays.
`e` at F still goes to the source, and the echo area says that the place may have moved.

**What a view gives up.** While Minitel is shown, `s p n ? e g q` are the page's and not the
view's, so `q` does not quit the view: `C-x k` does, or `M-g s` to another skin gives it back.
The rest is shared, and a key the page declines does what it did before: DEL scrolls back unless
it is rubbing out a digit, a digit is a prefix argument outside SOMMAIRE, Esc and RET are Emacs's
outside a screen, and `q`, `g` and `e` are Emacs's once the session has ended. `C-g` and anything
with a modifier are never the page's, so ANNULATION answers to Esc and not to `C-g`.

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in `imprimeur-skin-options`.

| Option    | Values                    | Default |
|-----------|---------------------------|---------|
| `palette` | `emacs`, `videotex`, `greys` | `emacs` |
| `columns` | `80`, `40`                | `80`    |
| `keys`    | `fixed`, `end`, `off`     | `fixed` |

- **`palette`:** Emacs's colours, each past a floor of lightness that the ground's own luminance
  sets, so that what a theme gives reads on any ground; Vidéotex's eight colours; or the eight
  greys that a Minitel 1 made of them, where code tells its tokens apart by weight and slant too
  and pictures go grey. Each has a day and a night, by the page's appearance.
- **`columns`:** 80, or the purist's 40 in letters up to 24 px, as many as the Emacs window
  holds. At 40 the bar waits at the end of the document, as it no longer fits on two rows.
- **`keys`:** two rows at the foot of the screen, or the bar at the end of the document, or none.
  The keys answer in each case. Below 620 px of width or 480 px of height, the bar waits at the
  end too.

```elisp
;; Every page starts in Minitel, whichever other skins are installed.
(setq imprimeur-skin 'minitel
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((minitel (palette . "emacs")
                                        (columns . "80")
                                        (keys . "fixed"))))
```

## Limits

Contrast is at least 4.5:1 on what the page chooses, but a theme's own mode line is left as it is,
and two of Emacs's themes, leuven and leuven-dark, stay under it in row 0. On a mid grey the inks
are black or white: readable and dull. `g` at C reloads the page, which an Emacs window's watchdog
takes for a page lost: pressed twice within a minute, it may say so for a moment. Mermaid draws in
its own spacing, so a wide diagram shrinks. A film has no codecs in the WebKit of an Emacs window
here, so it shows its poster, if the document names one in raw HTML, and a link. The GUIDE and the
names of alerts speak French and English alone. Print is not done, nor a cursor that blinks. Tried
in WebKit at scale 1 on a virtual display and in headless Chromium, not on a real Wayland session
or on a Mac.

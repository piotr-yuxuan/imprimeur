# Commands and keys

## imprimeur's commands

| Command | Key | What it does |
|---|---|---|
| `imprimeur-mode` | | Opens the page of this buffer, or closes it. The mode survives a change of major mode when the new mode has a reader in `imprimeur-reader-alist`, and ends otherwise. |
| `imprimeur-show` | | Shows the page where `imprimeur-target` says, after you quit its Emacs window or killed its buffer. |
| `imprimeur-jump` | `M-g v` | From the source, brings the block of point's line to the top of the page and marks it for a moment; a hidden page is shown, and the window start stays. From the page's Emacs window, selects the source, with point on the line of the page's top block, opening a fold there. |
| `imprimeur-choose-skin` | `M-g s` | Shows this page in another skin, keeping your place, for as long as the mode lasts. |
| `imprimeur-set-skin-option` | `M-g o` | Gives an option of this page's skin another value, and says the entry that keeps it in `imprimeur-skin-options`. |
| `imprimeur-follow-mode` | | Turns the following of each other's scrolling off or on, in this buffer. Turned on, the page goes at once to where the source is. |
| `imprimeur-browse` | | Opens the page in a desktop window of the browser, whatever `imprimeur-target` says. |
| `imprimeur-copy-url` | | Copies the page's address. Anyone on this machine who has it can read the page while the mode is on. |
| `imprimeur-refresh-palette` | | Gives the page the current colours and fonts, after a change that no switch of theme made. |
| `imprimeur-stop-all` | | Closes every page. So do killing the buffer and leaving Emacs. |

## The page's Emacs window

It shows the buffer `*imprimeur: NAME*`, in the minor mode `imprimeur-view-mode`.

| Command | Key | What it does |
|---|---|---|
| `imprimeur-view-scroll-up` | `SPC`, and what `C-v` runs | Scrolls towards the end, by a prefix's lines or by nearly a page. |
| `imprimeur-view-scroll-down` | `S-SPC`, `DEL`, and what `M-v` runs | Scrolls towards the start, likewise. |
| `imprimeur-view-next-line` | What `C-n` runs | Scrolls towards the end by lines. |
| `imprimeur-view-previous-line` | What `C-p` runs | Scrolls towards the start by lines. |
| `imprimeur-view-top` | What `M-<` runs | Goes to the start of the page. |
| `imprimeur-view-bottom` | What `M->` runs | Goes to the end of the page. |
| `imprimeur-view-copy-selection` | What copies in `xwidget-webkit-mode` | Puts the page's selection on the kill ring, without its soft hyphens. |
| `imprimeur-view-forward-key` | The page's keys below | Gives the key to the page, and runs what the key has otherwise if the page declines it. |

`M-g v`, `M-g s` and `M-g o` work here too. `q` takes the Emacs window away and leaves the
page live, so that `imprimeur-show` or `M-g v` brings it back, unless the skin takes `q`.
Killing that buffer asks nothing and keeps the mode on, and `imprimeur-show` makes it anew.
Killing the source kills it too.

## The page's own keys

These work in the page, whichever way it is shown. In its Emacs window they are forwarded,
without a modifier only. A key that the page has nothing to do with stays what it was, so
`+` and `-` zoom while the popover is closed. `Esc` being forwarded, it is no longer a way
to type `M-` there.

| Key | What it does |
|---|---|
| `t` | Opens or closes the popover of the pill. |
| `+`, `-` | With the popover open, lists one level more or one fewer. |
| `]`, `[` | Goes to the next or the previous entry of the section at the top of the view. |
| `u` | Goes to the heading above. |
| `Escape` | Closes the popover, then the inline minitoc. A skin's module may take it when no minitoc is open. |
| `S`, `O` | Kept for the core: no skin may take them, and nothing answers to them yet. |

A skin's module may take other keys, by its manifest's `:keys`. Those are the only ones of
the seven skins' that do so, all of Minitel's:

| Key | What it does in Minitel |
|---|---|
| `s` | SOMMAIRE: the headings, chosen by number. |
| `p`, `n` | RETOUR, SUITE: the previous or the next heading. |
| `?` | GUIDE: the list of these. |
| `e` | CORRECTION: rubs out a digit, or goes to the source. |
| `g` | RÉPÉTITION: makes the page again. |
| `q` | CONNEXION/FIN: follows Emacs, or stops. |
| `0`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9` | A digit of the choice in SOMMAIRE. |
| `Enter`, `Backspace`, `Escape` | ENVOI, a digit rubbed out, ANNULATION. |

[Minitel's README](../../imprimeur-skin-minitel/README.md#keys) says what these take from
the page's Emacs window.

## What the mouse does

**A double-click on the page** puts point on the nearest line it knows, shows the source if
it is hidden, opens the fold around that line and flashes it, with the following on or off.
It asks for nothing on a link, a video, a sound, the `summary` of some details, a minitoc or
the banner, as a click already serves those or they have no line.

**A link** goes through Emacs: web addresses open with `browse-url`, and documents and media
under the document's root with `find-file-other-window`. For any other link, Emacs says that
it leads nowhere.

**The pill**, in the top right corner of a page with headings, says where you are and opens
the popover, with the scopes "This section" and "Document", and `-` and `+` buttons for the
depth. An entry takes you to its heading. **A button** such as `▸ 3`, on a heading that begins
a run, opens its inline minitoc, one at a time.

## What folds and following do

Scrolling the page across a fold leaves it closed: the source's window start rests on its
heading, and the page stays where you put it. Only a jump opens a fold: a double-click, or
`M-g v` from the page's Emacs window.

Following goes by the blocks' lines in Org and Markdown, and by proportion in other formats.
Two pages of one buffer, in an Emacs window and in a browser, follow the source and not each
other.

In a browser, all of this holds, but Emacs does not bring its own Emacs frame forward, so
after a double-click the focus stays in the browser.

## sommaire's commands

| Command | Key | What it does |
|---|---|---|
| `sommaire-mode` | | Shows the minitocs in this Org or Markdown buffer. |
| `sommaire-jump` | `M-g m` | Asks for a heading of the scope and goes there, leaving the mark. `C-u` offers the whole document, and a numeric prefix that many levels, this once. |
| `sommaire-panel` | A click on the segment | Shows the scope in a side Emacs window, or closes it. |
| `sommaire-toggle-inline` | A click on a button | Opens or closes the inline minitoc of the nearest heading around point that has one. |
| `sommaire-follow-inline` | A click on an entry | Goes to the heading of that inline entry. |

Each Emacs window shows at most one inline minitoc. A folded heading refuses to open one. A
jump to a heading inside a fold stops at the fold, leaves it closed and says so.

## sommaire's panel

Its buffer is in `sommaire-panel-mode`.

| Command | Key | What it does |
|---|---|---|
| `sommaire-panel-jump` | `RET`, `<mouse-1>` | Goes to the heading of that entry. |
| `sommaire-panel-deeper` | `+` | Lists one level more. At the deepest level that the list has, every level, which holds in the deeper sections you move to. |
| `sommaire-panel-shallower` | `-` | Lists one level fewer. |
| `sommaire-panel-toggle-root` | `r` | Lists from the document, or from the section around point again, keeping the depth. |
| `sommaire-panel-close` | `q` | Closes the panel. |

What these keys change holds for that buffer alone, so that `clone-indirect-buffer` gives
each Emacs window a list of its own.

## What sommaire shows

**The segment**, in the header line, after whatever that already holds, reads like
`§ Sizes of type ▾3 › Long primer`: the section, the number of its entries and the entry that
holds point. With nothing else in the header line, it shows the heading path too.

**An entry** reads like its heading as displayed, without the TODO keyword, priority, tags and
statistics cookies, or takes the heading's `ALT_TITLE`. [The rules](minitoc-rules.md) say which
headings are listed and which have a button.

**Limits.** Inline markup other than links, emphasis and code, such as an entity, a footnote's
mark or raw HTML, shows as its source has it. A buffer of more than 1,000,000 accessible
characters is not read: sommaire says so, and lists nothing until you narrow to less.

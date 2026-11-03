# imprimeur

[![GitHub licence](https://img.shields.io/github/license/piotr-yuxuan/imprimeur)](#licence)
[![GitHub issues](https://img.shields.io/github/issues/piotr-yuxuan/imprimeur)](https://github.com/piotr-yuxuan/imprimeur/issues)

![A cheerful letterpress turns a plain-text sheet with Org and Markdown marks into a typeset page with a red drop cap.](docs/social-media-preview.png)

imprimeur shows the Org or Markdown buffer you are editing as a typeset
page, within one Emacs frame: one Emacs window shows the source and the
other the page. The page follows every change a moment after you stop
typing, saved or not, and replaces only the blocks you touched. Each of the
two follows the other's scrolling, and a double-click on the page puts point
on that place in the source. It shows your pictures, tables, code, maths,
Mermaid diagrams and videos, in the colours of your Emacs theme, and follows
a switch of theme without reloading. No document runs code in it, and an
untrusted one makes it fetch nothing from the network. Install it with
straight.el, then type `M-x imprimeur-mode` in the buffer. An Emacs without
xwidgets, or on a text terminal, shows the page in a desktop window of
Chromium instead.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/emacs-view-dark.png">
  <img alt="One Emacs frame holding two Emacs windows: an Org buffer on the left and, on the right, the same document typeset, in the colours of the Emacs theme." src="docs/images/emacs-view.png">
</picture>

It is pre-release, in the one skin it has so far (see [Status](#status)).
Xwidgets, which put the page in an Emacs window, are experimental in Emacs:
[try them first](#try-xwidgets-first). So far the Emacs window has run on a
virtual X display alone: a real Wayland session has not been tried.

## Install

You need Emacs 30.1 or later, [pandoc](https://pandoc.org/) 3 (tested with
3.7.0.2), and something to show the page in:

- for an Emacs window, an Emacs built with xwidgets (`--with-xwidgets`), on
  which `(featurep 'xwidget-internal)` is `t`. Tried with Emacs 31.1 built
  for PGTK and WebKitGTK 2.54.1, and with nothing else;
- for a desktop window, Chromium, or a browser that takes Chromium's options.

For Markdown, `markdown-mode`. For Mermaid diagrams,
[mermaid-cli](https://github.com/mermaid-js/mermaid-cli) (tested with
12.0.0), whose copy of Mermaid the page uses, or a Mermaid script of your
own.

With [straight.el](https://github.com/radian-software/straight.el) and
`use-package`:

```elisp
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       ;; The repository holds two packages: take this one's
                       ;; Lisp files and the page's assets, which it finds
                       ;; beside them.
                       :files ("imprimeur/*.el" "imprimeur/assets")))
```

To work from a clone, add `:local-repo "<clone>"` to the recipe.

### Try xwidgets first

Xwidgets are experimental in Emacs: its own `etc/NEWS.29` says so of a video
in an xwidget, and that this is known to crash Emacs on some systems. A crash
takes your unsaved text with it. So try them in a separate Emacs before you
rely on them, from a clone:

```sh
nix develop --command make smoke-xwidget
```

This runs a separate `emacs -Q`, in a scratch home, on your display, for about
half a minute. It opens real pages in a desktop window of its own and prints
`PASS` or `FAIL` for each thing it checks: where the page opens, that the two
follow each other, `M-g v` both ways, a double-click on folded text, a palette,
a hostile document, a WebKit process that dies, what killing either buffer
asks. It also prints `REPORT` lines, such as what WebKit makes of a video.
Outside `nix develop`, name your Emacs with `EMACS=` and have pandoc and ffmpeg
on your path. If it fails, or you would rather not,
`(setq imprimeur-target 'browser)` keeps xwidgets out of it.

## Configure

Nothing is required. The package binds no key and changes nothing until
you turn the mode on, which adds `M-g v` where the mode is on. An example
with every option at its default value:

```elisp
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       :files ("imprimeur/*.el" "imprimeur/assets"))
  ;; A key of your own: `imprimeur-mode' toggles the page of this buffer.
  :bind ("C-c i" . imprimeur-mode)
  :custom
  ;; Where the page opens: `auto', in an Emacs window when the selected Emacs
  ;; frame is graphic and this Emacs has xwidgets, and otherwise in a desktop
  ;; window of the browser; `xwidget', in an Emacs window, refusing where that
  ;; cannot run; `browser', in a desktop window of the browser.
  (imprimeur-target 'auto)
  ;; How `display-buffer' shows the page in an Emacs window: on the right of
  ;; the Emacs frame, over half its width, in an Emacs window that shows nothing
  ;; else; the source stays selected.  '((display-buffer-same-window)) takes
  ;; the source's Emacs window instead, and quitting brings the source back.
  (imprimeur-display-buffer-action
   '((display-buffer-reuse-window display-buffer-in-direction)
     (direction . right)
     (window . root)
     (window-width . 0.5)
     (dedicated . t)
     (reusable-frames . visible)))
  ;; Which way the page and the source follow each other's scrolling: `both';
  ;; `to-preview', the page follows the source alone; nil, neither, until you
  ;; turn `imprimeur-follow-mode' on by hand, when each follows the other.
  (imprimeur-scroll-sync 'both)
  ;; The browser that shows the page in a desktop window, with a profile of
  ;; its own.  Browsers built on Chromium take the same options, such as
  ;; "google-chrome-stable" or "brave"; only Chromium is tested.
  (imprimeur-browser-program "chromium")
  ;; pandoc 3.  A wrapper that adds options of its own is fine, as long as
  ;; the output stays a bare fragment: neither standalone nor with text
  ;; included before the body.
  (imprimeur-pandoc-program "pandoc")
  ;; Seconds after which a render is abandoned, and its error shown.
  (imprimeur-render-timeout 20)
  ;; Render 0.3 s after you stop typing, and every 2 s at least while you
  ;; type without a pause.
  (imprimeur-render-delay 0.3)
  (imprimeur-render-max-delay 2.0)
  ;; Load remote images (badges, pictures on the web) only for documents
  ;; that `trusted-content' accepts; nil never, t always.  Elsewhere each
  ;; one is a link that names its host, and nothing is fetched.
  (imprimeur-remote-images 'trusted)
  ;; Whether the page is light or dark: `auto' follows the background mode
  ;; of the Emacs frame that gives it its colours; `light' and `dark' force
  ;; one.  Emacs's colours stay: this chooses what stands in where a face
  ;; gives none.
  (imprimeur-appearance 'auto)
  ;; The Mermaid script with which the page draws diagrams: nil finds the
  ;; copy beside the program mmdc, from mermaid-cli; a file name uses that
  ;; file, a classic script that sets the global mermaid, which runs in the
  ;; page.  Without a script a diagram stays as code: the page never fetches
  ;; one from the network.
  (imprimeur-mermaid-script nil)
  :config
  ;; Markdown files without markdown-mode: choose the reader by file name.
  ;; Each entry is a major mode or a file-name pattern, and a pandoc reader.
  (add-to-list 'imprimeur-reader-alist '("\\.md\\'" . "gfm+sourcepos") t))

;; Documents you trust, such as your own notes, may load remote images and
;; include other files with #+INCLUDE: pandoc then runs without its sandbox.
;; This is Emacs's own option (Emacs 30), shared with other packages, some
;; of which then run code from those files: list only what you wrote.
(setq trusted-content '("~/notes/"))
```

## Use

In an Org or Markdown buffer, `M-x imprimeur-mode` opens the page in an Emacs
window on the right of the Emacs frame, and the source stays selected. Then
type: the page shows the buffer's text a moment after each change, and what
you did not touch stays as it is. Pictures and videos under the document's
directory, or under its git repository, show in the page.

| Command | What it does |
|---|---|
| `imprimeur-mode` | Opens the page of this buffer, or closes it. |
| `imprimeur-show` | Shows the page where `imprimeur-target` says, after you quit its Emacs window or killed its buffer. |
| `imprimeur-jump`, `M-g v` | From the source, brings point's block to the top of the page; from the page's Emacs window, goes back to the source. |
| `imprimeur-follow-mode` | Turns the following of each other's scrolling off or on, in this buffer. |
| `imprimeur-browse` | Opens the page in a desktop window of the browser, whatever `imprimeur-target` says, or again after you closed it. |
| `imprimeur-copy-url` | Copies the page's address, to open it in another browser. Anyone on this machine who has it can read the page while the mode is on. |
| `imprimeur-refresh-palette` | Gives the page the current colours and fonts, after a change that no switch of theme made, such as a new `imprimeur-appearance`. |
| `imprimeur-stop-all` | Closes every page; so do killing the buffer and leaving Emacs. |

Links in the page go through Emacs: web addresses open with `browse-url`,
and documents or media under the document's root with
`find-file-other-window`; for any other link, Emacs says that it leads
nowhere. If pandoc fails, the page keeps the last good version and shows
pandoc's message above it.

**The page's Emacs window.** It shows the buffer `*imprimeur: NAME*`, whose
scrolling keys scroll the page: `SPC`, `S-SPC`, `DEL`, `C-v`, `M-v`, `C-n`,
`C-p`, `M-<` and `M->`. `q` takes the Emacs window away and leaves the page
live, so that `imprimeur-show` or `M-g v` brings it back. Killing that buffer
keeps the mode on, and `imprimeur-show` makes it anew. Killing the source kills
it too, and neither asks anything.

**Following.** The source and the page follow each other's scrolling, aligned
from the moment the page opens. That is `imprimeur-follow-mode`, local to the
buffer, which comes on with the page. Turn it off and neither moves for the
other, while the page goes on showing your text; turn it on and the page goes
at once to where the source is. `imprimeur-scroll-sync` says the directions, and
nil leaves the mode off in a new session. It goes by the blocks' lines in Org
and Markdown, as nearly as they allow, and by proportion in the other formats.

**A double-click on the page** puts point on the nearest line it knows, shows
the source if it is hidden, opens the fold around that line and flashes it. A
double-click on a link, a video, a sound or the `summary` of some details asks
for nothing, as a click already serves them, and neither does one on the banner,
which has no line. It works with the following off.

**`M-g v`** goes the other way. In the source it brings the block of point's
line to the top of the page and marks it for a moment, without motion if your
system asks for none; the window start stays where it is, and a hidden page is
shown. In the page's Emacs window, the same key selects the source, with point
on the line of the page's top block. The key exists only where the mode is on,
under Emacs's prefix for going somewhere; `imprimeur-jump` can be bound to any
other.

**Folded text is yours.** Scrolling the page across a fold leaves it closed:
the source's window start rests on its heading, and the page stays where you
put it. Only a jump opens a fold: a double-click, or `M-g v` from the page's
Emacs window.

**In a browser.** With `imprimeur-target` at `browser`, or at `auto` where Emacs
has no xwidgets or the Emacs frame is not graphic, the page opens in a desktop
window of Chromium, in its app mode; `imprimeur-browse` opens it there at any
time. Following, the double-click and `M-g v` hold there too, with one
difference: Emacs does not bring its own Emacs frame forward, which Wayland
would not let it do, so after a double-click in the browser's desktop window
point has moved in the source and the focus stays in the browser.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/emacs-and-page-dark.png">
  <img alt="An Org buffer in Emacs on the left; on the right, the same document typeset in a desktop window of Chromium, in the colours of the Emacs theme." src="docs/images/emacs-and-page.png">
</picture>

**Colours.** The page takes its colours and fonts from the faces of the
Emacs frame that shows the buffer, and its own light and dark colours only
where a face gives none. A switch of theme, by hand or by a package such as
auto-dark, recolours the page at once, and nothing reloads.

**Diagrams.** A Mermaid block, `#+begin_src mermaid` or a fence named
`mermaid`, is drawn in those colours when the page has a Mermaid script: the
copy that mermaid-cli installs beside its program `mmdc`, or the file that
`imprimeur-mermaid-script` names. Without one, the block stays as code. A
source that does not parse keeps its last drawing, with the message beneath.

**Videos.** In Chromium, a video plays and seeks, and keeps playing while you
type elsewhere. One that the page cannot play gets a link, "Open externally":
Emacs visits the file, and a media package such as ready-player can play it.

In an Emacs window, WebKit plays video through GStreamer, whose plugins must be
in the environment of the Emacs that runs it: those your system installs, or
those that `GST_PLUGIN_SYSTEM_PATH_1_0` names. Without them, a video stays on a
still picture with a play disc that does nothing. So far it has done no more
with them, on a virtual display, where WebKit says that it can play the clip and
then asks for none of it; whether one plays in a real Emacs frame is not known
yet, and `make smoke-xwidget` reports it, with plugins and without. Either way
the page offers the same link, and `imprimeur-browse` shows the page where
videos play.

**Tables and maths.** A table too wide for the page scrolls by itself, and
long addresses in a cell break. LaTeX maths in Org and Markdown shows as
MathML, in a maths font if you have one, such as Libertinus Math or DejaVu
Math TeX Gyre; [how it works](docs/how-it-works.md#tables-and-maths) lists
the forms that each format reads.

The formats are those of `imprimeur-reader-alist`: Org, Markdown (GitHub's
dialect), reStructuredText, MediaWiki, Textile, Creole, POD, Jupyter
notebooks, CSV and TSV.

![A Markdown document typeset by imprimeur, with a table, code, a diagram, a task list and a picture.](docs/images/markdown-page.png)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/architecture-dark.svg">
  <img alt="How imprimeur shows a buffer: Emacs sends the unsaved text to pandoc, serves the result on 127.0.0.1 under a token, and a page in an xwidget or in Chromium fetches, sanitises and shows it; links, scrolling and double-clicks come back to Emacs." src="docs/images/architecture.svg">
</picture>

A moment after you stop typing, Emacs sends the whole buffer to pandoc,
which returns HTML. A small HTTP server inside Emacs, on 127.0.0.1 only,
tells the page that a new version exists; the page fetches it, sanitises
it and replaces only the blocks that changed. [How imprimeur
works](docs/how-it-works.md) follows one edit to the page, explains the
scheduling, the page's Emacs window, scroll sync, the colours, the diagrams
and the videos, and lists every defence against a hostile document.

## Security

A document you open may come from anyone. imprimeur treats it as untrusted
unless Emacs's `trusted-content` says otherwise:

- pandoc runs with `--sandbox`, so a document cannot include other files;
- the page runs no script from the document: each version is sanitised
  with DOMPurify, and every response carries a strict Content Security
  Policy;
- a diagram is drawn by Mermaid in its strict mode, under settings that no
  document can change, and what it draws is sanitised again; the script
  comes from your disk, never from the network;
- the page navigates nowhere by itself: Emacs decides where each link may
  lead, and in an Emacs window it can save no file, open no other xwidget and
  stay on no other site;
- what the page tells Emacs of scrolling and double-clicks holds integers
  alone;
- remote images load only for trusted documents;
- the server listens on 127.0.0.1 only, under a random token per page,
  and checks the `Host` of each request and the `Origin` of each message
  from the page, against other web pages and other users of the machine;
- the browser's desktop window has a profile of its own, deleted
  afterwards, and the token appears in no process's command line.

The tests check each of these against hostile documents and diagrams in a
headless Chromium. WebKit, which those tests do not reach, gets one hostile
document from `make smoke-xwidget`.

## Status

Pre-release, built one plan at a time. Done: the page in an Emacs window beside
the one showing the source buffer, within one Emacs frame, or else in Chromium's
desktop window, live, safe, in the core of the Minitel skin; the Emacs theme's
colours, which follow auto-dark without a reload; Mermaid diagrams; videos that
seek, in Chromium; an update that replaces only the blocks you touched; scroll
sync both ways, a double-click to the source and `M-g v` to the page. Next:
typeset skins (French books of the XVII<sup>th</sup>, XVIII<sup>th</sup> and
XIX<sup>th</sup> centuries, a business briefing, a vertical Chinese page, a
handwritten notebook).

Not yet tried: a real Wayland session, as the Emacs window has run on Xvfb
alone, through `GDK_BACKEND=x11`; a wheel, keys and a double-click by a person's
hand in the xwidget, which the checks synthesise or leave out; and whether a
video plays there at all.

This repository also holds **sommaire**, a second package to come: mini
tables of contents in Org and Markdown buffers, one for the section around
point and one under a heading on request, never stacked. It will work
without imprimeur.

## Development

The checks run in `nix develop`, which provides every tool and the
packages' minimum Emacs versions:

```sh
nix develop --command make check
nix develop --command make test-min
```

`make smoke-xwidget` is apart, as it opens a desktop window: [try xwidgets
first](#try-xwidgets-first).

`nix develop --accept-flake-config` fetches Emacs 29.1 and 30.1 from the
binary cache of nix-emacs-ci instead of building them. `AGENTS.md` gives
the workflow and the rules.

## Licence

imprimeur and sommaire are licensed under the European Union Public
Licence 1.2 (`LICENSE`) or, at your option, the GNU General Public License,
version 3 or any later version (`COPYING`): `EUPL-1.2 OR GPL-3.0-or-later`.

imprimeur ships a copy of DOMPurify, under the Apache License 2.0 or the
Mozilla Public License 2.0: see `imprimeur/assets/vendor/dompurify/`.

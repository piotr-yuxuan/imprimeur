# imprimeur

[![GitHub licence](https://img.shields.io/github/license/piotr-yuxuan/imprimeur)](#licence)
[![GitHub issues](https://img.shields.io/github/issues/piotr-yuxuan/imprimeur)](https://github.com/piotr-yuxuan/imprimeur/issues)

![A cheerful letterpress turns a plain-text sheet with Org and Markdown marks into a typeset page with a red drop cap.](docs/social-media-preview.png)

imprimeur shows the Org or Markdown buffer you are editing as a typeset
page, in a desktop window beside your Emacs frame. The page follows every
change a moment after you stop typing, saved or not, and replaces only the
blocks you touched. It shows your pictures, tables, code, maths, Mermaid
diagrams and videos, in the colours of your Emacs theme, and follows a
switch of theme without reloading. No document runs code in it, and an
untrusted one makes it fetch nothing from the network. Install it with
straight.el, then type `M-x imprimeur-mode` in the buffer.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/emacs-and-page-dark.png">
  <img alt="An Org buffer in Emacs on the left; on the right, the same document typeset in a desktop window of Chromium, in the colours of the Emacs theme." src="docs/images/emacs-and-page.png">
</picture>

It is pre-release: the page opens in Chromium's own desktop window, in the
one skin it has so far. The aim is a view inside Emacs: within one Emacs
frame, two Emacs windows, one showing the source buffer and the other the
page. That, scroll sync and more skins arrive next (see
[Status](#status)).

The repository holds a second package, [sommaire](#sommaire), which shows
where you are in a long Org or Markdown buffer and works without imprimeur.

## Install

You need Emacs 30.1 or later, [pandoc](https://pandoc.org/) 3 (tested with
3.7.0.2) and Chromium, or a browser that takes Chromium's options. For
Markdown, `markdown-mode`. For Mermaid diagrams,
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

## Configure

Nothing is required. The package binds no key and changes nothing until
you turn the mode on. An example with every option at its default value:

```elisp
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       :files ("imprimeur/*.el" "imprimeur/assets"))
  ;; A key of your own: `imprimeur-mode' toggles the page of this buffer.
  :bind ("C-c i" . imprimeur-mode)
  :custom
  ;; The browser that shows the page, in a desktop window and a profile of
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

In an Org or Markdown buffer, `M-x imprimeur-mode` opens the page in a
desktop window of Chromium, in its app mode. Then type: the page shows the
buffer's text a moment after each change, and what you did not touch stays
as it is. Pictures and videos under the document's directory, or under its
git repository, show in the page.

| Command                     | What it does                                                                                                                        |
|-----------------------------|-------------------------------------------------------------------------------------------------------------------------------------|
| `imprimeur-mode`            | Opens the page of this buffer, or closes it.                                                                                        |
| `imprimeur-browse`          | Opens the desktop window again after you closed it.                                                                                 |
| `imprimeur-copy-url`        | Copies the page's address, to open it in another browser. Anyone on this machine who has it can read the page while the mode is on. |
| `imprimeur-refresh-palette` | Gives the page the current colours and fonts, after a change that no switch of theme made, such as a new `imprimeur-appearance`.    |
| `imprimeur-stop-all`        | Closes every page; so do killing the buffer and leaving Emacs.                                                                      |

Links in the page go through Emacs: web addresses open with `browse-url`,
and documents or media under the document's root with
`find-file-other-window`; for any other link, Emacs says that it leads
nowhere. If pandoc fails, the page keeps the last good version and shows
pandoc's message above it.

**Colours.** The page takes its colours and fonts from the faces of the
Emacs frame that shows the buffer, and its own light and dark colours only
where a face gives none. A switch of theme, by hand or by a package such as
auto-dark, recolours the page at once, and nothing reloads.

**Diagrams.** A Mermaid block, `#+begin_src mermaid` or a fence named
`mermaid`, is drawn in those colours when the page has a Mermaid script: the
copy that mermaid-cli installs beside its program `mmdc`, or the file that
`imprimeur-mermaid-script` names. Without one, the block stays as code. A
source that does not parse keeps its last drawing, with the message beneath.

**Videos.** A video plays and seeks, and keeps playing while you type
elsewhere. One that the page cannot play gets a link, "Open externally":
Emacs visits the file, and a media package such as ready-player can play it.

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
  <img alt="How imprimeur shows a buffer: Emacs sends the unsaved text to pandoc, serves the result on 127.0.0.1 under a token, and a Chromium page fetches, sanitises and shows it; links come back to Emacs." src="docs/images/architecture.svg">
</picture>

A moment after you stop typing, Emacs sends the whole buffer to pandoc,
which returns HTML. A small HTTP server inside Emacs, on 127.0.0.1 only,
tells the page that a new version exists; the page fetches it, sanitises
it and replaces only the blocks that changed. [How imprimeur
works](docs/how-it-works.md) follows one edit to the page, explains the
scheduling, the colours, the diagrams and the videos, and lists every
defence against a hostile document.

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
  lead;
- remote images load only for trusted documents;
- the server listens on 127.0.0.1 only, under a random token per page,
  and checks the `Host` of each request and the `Origin` of each message
  from the page, against other web pages and other users of the machine;
- the browser's desktop window has a profile of its own, deleted
  afterwards, and the token appears in no process's command line.

The tests check each of these against hostile documents and diagrams in a
headless Chromium.

## Status

Pre-release, built one plan at a time. Done: the page in Chromium's desktop
window, live, safe, in the core of the Minitel skin; the Emacs theme's
colours, which follow auto-dark without a reload; Mermaid diagrams; videos
that seek; an update that replaces only the blocks you touched. Next: the
page inside Emacs, in an Emacs window beside the one showing the source
buffer, within one Emacs frame; scroll sync both ways; then typeset skins
(French books of the 17th, 18th and 19th centuries, a business briefing, a
vertical Chinese page, a handwritten notebook).

**sommaire** works in Org and Markdown buffers, pre-release too: see
[below](#sommaire). The page's own minitocs, under the same rules, come
later.

## sommaire

sommaire shows where you are in a long Org or Markdown document and takes
you anywhere else in it, without changing the file. It needs Emacs 29.1 or
later and no other package, imprimeur included. Install it as below, then
type `M-x sommaire-mode` in the buffer, or turn it on with a hook.

![An Org buffer in Emacs. The header line reads "Composition › § Sizes of type ▾3 › Long primer". The heading Composition carries the button "▸ 3", and an open inline minitoc below it lists its entries, with the entries of Sizes of type under that one.](docs/images/sommaire-buffer.png)

### What you see

**The header line** names the section around point, after whatever it
already holds, such as the path that breadcrumb shows. A moment after point
stops moving, it reads like `§ Sizes of type ▾3 › Long primer`: the section,
the number of its entries and the entry that holds point. With nothing else
in the header line, the segment shows the heading path too, as in the
picture, so that the row stays where it is as long as the mode is on.

**`M-g m`** asks for a heading and goes there, leaving the mark behind. It
offers the direct children of the section around point, so the list stays
short. `C-u M-g m` offers the whole document at all depths, and a numeric
prefix, as in `M-2 M-g m`, that many levels, this once. The mode binds this
key in its own map, and no other.

**The panel.** A click on the segment, or `M-x sommaire-panel`, shows that
list in a narrow side Emacs window, and another closes it. It is off until
you ask for it, leaves the selected Emacs window selected, follows point and
marks the entry that holds point. If you go there, or click:

| Key in the panel | What it does                                                     |
|------------------|------------------------------------------------------------------|
| `RET`, a click   | Goes to the heading of that entry.                               |
| `+`, `-`         | Lists one level more, or one fewer.                              |
| `r`              | Lists from the document, or from the section around point again. |
| `q`              | Closes the panel.                                                |

What these keys change holds for that buffer alone, so that
`clone-indirect-buffer` gives each Emacs window a list of its own.

**A button and an inline minitoc.** Some headings end with a button such as
`▸ 3`, which counts their entries. A click on it opens the heading's minitoc
under its metadata, and another closes it, as does
`M-x sommaire-toggle-inline` for the nearest such heading around point. A
click on an entry goes to its heading. Each Emacs window shows at most one:
opening another closes the first.

A few rules keep all this quiet:

- A section is a heading with at least two children, at most two levels below
  the document, or the document itself when it has two. So a chain of headings
  with one child each has no section, and no minitoc.
- In a stack of headings with no text between them, only the first one worth
  a minitoc has a button, and the next one's entries join its list, so that
  lists never stack. In the picture, Composition's list holds the entries of
  Sizes of type, which has no button.
- A heading with a table of its own, `#+TOC: headlines N local` or an
  org-make-toc drawer, has no button.
- COMMENT headings, headings tagged `:noexport:` or with another tag of
  `org-export-exclude-tags`, `UNNUMBERED: notoc` and toc-org containers are
  not listed, nor is what lies under them. ARCHIVE headings are listed,
  dimmed, and never expanded.
- In Markdown, a lone first H1 is the document's title. What looks like a
  heading in code, front matter, an HTML block, a block quote, a list item
  or a footnote definition is not one.
- Under narrowing, a part that starts at a heading and holds nothing but
  deeper ones takes that heading for the document.
- An entry reads like its heading without the TODO keyword, priority, tags
  and statistics cookies, or takes the heading's `ALT_TITLE`.

[The rules](docs/minitoc-rules.md) say all this in full, and [how it
works](docs/how-it-works.md#sommaire) explains the design.

**Folding** stays Org's and yours: sommaire never folds. A folded heading
hides its minitoc, and refuses to open one. Org folds by itself; in Markdown,
this one line gives you Emacs's own:

```elisp
(add-hook 'markdown-mode-hook #'outline-minor-mode)
```

**Limits.** A title shows as its source has it, so a link or emphasis in a
heading keeps its marks. A buffer of more than 1,000,000 accessible
characters is not read: sommaire says so once, and again when you ask it for
a heading, and lists none until you narrow to less.

### Install

Install it with [straight.el](https://github.com/radian-software/straight.el)
and `use-package`. The two packages share one clone: each recipe names the same
`:local-repo` and its own `:files`. The recipe of imprimeur above gets that
clone by default, as straight.el names it after the repository.

```elisp
(use-package sommaire
  :straight (sommaire :type git :host github :repo "piotr-yuxuan/imprimeur"
                      ;; The clone that the two packages share, and this
                      ;; package's Lisp files.
                      :local-repo "imprimeur"
                      :files ("sommaire/*.el")))
```

To work from a clone of your own, write its path as `:local-repo` in the
recipe of each package you use.

### Configure

Nothing is required. Loading the package adds no timer, hook or key. An
example with every option at its default value:

```elisp
(use-package sommaire
  :straight (sommaire :type git :host github :repo "piotr-yuxuan/imprimeur"
                      :local-repo "imprimeur"
                      :files ("sommaire/*.el"))
  ;; On in every Org and Markdown buffer.  gfm-mode derives from markdown-mode
  ;; and runs its hook; markdown-ts-mode has a hook of its own.
  :hook ((org-mode markdown-mode) . sommaire-mode)
  ;; Keys of your own, for the two commands that have none.
  :bind (:map sommaire-mode-map
              ("C-c m" . sommaire-panel)
              ("C-c M" . sommaire-toggle-inline))
  :custom
  ;; Show the segment in the header line; nil leaves the header line alone.
  ;; The mode reads this when it starts.
  (sommaire-header-line t)
  ;; Give a button to the headings that have an inline minitoc; nil gives
  ;; none, and `sommaire-toggle-inline' still opens one.  The mode reads this
  ;; when it starts.
  (sommaire-heading-buttons t)
  ;; Follow point after this many seconds of idle time.  The first buffer to
  ;; turn the mode on reads this.
  (sommaire-idle-delay 0.4)
  ;; What `M-g m' and the panel list: (ROOT . DEPTH).  ROOT is `section', the
  ;; section around point, which follows it, or `document'.  DEPTH is how many
  ;; levels below ROOT: a positive integer, or `all'.  So (section . 1) is the
  ;; section's direct children, and (document . 2) the document's first two
  ;; levels.
  (sommaire-scope '(section . 1)))
```

The faces are `sommaire-current`, for the entry that holds point,
`sommaire-archived`, `sommaire-button` and `sommaire-inline`.

### Without imprimeur

Neither package needs the other: neither lists it in `Package-Requires`,
loads it or uses its code, so you can install either alone, and sommaire
runs with neither pandoc nor Chromium on the machine. They share this
repository for now. The page's minitocs, when they come, will follow the same
written rules, [`docs/minitoc-rules.md`](docs/minitoc-rules.md), and no code
will cross.

## Development

The checks run in `nix develop`, which provides every tool and the
packages' minimum Emacs versions:

```sh
nix develop --command make check
nix develop --command make test-min
```

`nix develop --accept-flake-config` fetches Emacs 29.1 and 30.1 from the
binary cache of nix-emacs-ci instead of building them. `AGENTS.md` gives
the workflow and the rules.

## Licence

imprimeur and sommaire are licensed under the European Union Public
Licence 1.2 (`LICENSE`) or, at your option, the GNU General Public License,
version 3 or any later version (`COPYING`): `EUPL-1.2 OR GPL-3.0-or-later`.

imprimeur ships a copy of DOMPurify, under the Apache License 2.0 or the
Mozilla Public License 2.0: see `imprimeur/assets/vendor/dompurify/`.

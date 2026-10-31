# imprimeur

[![GitHub licence](https://img.shields.io/github/license/piotr-yuxuan/imprimeur)](#licence)
[![GitHub issues](https://img.shields.io/github/issues/piotr-yuxuan/imprimeur)](https://github.com/piotr-yuxuan/imprimeur/issues)

![A cheerful letterpress turns a plain-text sheet with Org and Markdown marks into a typeset page with a red drop cap.](docs/social-media-preview.png)

imprimeur shows the Org or Markdown buffer you are editing as a typeset
page, in a browser window beside Emacs. The page follows every change
within a second, saved or not, and shows your pictures, tables, code and
maths. A document can neither run code in it nor make it fetch anything.
Install it with straight.el, then type `M-x imprimeur-mode` in the buffer.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/emacs-and-page-dark.png">
  <img alt="An Org buffer in Emacs on the left; on the right, the same document typeset in a Chromium window." src="docs/images/emacs-and-page.png">
</picture>

It is pre-release: the page opens in a Chromium window and has its own
light and dark colours. The view inside Emacs, the Emacs theme's colours,
Mermaid diagrams, scroll sync and more skins arrive next (see
[Status](#status)).

## Install

You need Emacs 30.1 or later, [pandoc](https://pandoc.org/) 3 (tested with
3.7.0.2) and Chromium, or a browser that takes Chromium's options. For
Markdown, `markdown-mode`.

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
you turn the mode on. An example with every option, at its default value
unless noted:

```elisp
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       :files ("imprimeur/*.el" "imprimeur/assets"))
  ;; A key of your own: `imprimeur-mode' toggles the page of this buffer.
  :bind ("C-c i" . imprimeur-mode)
  :custom
  ;; The browser that shows the page, in a window and a profile of its own.
  ;; Browsers built on Chromium take the same options, such as
  ;; "google-chrome-stable" or "brave"; only Chromium is tested.
  (imprimeur-browser-program "chromium")
  ;; pandoc 3.  A wrapper that adds options of its own is fine: imprimeur
  ;; passes every option it needs.
  (imprimeur-pandoc-program "pandoc")
  ;; Render 0.3 s after you stop typing, and every 2 s at least while you
  ;; type without a pause.
  (imprimeur-render-delay 0.3)
  (imprimeur-render-max-delay 2.0)
  ;; Load remote images (badges, pictures on the web) only for documents
  ;; that `trusted-content' accepts; nil never, t always.  Elsewhere each
  ;; one is a link that names its host, and nothing is fetched.
  (imprimeur-remote-images 'trusted)
  :config
  ;; Markdown files without markdown-mode: choose the reader by file name.
  ;; Each entry is a major mode or a file-name pattern, and a pandoc reader.
  (add-to-list 'imprimeur-reader-alist '("\\.md\\'" . "gfm+sourcepos") t))

;; Documents you trust, such as your own notes, may load remote images and
;; include other files with #+INCLUDE: pandoc then runs without its sandbox.
;; This is Emacs's own option (Emacs 30), shared with other packages.
(setq trusted-content '("~/notes/"))
```

## Use

In an Org or Markdown buffer, `M-x imprimeur-mode` opens the page in a
Chromium app window. Then type: the page shows the buffer's text a moment
after each change. Pictures and videos under the document's directory, or
under its git repository, show in the page.

| Command | What it does |
|---|---|
| `imprimeur-mode` | Opens the page of this buffer, or closes it. |
| `imprimeur-browse` | Opens the window again after you closed it. |
| `imprimeur-copy-url` | Copies the page's address, to open it in another browser. Anyone on this machine who has it can read the page while the mode is on. |
| `imprimeur-stop-all` | Closes every page; so do killing the buffer and leaving Emacs. |

Links in the page go through Emacs: web addresses open with `browse-url`,
and documents or media under the document's root with
`find-file-other-window`. If pandoc fails, the page keeps the last good
version and shows pandoc's message above it.

The formats are those of `imprimeur-reader-alist`: Org, Markdown (GitHub's
dialect), reStructuredText, MediaWiki, Textile, Creole, POD, Jupyter
notebooks, CSV and TSV.

![A Markdown document typeset by imprimeur, with a table, code, a task list and a picture.](docs/images/markdown-page.png)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/architecture-dark.svg">
  <img alt="How imprimeur shows a buffer: Emacs sends the unsaved text to pandoc, serves the result on 127.0.0.1 under a token, and a Chromium page fetches, sanitises and shows it; links come back to Emacs." src="docs/images/architecture.svg">
</picture>

A moment after you stop typing, Emacs sends the whole buffer to pandoc,
which returns HTML. A small HTTP server inside Emacs, on 127.0.0.1 only,
tells the page that a new version exists; the page fetches it, sanitises
it and replaces its contents. [How imprimeur works](docs/how-it-works.md)
follows one edit to the page, explains the scheduling, and lists every
defence against a hostile document.

## Security

A document you open may come from anyone. imprimeur treats it as untrusted
unless Emacs's `trusted-content` says otherwise:

- pandoc runs with `--sandbox`, so a document cannot include other files;
- the page runs no script from the document: each version is sanitised
  with DOMPurify, and every response carries a strict Content Security
  Policy;
- the page navigates nowhere by itself: Emacs decides where each link may
  lead;
- remote images load only for trusted documents;
- the server listens on 127.0.0.1 only, under a random token per page, and
  checks the `Host` and `Origin` of each request, against other web pages
  and other users of the machine;
- the browser window has a profile of its own, deleted afterwards, and the
  token appears in no process's command line.

The tests check each of these against hostile documents in a headless
Chromium.

## Status

Pre-release, built one plan at a time. Done: the page in a Chromium
window, live, safe, in the core of the Minitel skin. Next: the Emacs
theme's colours with auto-dark, Mermaid diagrams, videos that seek, an
update that keeps your place, the page inside Emacs beside the source,
scroll sync both ways, then typeset skins (French books of the 17th, 18th
and 19th centuries, a business briefing, a vertical Chinese page, a
handwritten notebook).

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

`nix develop --accept-flake-config` fetches Emacs 29.1 and 30.1 from the
binary cache of nix-emacs-ci instead of building them. `AGENTS.md` gives
the workflow and the rules.

## Licence

imprimeur and sommaire are licensed under the European Union Public
Licence 1.2 (`LICENSE`) or, at your option, the GNU General Public License,
version 3 or any later version (`COPYING`): `EUPL-1.2 OR GPL-3.0-or-later`.

imprimeur ships a copy of DOMPurify, under the Apache License 2.0 or the
Mozilla Public License 2.0: see `imprimeur/assets/vendor/dompurify/`.

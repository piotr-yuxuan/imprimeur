# imprimeur and sommaire

Two Emacs packages, developed in one repository:

- **imprimeur** renders the current buffer (Org, Markdown, and the other
  formats GitHub renders that pandoc reads) into a typeset page, shown
  beside the source inside Emacs or in a Chromium window. The page follows
  the unsaved text, the scrolling and the colours of the Emacs theme, and
  comes in several skins.
- **sommaire** shows mini tables of contents in Org and Markdown buffers:
  one for the section around point, and one under a heading on request,
  never stacked. It works without imprimeur.

## Status

Pre-release. imprimeur opens the page of an Org or Markdown buffer in a
Chromium window that follows the unsaved text, in the core of its Minitel
skin, with colours of its own. The view inside Emacs, the theme's colours,
Mermaid diagrams, scroll sync and sommaire arrive with the next plans.

## Using imprimeur

In an Org or Markdown buffer, or another format of `imprimeur-reader-alist`,
`M-x imprimeur-mode` opens the page in a Chromium app window. The page
shows the buffer's text a moment after each change, saved or not. Links in
the page go through Emacs: web addresses to `browse-url`, documents and
media under the document's root to `find-file-other-window`.

- `imprimeur-browse` opens the window again once closed.
- `imprimeur-copy-url` copies the page's address. Anyone who has it can
  read the page while the session lasts.
- `imprimeur-stop-all` ends every session; so does turning the mode off,
  killing the buffer or leaving Emacs.

The options are in the customisation group `imprimeur`: the pandoc and
browser programs, the readers, the delays before a render, and whether
remote images load.

## Requirements

- sommaire: Emacs 29.1 or later.
- imprimeur: Emacs 30.1 or later; pandoc 3 (tested with 3.7.0.2); Chromium
  for the browser view; Emacs built with xwidgets for the view inside Emacs;
  mermaid-cli for diagrams.

## Installing from a clone

With straight.el, each package takes its own files from the repository:

```elisp
(use-package sommaire
  :straight (sommaire :type git :host github :repo "piotr-yuxuan/imprimeur"
                      :files ("sommaire/*.el")))

(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       :files ("imprimeur/*.el" "imprimeur/assets")))
```

Add `:local-repo "<clone>"` to both recipes to use an existing clone.

With package-vc, in Emacs 30 or later:

```elisp
(package-vc-install '(sommaire :url "https://github.com/piotr-yuxuan/imprimeur"
                               :lisp-dir "sommaire"))
(package-vc-install '(imprimeur :url "https://github.com/piotr-yuxuan/imprimeur"
                                :lisp-dir "imprimeur"))
```

## Security

imprimeur treats every document as untrusted unless Emacs's
`trusted-content` says otherwise:

- pandoc runs with `--sandbox`, so a document cannot include other files;
- the page is served by a server listening on 127.0.0.1 only, under a
  random 128-bit token per session, which checks the `Host` and `Origin`
  headers and limits the size, number and duration of requests;
- the page runs no script from the document: each revision is sanitised
  with DOMPurify, and every response carries a strict Content Security
  Policy;
- the page navigates nowhere by itself: Emacs decides where each link
  followed may lead;
- remote images load only for trusted documents; otherwise each is a link
  naming its host, and nothing is fetched;
- the browser window has a profile of its own, readable by you only and
  deleted afterwards, and starts on a file inside it, so that the token
  appears in no process's command line.

The tests check each of these against hostile documents.

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

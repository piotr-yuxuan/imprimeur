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

Pre-release. This version holds the repository's checks and the two
packages' headers; the features arrive one plan at a time.

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

imprimeur's design treats every document as untrusted unless Emacs's
`trusted-content` says otherwise: pandoc runs sandboxed, the page is
sanitised and served with a strict Content Security Policy by a loopback
server that requires a per-session token, and remote images load only for
trusted documents. The plans that build the renderer test each of these.

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

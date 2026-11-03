# imprimeur

English · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

[![CI](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/ci.yml/badge.svg)](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/ci.yml)
[![CD](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/cd.yml/badge.svg)](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/cd.yml)

<img alt="A woodcut of a printing shop: two pressmen at a wooden press, with stacks of sheets before them and two compositors at the back." src="docs/images/printer-1568.png"><br>

imprimeur shows the Org or Markdown buffer you are editing as a typeset page, in an Emacs
window beside it, and keeps the two in step. The page follows every change a moment after you
stop typing, saved or not. No document runs code in it, and an untrusted one makes it fetch
nothing from the network. It is pre-release.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/emacs-view-dark.png">
  <img alt="One Emacs frame holding two Emacs windows: an Org buffer on the left and, on the right, the same text typeset in the skin Minitel, in the colours of the Emacs theme." src="docs/images/emacs-view.png">
</picture>

## Install

You need Emacs 31.1, [pandoc](https://pandoc.org/) 3, and something to show the page in: an
Emacs built with xwidgets (`pkgs.emacs-pgtk` under Nix), or else Chromium, for a desktop window.
With [straight.el](https://github.com/radian-software/straight.el) and `use-package`:

```elisp
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       :files ("imprimeur/*.el" "imprimeur/assets")))
```

Then type `M-x imprimeur-mode` in a buffer. [Your first preview](docs/tutorials/first-preview.md)
walks through it from a clone, with nothing installed. For Markdown, add `markdown-mode`. For
Mermaid diagrams, [mermaid-cli](https://github.com/mermaid-js/mermaid-cli). For videos in an
Emacs window, GStreamer's plugins in that Emacs's environment.

That recipe follows the latest of `main`. To pin a
[release](https://github.com/piotr-yuxuan/imprimeur/releases) instead, Emacs's own `:vc` takes its tag:

```elisp
(use-package imprimeur
  :vc (:url "https://github.com/piotr-yuxuan/imprimeur" :rev "0.0.0" :lisp-dir "imprimeur"))
```

### Try xwidgets first

Xwidgets are experimental in Emacs, and a crash takes your unsaved text with it. So try them in
a separate Emacs before you rely on them, from a clone:

```sh
nix develop --command make smoke-xwidget
```

It opens real pages in a desktop window of its own for about a minute, and prints `PASS` or
`FAIL` for each thing it checks. If it fails, or you would rather not,
`(setq imprimeur-target 'browser)` keeps xwidgets out of it.

## What is in this repository

Each package installs alone, by the recipes under [Configuration](#configuration).

| Package                   | What it is for                                                                                          | What it needs                                             |
|---------------------------|---------------------------------------------------------------------------------------------------------|-----------------------------------------------------------|
| `imprimeur`               | The typeset page of a buffer                                                                            | Emacs 31.1, pandoc 3, and xwidgets or Chromium            |
| `sommaire`                | Mini tables of contents in the buffer itself: where you are in a long document, and a way anywhere else | Emacs 31.1 and nothing else, imprimeur included           |
| `imprimeur-skin-minitel`  | A skin: a tribute to the terminal, in your theme's colours. A page starts in it once installed          | `imprimeur`, and no fonts                                 |
| `imprimeur-skin-xix`      | A skin: a French book of the XIX<sup>th</sup> century                                                   | `imprimeur`, and its fonts                                |
| `imprimeur-skin-xviii`    | A skin: a French book of the XVIII<sup>th</sup> century                                                 | `imprimeur`, and its fonts                                |
| `imprimeur-skin-xvii`     | A skin: a French book of the XVII<sup>th</sup> century                                                  | `imprimeur`, and its fonts                                |
| `imprimeur-skin-briefing` | A skin: a modern business memo                                                                          | `imprimeur`, and its fonts                                |
| `imprimeur-skin-ecrivain` | A skin: handwriting on paper                                                                            | `imprimeur`, and its fonts, which it needs for its ruling |
| `imprimeur-skin-tianlu`   | A skin: a Song block-print page, in vertical Chinese                                                    | `imprimeur`, and about 580 MB of fonts                    |

Installing a skin is installing code: its stylesheet runs in the page, its filters in pandoc.

## Gallery

Real captures, from `scripts/make-gallery`. [The examples](examples/README.md) hold each document.

| Skin                                                   | Light                                                                                                                         | Dark                                                                                                                              |
|--------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| [Minitel](imprimeur-skin-minitel/README.md)            | <img alt="Wells in Minitel, light." src="docs/images/gallery/minitel.png" width="340">                                        | <img alt="Wells in Minitel, dark." src="docs/images/gallery/minitel-dark.png" width="340">                                        |
| [XIX](imprimeur-skin-xix/README.md)                    | <img alt="Tocqueville in XIX, on paper." src="docs/images/gallery/xix.png" width="340">                                       | <img alt="Tocqueville in XIX, by candlelight." src="docs/images/gallery/xix-dark.png" width="340">                                |
| [XVIII](imprimeur-skin-xviii/README.md)                | <img alt="Voltaire in XVIII, on paper." src="docs/images/gallery/xviii.png" width="340">                                      | <img alt="Voltaire in XVIII, by candlelight." src="docs/images/gallery/xviii-dark.png" width="340">                               |
| [XVII](imprimeur-skin-xvii/README.md)                  | <img alt="Descartes in XVII, on paper." src="docs/images/gallery/xvii.png" width="340">                                       | <img alt="Descartes in XVII, by candlelight." src="docs/images/gallery/xvii-dark.png" width="340">                                |
| [Briefing](imprimeur-skin-briefing/README.md)          | <img alt="Turgot's letter in Briefing, light." src="docs/images/gallery/briefing.png" width="340">                            | <img alt="Turgot's letter in Briefing, dark." src="docs/images/gallery/briefing-dark.png" width="340">                            |
| [Écrivain](imprimeur-skin-ecrivain/README.md)          | <img alt="A notebook in Écrivain, on Seyès paper." src="docs/images/gallery/ecrivain.png" width="340">                        | <img alt="A notebook in Écrivain, on dark paper." src="docs/images/gallery/ecrivain-dark.png" width="340">                        |
| [Tianlu](imprimeur-skin-tianlu/README.md), traditional | <img alt="An essay in traditional characters in Tianlu, light." src="docs/images/gallery/tianlu-traditional.png" width="340"> | <img alt="An essay in traditional characters in Tianlu, dark." src="docs/images/gallery/tianlu-traditional-dark.png" width="340"> |
| [Tianlu](imprimeur-skin-tianlu/README.md), simplified  | <img alt="An essay in simplified characters in Tianlu, light." src="docs/images/gallery/tianlu-simplified.png" width="340">   | <img alt="An essay in simplified characters in Tianlu, dark." src="docs/images/gallery/tianlu-simplified-dark.png" width="340">   |

## Configuration

A complete configuration, in the order to load it. Every value is the default, so keep only what
you change. Deleting an entry follows the default if a release changes it, where a value kept
here stays.

```elisp
;; imprimeur first: a skin's recipe needs it.
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       ;; This package's Lisp files, and the page's assets beside them.
                       :files ("imprimeur/*.el" "imprimeur/assets"))
  ;; A key of your own.  The mode adds M-g v, M-g s and M-g o where it is on, and no other.
  :bind ("C-c i" . imprimeur-mode)
  :custom
  ;; Where the page opens: `auto', in an Emacs window when the selected Emacs frame is
  ;; graphic and this Emacs has xwidgets, otherwise in a desktop window of the browser;
  ;; `xwidget', in an Emacs window, refusing where that cannot run; `browser', in a
  ;; desktop window of the browser.
  (imprimeur-target 'auto)
  ;; How `display-buffer' shows the page in an Emacs window: on the right of the Emacs
  ;; frame, half its width, and the source stays selected.  '((display-buffer-same-window))
  ;; takes the source's Emacs window instead, and quitting brings the source back.
  (imprimeur-display-buffer-action
   '((display-buffer-reuse-window display-buffer-in-direction)
     (direction . right)
     (window . root)
     (window-width . 0.5)
     (dedicated . t)
     (reusable-frames . visible)))
  ;; Which way the page and the source follow each other's scrolling: `both'; `to-preview',
  ;; the page follows the source alone; nil, neither, until `imprimeur-follow-mode' by hand.
  (imprimeur-scroll-sync 'both)
  ;; The browser of a desktop window: Chromium, or one that takes its options.
  (imprimeur-browser-program "chromium")
  ;; pandoc 3, or a wrapper whose output stays a bare fragment.
  (imprimeur-pandoc-program "pandoc")
  ;; Which pandoc reader a buffer takes: a major mode, or a pattern on the file name.
  ;; Markdown without markdown-mode: add ("\\.md\\'" . "gfm+sourcepos").
  (imprimeur-reader-alist
   '((org-mode . "org")
     (markdown-mode . "gfm+sourcepos")
     (rst-mode . "rst")
     (mediawiki-mode . "mediawiki")
     (textile-mode . "textile")
     ("\\.creole\\'" . "creole")
     ("\\.pod\\'" . "pod")
     ("\\.ipynb\\'" . "ipynb")
     ("\\.csv\\'" . "csv")
     ("\\.tsv\\'" . "tsv")))
  ;; Seconds of quiet after a change before a render.
  (imprimeur-render-delay 0.3)
  ;; Seconds after which a render happens even while you go on typing.
  (imprimeur-render-max-delay 2.0)
  ;; Seconds after which a render is abandoned, and its error shown.
  (imprimeur-render-timeout 20)
  ;; Whether remote images load: `trusted', for documents that `trusted-content' accepts;
  ;; nil, never; t, always.  Elsewhere each one is a link that names its host.
  (imprimeur-remote-images 'trusted)
  ;; Whether the page is light or dark: `auto', as the Emacs frame; `light'; `dark'.
  (imprimeur-appearance 'auto)
  ;; The script that draws Mermaid diagrams: nil, the copy beside the program mmdc; or a
  ;; file name.  Without one a diagram stays as code, and nothing is fetched.
  (imprimeur-mermaid-script nil)
  ;; The skin of a new page: `auto', Minitel if installed and otherwise the plain page;
  ;; `base', the plain page; or a skin's name, such as `xix'.
  (imprimeur-skin 'auto)
  ;; Each skin's options, to start from; M-g o tries one, and says what to write here.
  (imprimeur-skin-options
   '((minitel
      ;; The colours: "emacs", your theme's; "videotex"; "greys".
      (palette . "emacs")
      ;; The columns: "80"; "40", in larger letters.
      (columns . "80")
      ;; The bar of keys: "fixed"; "end", at the document's end; "off".
      (keys . "fixed"))
     (xix
      ;; The text: "junicode", "bodoni-moda", "bodoni-moda-optical", "playfair",
      ;; "playfair-display", "old-standard", "theano", "libertinus", "eb-garamond".
      (text-face . "junicode")
      ;; "none", "common", "discretionary", "historical".
      (ligatures . "discretionary")
      ;; The column in rem: "24", "24-5" and so on by half a rem, to "40".
      (measure . "30"))
     (xviii
      ;; "baskervville", "junicode".
      (face . "baskervville")
      ;; Long s, under Junicode only: "off", "on".
      (long-s . "off")
      ;; "fleurons", "rinceau", "entrelacs", "perles", "filet".
      (bands . "fleurons"))
     (xvii
      ;; "im-fell", "eb-garamond", "garamond-libre".
      (face . "im-fell")
      ;; Long s: "on", "off".
      (long-s . "on")
      ;; Historical ligatures: "on", "off".
      (ligatures . "on")
      ;; Notes in the margin: "on"; "off", at the end of the section.
      (manchettes . "on"))
     (briefing
      ;; "blue", "teal", "aubergine", "graphite".
      (accent . "blue")
      ;; "compact", "regular", "airy".
      (density . "compact")
      ;; The bottom line, the titles and the callouts alone: "off", "on".
      (skim . "off"))
     (ecrivain
      ;; The hand and its paper: "cahier", "carnet", "notes", "ardoise".
      (variant . "cahier")
      ;; In Cahier: "moderne", "trad".
      (hand . "moderne")
      ;; "variante", the variant's own; "bleu-noir", "bleu", "noir", "violet", "sepia".
      (ink . "variante")
      ;; "pageless", one long sheet; "pages", the leaves of a notebook.
      (sheet . "pageless"))
     (tianlu
      ;; The grid and its dress: "song", "juzhen", "siku".
      (preset . "song")
      ;; "auto", as the preset says; "moe", "kai", "ming", "fang".
      (face . "auto")))))

;; A skin is one recipe, and imprimeur registers it once it loads.  Keep those you want.
(use-package imprimeur-skin-minitel
  :straight (imprimeur-skin-minitel :type git :host github :repo "piotr-yuxuan/imprimeur"
                                    :local-repo "imprimeur"
                                    :files ("imprimeur-skin-minitel/*.el" "imprimeur-skin-minitel/assets"))
  :defer t)

(use-package imprimeur-skin-xix
  :straight (imprimeur-skin-xix :type git :host github :repo "piotr-yuxuan/imprimeur"
                                :local-repo "imprimeur"
                                :files ("imprimeur-skin-xix/*.el" "imprimeur-skin-xix/assets"))
  :defer t)

(use-package imprimeur-skin-xviii
  :straight (imprimeur-skin-xviii :type git :host github :repo "piotr-yuxuan/imprimeur"
                                  :local-repo "imprimeur"
                                  :files ("imprimeur-skin-xviii/*.el" "imprimeur-skin-xviii/assets"))
  :defer t)

(use-package imprimeur-skin-xvii
  :straight (imprimeur-skin-xvii :type git :host github :repo "piotr-yuxuan/imprimeur"
                                 :local-repo "imprimeur"
                                 :files ("imprimeur-skin-xvii/*.el" "imprimeur-skin-xvii/assets"))
  :defer t)

(use-package imprimeur-skin-briefing
  :straight (imprimeur-skin-briefing :type git :host github :repo "piotr-yuxuan/imprimeur"
                                     :local-repo "imprimeur"
                                     :files ("imprimeur-skin-briefing/*.el" "imprimeur-skin-briefing/assets"))
  :defer t)

(use-package imprimeur-skin-ecrivain
  :straight (imprimeur-skin-ecrivain :type git :host github :repo "piotr-yuxuan/imprimeur"
                                     :local-repo "imprimeur"
                                     :files ("imprimeur-skin-ecrivain/*.el" "imprimeur-skin-ecrivain/assets"))
  :defer t)

(use-package imprimeur-skin-tianlu
  :straight (imprimeur-skin-tianlu :type git :host github :repo "piotr-yuxuan/imprimeur"
                                   :local-repo "imprimeur"
                                   :files ("imprimeur-skin-tianlu/*.el" "imprimeur-skin-tianlu/assets"))
  :defer t)

;; sommaire needs none of the above.
(use-package sommaire
  :straight (sommaire :type git :host github :repo "piotr-yuxuan/imprimeur"
                      :local-repo "imprimeur"
                      :files ("sommaire/*.el"))
  ;; On in every Org and Markdown buffer.
  :hook ((org-mode markdown-mode) . sommaire-mode)
  ;; Keys of your own, for the two commands that have none.
  :bind (:map sommaire-mode-map
              ("C-c m" . sommaire-panel)
              ("C-c M" . sommaire-toggle-inline))
  :custom
  ;; Show the segment in the header line: t; nil leaves the header line alone.
  (sommaire-header-line t)
  ;; A button on the headings that have an inline minitoc: t; nil, none.
  (sommaire-heading-buttons t)
  ;; Follow point after this many seconds of idle time.
  (sommaire-idle-delay 0.4)
  ;; What M-g m and the panel list: (ROOT . DEPTH).  ROOT is `section', around point, or
  ;; `document'.  DEPTH is how many levels below it: a positive integer, or `all'.
  (sommaire-scope '(section . 1)))

;; Documents you trust may load remote images and include other files, with pandoc outside
;; its sandbox.  Emacs's own option, which other packages read: list only what you wrote.
;; (setq trusted-content '("~/notes/"))
```

## Keys

| Key                                                    | Where                   | What it does                                                        |
|--------------------------------------------------------|-------------------------|---------------------------------------------------------------------|
| `M-g v`                                                | The source              | Brings point's block to the top of the page                         |
| `M-g v`                                                | The page's Emacs window | Goes back to the source, at the page's top line                     |
| `M-g s`                                                | Both                    | Chooses a skin, in a menu                                           |
| `M-g o`                                                | Both                    | Sets an option of this page's skin, and says the line that keeps it |
| `SPC`, `DEL`, `C-v`, `M-v`, `C-n`, `C-p`, `M-<`, `M->` | The page's Emacs window | Scroll the page                                                     |
| `q`                                                    | The page's Emacs window | Hides the page, and leaves it live                                  |
| `t`                                                    | The page                | Opens the popover of the pill, its table of contents                |
| A double-click                                         | The page                | Puts point on that line of the source                               |
| `M-g m`                                                | A sommaire buffer       | Goes to a heading of the section around point                       |

[Commands and keys](docs/reference/commands-and-keys.md) lists all of them.

## Fonts

A skin names fonts and ships none; without them, the page falls back on what you have. Minitel
asks for none. With Nix, take the repository as a plain flake input,
`inputs.imprimeur = { url = "github:piotr-yuxuan/imprimeur"; flake = false; };`, and under NixOS:

```nix
fonts.packages = lib.concatMap
  (skin: import "${inputs.imprimeur}/imprimeur-skin-${skin}/fonts.nix" { inherit pkgs; })
  [ "xix" "xviii" "xvii" "briefing" "ecrivain" ];
```

Under Home Manager, the same list goes in `home.packages`, with `fonts.fontconfig.enable = true`.
Tianlu needs a predicate for two faces, whose licence you should read first. Without Nix, install
the families in the table "Fonts" of each skin's README; Écrivain's letters leave the ruling
without its strut. [Install the fonts](docs/how-to/install-the-fonts.md) has every step.

## Documentation

**Tutorial**

- [Your first preview](docs/tutorials/first-preview.md): from a clone to a typeset page.

**How-to guides**

- [Choose and tune a skin](docs/how-to/choose-and-tune-a-skin.md): pick one, set its options, keep them.
- [Write a skin](docs/how-to/write-a-skin.md): a stylesheet, then a filter and a module.
- [Install the fonts](docs/how-to/install-the-fonts.md): under NixOS, Home Manager, or without Nix.
- [Use sommaire](docs/how-to/use-sommaire.md): find your place in a long buffer.
- [Sync and follow](docs/how-to/sync-and-follow.md): move between the source and the page.
- [Troubleshoot by symptom](docs/how-to/troubleshoot.md): what a message means, and what to do.

**Reference**

- [Options](docs/reference/options.md): every option, with its default and choices.
- [Commands and keys](docs/reference/commands-and-keys.md): every command, key and click.
- [What a document may hold](docs/reference/documents.md): formats, media, diagrams, maths.
- [The skin API](docs/reference/skin-api.md): each key of `imprimeur-skin-define`.
- [Minitoc rules](docs/reference/minitoc-rules.md): which document gets which minitocs.
- [The release pipeline](docs/reference/release-pipeline.md): the two workflows, what a release writes, how to raise a version by hand.
- Each skin's README: [Minitel](imprimeur-skin-minitel/README.md), [XIX](imprimeur-skin-xix/README.md), [XVIII](imprimeur-skin-xviii/README.md), [XVII](imprimeur-skin-xvii/README.md), [Briefing](imprimeur-skin-briefing/README.md), [Écrivain](imprimeur-skin-ecrivain/README.md), [Tianlu](imprimeur-skin-tianlu/README.md): its fonts, options and limits.
- [The examples](examples/README.md): which document to open for which skin.

**Explanation**

- [How imprimeur works](docs/explanation/how-it-works.md): the design, one edit to the page, the defences, and sommaire.
- [Why a page rather than the buffer](docs/explanation/why-a-page.md): what a browser's engine gives, and what it costs.
- [Why these skins and faces](docs/explanation/why-these-skins-and-faces.md): packages, manifests, fonts, and what each skin gives up.

## Security

A document you open may come from anyone, so it is untrusted unless Emacs's `trusted-content`
says otherwise. pandoc runs in its sandbox, each version is sanitised with DOMPurify under a strict
Content Security Policy, the server listens on 127.0.0.1 under a random token, and links go through
Emacs. [The defences](docs/explanation/how-it-works.md#the-defences) explain each layer.

## Status

Pre-release. Not yet tried: a real Wayland session, as the Emacs window has run on Xvfb alone; a
wheel, keys and a double-click by a person's hand in the xwidget; whether a video plays there at
all; and a Mac.

## Development

The checks run in `nix develop`, which provides every tool, and the one Emacs that the packages
target: `nix develop --command make check`. `make gallery` remakes the pictures, and
`make smoke-xwidget` tries a real xwidget; both need a display. `AGENTS.md` gives the rules.

## Licence

imprimeur and sommaire and the skins are licensed under the European Union Public Licence 1.2
(`LICENSE`) or, at your option, the GNU General Public License, version 3 or any later version
(`COPYING`): `EUPL-1.2 OR GPL-3.0-or-later`.

imprimeur ships a copy of DOMPurify, under the Apache License 2.0 or the Mozilla Public License
2.0: see `imprimeur/assets/vendor/dompurify/`; and the French and British English hyphenation
patterns of hyph-utf8, under the MIT licence: see `imprimeur/assets/vendor/hyph-utf8/`.

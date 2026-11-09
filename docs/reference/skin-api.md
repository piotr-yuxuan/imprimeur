# The skin API

A skin is a package that calls `imprimeur-skin-define`. It requires `imprimeur-skin`, never
`imprimeur`, and uses no `--` symbol of imprimeur.

## `imprimeur-skin-define`

`(imprimeur-skin-define NAME &rest MANIFEST)` registers the skin and returns NAME. NAME is a
symbol of `[a-z][a-z0-9-]*`, at most 64 characters; `base` and `auto` are the core's.
`imprimeur-skin-parse-manifest` judges the manifest, and refuses a key that it does not know. A
refused manifest gives a warning and registers nothing.

| Key | Value | Required |
|---|---|---|
| `:title` | A string, the name that the echo area and the page's messages show. | Yes |
| `:directory` | A local absolute directory, which every file below is under. | Yes |
| `:stylesheets` | File names of `.css`, at least one, in order. | Yes |
| `:files` | The other files that a stylesheet refers to: `.css`, `.svg`, `.png`, `.webp`. | |
| `:filters` | In order: a `.lua` file under the directory, or a symbol naming a shared filter. | |
| `:smart` | `t` for pandoc's `+smart` where the format has it, or `nil`. | |
| `:notes` | `section` for notes at the end of each section, or `nil`. | |
| `:module` | One `.mjs` file under the directory, or `nil`. | |
| `:keys` | The page's keys that the module takes: one printable ASCII character but a space, in exact case, or `Enter`, `Backspace` or `Escape`. None of `S`, `O`, `t`, `[`, `]`, `u`, `+`, `-`. Needs `:module`. | |
| `:auto` | `t` for the skin that `imprimeur-skin` at `auto` means, the first by name if several say so. | |
| `:menu-key` | One lower-case letter or digit: the skin's key in `imprimeur-skin-menu`, unless another skin holds it. | |
| `:options` | A list of `(ID :label LABEL :choices ((VALUE . LABEL)...) :default VALUE)`. | |

A file name has no space, accent, `..`, `%` or leading dot. An option's ID is of
`[a-z][a-z0-9-]*`, at most 32 characters. It has from 2 to 64 values of `[a-z0-9-]`, at most 32
characters each, and its default is one of them.

A package registers itself once imprimeur loads, by this autoload cookie:

```elisp
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "NAME: %S" (require 'NAME)))
```

## Options on the page

An option away from its default is the attribute `data-NAME-ID` on the root, which only the
sheet reads, and which renders nothing; at its default the root is bare. It reaches no filter.
The session's choice comes first, then `imprimeur-skin-options`, then the manifest.

## Stylesheets

The page declares `@layer base, skin;`. A sheet writes its rules in `@layer skin`, under
`[data-skin="NAME"]`, and its classes start with NAME. It may set these tokens, which
`base.css` reads: `--imp-background`, `--imp-foreground`, `--imp-muted`, `--imp-link`,
`--imp-rule`, `--imp-code-background`, `--imp-error`, `--imp-notice`, `--imp-font-body`,
`--imp-font-code`, `--imp-measure` and `--imp-view-inset`, the length that a sticky bar covers.

It may read the [palette's properties](../explanation/how-it-works.md#the-colours), each left
out where a face gives nothing, and `data-appearance`, `light` or `dark`, on the root, which
sets the colour scheme, and so `light-dark()`. It may read `dir`, `rtl` or `ltr`, on the root,
which the document's language sets: see
[a skin for a right-to-left language](../how-to/write-a-skin.md#a-skin-for-a-right-to-left-language).

A skin names fonts in its stacks and ships none. `fonts.nix` beside it, a function of `{pkgs}`,
returns the list of packages that install them.

## Filters

They run in this order: `imprimeur.lua`, the skin's as its manifest lists them, `finish.lua`.
They do no input or output and load no code, which `scripts/check-public` enforces. Every block
comes in one shape: a block with attributes carries its line, and any other sits in a `Div`
with `wrapper`.

| Shared filter | What it does |
|---|---|
| `common` | A lone first heading becomes the title; a lone picture or film with a description a figure; `Table:` and `Plate:` lines captions; a bare address may break. |
| `french` | Where the language starts with `fr`: narrow spaces, guillemets, superscripts, and a century in `span.imprimeur-siecle`. |
| `hyphenate` | Soft hyphens in prose, in French and English, by Liang's algorithm. |

## A module

The page imports the file at the swap, or at load for the skin that the shell names, and calls
its default export once, as `mount(context)`:

| Field | What it does |
|---|---|
| `signal` | An `AbortSignal`, aborted at a swap, when what the module added must go. |
| `option(id)` | The value in force, its default included. |
| `key(name, handler)` | Takes a key that `:keys` declares. A handler that returns false, or throws, declines it. |
| `hold(flag)` | Stops new revisions from showing, and the page and Emacs from following each other's scrolling. |
| `latest()` | Shows the newest revision, keeping the hold. |
| `goToLine(line)` | Asks Emacs to put point on that line of the source, as a double-click does. |

A module that throws, rejects or fails to load aborts its signal and holds the banner until the
next swap, and the page goes on in the skin. Events on `document` tell a module of
`imprimeur-shown`, after each revision shown, and of `imprimeur-ended`, with the detail `lost`
or `closed`.

The worked steps are in [how to write a skin](../how-to/write-a-skin.md).

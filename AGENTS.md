# Working in this repository

This repository holds Emacs packages: `imprimeur`, which renders the current
buffer into a typeset page shown inside Emacs or in a browser; `sommaire`, which
shows mini tables of contents in Org and Markdown buffers; and `imprimeur-skin-minitel`,
`imprimeur-skin-xix`, `imprimeur-skin-xviii`, `imprimeur-skin-xvii`, `imprimeur-skin-briefing`, `imprimeur-skin-ecrivain` and `imprimeur-skin-tianlu`, skins of imprimeur. They live together for now and can be split later;
`README.md` describes them for users.

## Workflow

Every change follows the skill `workflow:plans`; load it before the first
edit. In this repository: plans are `docs/work/plans/NNN-slug.md`, not
tracked; the check is `make check`, run in `nix develop`, and before a
merge `make commits BASE=main`. The research behind the plans is under
`docs/work/research_notes/`, also not tracked.

## Layout

```
sommaire/                  the package sommaire: shipped .el files only
imprimeur/                 the package imprimeur: shipped .el files and assets/
imprimeur/imprimeur-palette.el  the page's colours and fonts, from the Emacs faces
imprimeur/imprimeur-skin.el  the skins' registry, its parser, and their options
imprimeur/imprimeur-sync.el  the lines of an Org page, and the scroll sync
imprimeur/imprimeur-xwidget.el  the view: the page in an Emacs window, by an xwidget
imprimeur/imprimeur-menu.el  the menu of skins and options, loaded with the first menu
imprimeur/assets/pandoc/   pandoc's data directory, with the Lua filters:
                           imprimeur.lua first, a skin's next, finish.lua last;
                           common.lua, french.lua and hyphenate.lua, which a skin may list
imprimeur/assets/page/     the page's shell
imprimeur/assets/js/       the page's runtime
imprimeur/assets/js/blocks.mjs  the block diff, a pure function of the blocks' keys
imprimeur/assets/js/hash.mjs  the FNV-1a hash that names a diagram's drawing
imprimeur/assets/js/line-map.mjs  the map between the source's lines and offsets on the page
imprimeur/assets/js/mermaid.mjs  the page's diagrams: the script, the look, the drawings
imprimeur/assets/js/minitoc-rules.mjs  the rules of minitocs, as pure functions
imprimeur/assets/js/minitoc-ui.mjs  the page's minitocs: the tree of its headings, the pill and its popover, the buttons, the keys
imprimeur/assets/js/sync.mjs  what the page decides about scrolling, as pure functions
imprimeur/assets/css/      the base stylesheet, which reads the --imp-* tokens
imprimeur/assets/vendor/   third-party code, copied unchanged
imprimeur-skin-minitel/    the package of the skin Minitel, with a module and keys, and no fonts
imprimeur-skin-xix/        the package of the skin XIX: its manifest, assets/ (sheet,
                           filter), fonts.nix and a README of its fonts and options
imprimeur-skin-xviii/      the package of the skin XVIII, in the same shape
imprimeur-skin-xvii/       the package of the skin XVII, in the same shape
imprimeur-skin-briefing/   the package of the skin Briefing, in the same shape, with a module
imprimeur-skin-ecrivain/   the package of the skin Écrivain, the same, and the two scripts that
                           its fonts.nix runs to cut its faces
imprimeur-skin-tianlu/     the package of the skin Tianlu, in the same shape, with a module
examples/minitel/          Minitel's samples, French and English, with their sources
examples/xix/              XIX's samples, French and English, with their pictures
examples/xviii/            XVIII's samples, French and English, with their sources
examples/xvii/             XVII's samples, French and English, with their sources
examples/briefing/         Briefing's two briefs, Org and Markdown, with their sources
examples/ecrivain/         Écrivain's notebook, French and English, with their sources
examples/tianlu/           Tianlu's two essays, traditional and simplified, with their sources
tests/run-ert.el           strict ERT runner
tests/run-node             node test runner that fails when there is no test
tests/helpers/             helpers shared by the tests, the CDP client included
tests/helpers/imprimeur-test-themes.el  the themes for the tests of the palette
tests/bin/                 stand-ins for pandoc, Chromium and gh
tests/fixtures/            documents the tests read
tests/fixtures/minitoc/    the fixtures of the minitoc rules, by hand
tests/sommaire/            tests of sommaire
tests/imprimeur/           tests of imprimeur
tests/imprimeur-skin-minitel/  tests of the skin Minitel
tests/imprimeur-skin-xix/  tests of the skin XIX
tests/imprimeur-skin-xviii/  tests of the skin XVIII
tests/imprimeur-skin-xvii/  tests of the skin XVII
tests/imprimeur-skin-briefing/  tests of the skin Briefing
tests/imprimeur-skin-ecrivain/  tests of the skin Écrivain, and align, its check by pixels, by hand
tests/imprimeur-skin-tianlu/  tests of the skin Tianlu
tests/tools/               tests of the repository's own scripts; release_test.py is Python's
tests/docs/                the test that loads the README's configuration
tests/js/                  JavaScript tests, run by node
scripts/with-scratch-home  runs a command in a scratch home
scripts/lint.el            byte-compile and checkdoc, one file per Emacs
scripts/complexity.el      cyclomatic complexity of each definition
scripts/check-public       tracked files: text that must not be published, SPDX lines
scripts/check-commits      commits: titles, trailers, text that must not be published
scripts/public-patterns.sh what must not be published, sourced by both checks
scripts/smoke-xwidget      make smoke-xwidget: a separate Emacs on a real display
scripts/smoke-xwidget.el   what that Emacs checks of the view
scripts/check-docs.el      make docs: the Markdown's links, the READMEs against each other, and what the reference holds
scripts/make-gallery       make gallery: the README's pictures, on an Xvfb of its own
scripts/make-gallery.el    what each of its Emacs does
scripts/release.py         what the workflow CD runs: the version commit and the release
.github/workflows/         CI and CD; docs/reference/release-pipeline.md describes them
flake.nix                  the development shell
docs/tutorials/            documentation, after Diátaxis: a lesson
docs/how-to/               steps for one real problem
docs/reference/            options, commands and keys, documents, the skin API, minitoc rules
docs/explanation/          the design explained, with the diagrams, and why
docs/diagrams/             diagram sources, light and dark
docs/images/               exported diagrams, screenshots, and the press of 1568
docs/images/gallery/       each skin in light and dark, by make gallery
docs/social-media-preview.png  the repository's picture for social media
.diagram-design            the diagram-design profile of the diagrams
docs/work/                 ignored: plans and research notes
.worktree/                 ignored: one linked worktree per plan
```

## Packages

- A package's directory, name, main file and symbol prefix are the same;
  private symbols use `--`.
- A skin requires `imprimeur-skin`, never `imprimeur`, uses no `--` symbol of
  imprimeur, and registers itself once imprimeur loads, by an autoload cookie around
  `with-eval-after-load`; imprimeur requires no skin. Its classes start with its name;
  `imprimeur-` belongs to the core's filters. What it names of fonts is in its
  sheet's stacks, and `fonts.nix` beside it installs them.
- Neither package requires the other, uses its macros, `defsubst` forms or
  `--` symbols, or lists it in `Package-Requires`. They share only a written
  rule set and its fixtures, which both packages' tests run.
- `docs/reference/minitoc-rules.md` is the authority on minitocs: where an implementation
  and it disagree, the implementation is wrong. Its thresholds are constants,
  not options, and it leans on no language, so that sommaire and the JavaScript
  of the page cannot drift. The fixtures are written by hand from it, never
  generated.
- Neither package folds: folding stays Emacs's and the reader's, and neither
  calls a folding command.
- A package directory holds only what ships; tests live under `tests/`,
  because package-vc compiles a package directory recursively.
- One Emacs: both packages require 31.1, that of nixpkgs at the flake's pinned
  revision, frozen by `flake.lock`. Nothing is kept for an older one.
- A package finds its assets through a top-level `defconst` on
  `load-file-name`, never through `eval-when-compile`, which would freeze
  the build machine's path into the compiled file.
- Loading a package prints nothing and adds no timer, global hook or global
  key; the load tests check this.
- A vendored directory holds the files copied unchanged, their licences,
  and a README giving the version, the source and the checksums. The
  `.gitignore` includes `imprimeur/assets/vendor/` explicitly, as a global
  ignore file may exclude `vendor/`.

## Checks

`nix develop` provides Emacs 31.1, built for PGTK with xwidgets, with package-lint,
relint and straight.el, pandoc, Chromium, node, mermaid-cli, ffmpeg, git, luacheck, Python, actionlint and
Xvfb. Outside it, set
`EMACS`, and put package-lint, relint and straight.el on the load path.

- `make check` runs `lint` (byte-compilation with warnings as errors of the
  packages, the scripts and the test helpers; checkdoc, package-lint and
  relint of the packages; the cyclomatic complexity of every tracked `.el`
  file), `test` (ERT, node, then Python's `unittest` on `scripts/release.py`), `public`,
  `docs` (every relative link of the Markdown; the READMEs against each other; every
  option, face, command and key in the reference) and `workflows` (actionlint). Each test and lint run happens in a
  scratch home.
- `make commits BASE=main` checks the commits of a branch.
- A skin's package gets `-L imprimeur` for compilation and tests, and package-lint
  sees imprimeur through an archive that `scripts/lint.el` writes in the scratch home.
  Its Lua filters are not in `make lint` yet: run `luacheck --max-cyclomatic-complexity
  10 --globals pandoc` over them by hand.
- `make smoke-xwidget` runs a separate `emacs -Q` in a scratch home, on whichever
  display the environment gives, and prints PASS, FAIL or REPORT for what it
  checks of a real xwidget; `make check` does not run it, as it opens a desktop
  window. A second Emacs repeats the report on video with the GStreamer plugins
  of `IMPRIMEUR_SMOKE_GST_PLUGINS`, which the shell of `nix develop` sets. It
  runs on Xvfb: `DISPLAY=:N GDK_BACKEND=x11`, with `WAYLAND_DISPLAY` unset, as CI does
  through `xvfb-run`. A real Wayland session, and a wheel or a double-click by hand, are the
  owner's check.
- `make gallery` remakes the README's pictures, each from a real xwidget on an Xvfb of its
  own, with the skin's `fonts.nix` on a scratch font path; `make check` does not run it. Each
  page takes a short `TMPDIR`, as WebKit and Chromium put sockets under it.
- `tests/imprimeur-skin-ecrivain/align`, by hand in `nix develop`, builds that skin's fonts
  and judges by pixels, in Chromium and in WebKit on an Xvfb of its own, that its letters sit
  on the ruling; `make check` has neither the fonts nor a display.
- `tests/run-ert.el` exits 1 on an unexpected result, when there is no
  test, on a test expected to fail, on an `.el` file it would not load
  (outside `helpers/` and `fixtures/`, every one is named `*-test.el`), or
  on a skip whose reason `IMPRIMEUR_TEST_ALLOW_SKIP` does not list (reasons
  separated by commas); `make check` allows none. A test that must skip
  calls `ert-skip` with a string, such as "missing executable pandoc".
- `tests/run-node` exits 1 when there is no `*.test.mjs` file, when a file
  defines no test, or when a test or a suite is skipped or left to do.

## Releases

The workflows CI and CD test every branch and release `main`: see
`docs/reference/release-pipeline.md`. Only the pipeline writes `.version`, the tags and the
`;; Version:` headers; there is one version for the whole repository.

## Code

- Before the first edit, name the decisions, the external input and output,
  the owner of each resource, and the failure paths.
- Cyclomatic complexity, counted as 1 plus the decision points by the rules
  in `scripts/complexity.el`, is at most 10. Never move complexity between
  functions only to pass the check.
- No single-use helper function, unless a strong domain design stands behind it.
  A wish to pass the limit on complexity is no such design, and anything else is
  inlined. These kinds stand:
  - A parser of untrusted input at the boundary, with its own contract and tests.
    The limit on complexity may split it into stages: they stand by that contract,
    which they share with its entry point. So a stage needs no test of its own,
    though a decision among them may have one: the fixtures judge them through the
    entry point, and pandoc too when the parser is a scanner. The commentary of its
    file names them.
  - A pure decision judged by a table, the form that "Tests" asks of a scheduler or
    a throttle.
  - A handler, which runs later, at the call of Emacs or of another module, outside
    the flow of what registers it: a process's filter, sentinel or log function, a
    timer, a hook, an xwidget's callback, the end of a render, a session's answer
    to a request or to a page's message.
  - The start of a session or of a stream, paired with its end.
- Documents, file contents, HTTP requests and messages from the page are
  untrusted: parse them at the boundary and let deterministic code decide. A
  message from the page is parsed at `imprimeur-server-parse-message`, and takes
  integers only, but for the address of a link.
- Lisp compiles on a build without xwidgets, through `declare-function`, and
  `xwidget.el`, which adds global hooks and keys, loads with the first view.
- The Lua filters do no input or output and load no code, since pandoc's
  `--sandbox` does not cover them; `scripts/check-public` enforces this.
- The page puts the document's markup into `main` only through DOMPurify,
  and anything else, banners and titles included, as text.

## Tests

- Expectations come from the requirement or the documented contract, never
  from the implementation; each test file states the requirement it checks.
- Tests run in a scratch home made by `scripts/with-scratch-home`: fresh
  HOME, XDG directories and TMPDIR, the git identity `tests@example.invalid`
  passed by environment, no display. No test opens a desktop window, visits
  the user's files or reaches the network beyond the loopback interface. So
  `make check` cannot make an xwidget: only `make smoke-xwidget` can, which is
  no test of `make check`.
- A test that turns `imprimeur-mode` on binds `imprimeur-browser-program`
  to `tests/bin/fake-browser`, or to `tests/bin/headless-chromium`, and
  records `browse-url` and `find-file-other-window` instead of calling them.
  In batch, `imprimeur-target` at `auto` means the browser.
- `format-mode-line` returns an empty string in batch, so a test of sommaire's
  header line compares its structure and the pure `sommaire-segment`.
- `make-frame` fails in batch, so a test of a second Emacs frame makes a terminal
  frame on a pty of its own, which opens no desktop window.
- The one Emacs has xwidgets, so a test of a build without them unbinds their
  primitives in a child Emacs.
- `IMPRIMEUR_TEST_FONTS`, which the shell of `nix develop` provides, names
  the directory of the only fonts that a scratch home sees, whatever the
  machine has, so that a page lays out the same here and in CI.
- The page tests drive a headless Chromium over the DevTools protocol,
  through `--remote-debugging-pipe` (`tests/helpers/imprimeur-test-cdp.el`):
  no port, no Node, a profile in the scratch directory, no host resolved
  but 127.0.0.1.
- `make check` asserts nothing on the wall clock: schedulers and throttles
  are pure functions of a state, an event and a time, judged by decision
  tables; performance budgets belong to a separate target.

## Pictures

- Diagrams are drawn with the skill `diagram-design`, under the profile
  that `.diagram-design` names: `sanityinc-tomorrow`, whose light and dark
  colours are the Emacs themes `sanityinc-tomorrow-day` and
  `sanityinc-tomorrow-night`, with system fonts, since GitHub shows an SVG
  as an image that loads no font. Each diagram has a light and a dark
  source in `docs/diagrams/` and their SVG exports in `docs/images/`,
  shown through `<picture>` with `prefers-color-scheme`. A change to what a
  diagram shows changes both sources and both exports.
- `scripts/make-gallery` makes `docs/images/emacs-view*.png` and `docs/images/gallery/`.
  `sommaire-buffer.png` is made by a script kept in the untracked `docs/work/media/`.
- `docs/images/printer-1568.png` is Jost Amman's woodcut, as the README credits it.
  `docs/social-media-preview.png` is that picture, 600 high, on a white ground of 1280
  by 640, by ImageMagick.

## Writing

This repository is public.

- Nothing private in a tracked file or a commit message: no home directory
  path, no machine user name, no e-mail address other than the noreply
  identity and `example.invalid`. Write a real path as `<clone>` or
  `<scratch>`. `scripts/check-public` enforces this for tracked files and
  `scripts/check-commits` for commit messages, authors and committers, with
  the extra words listed, one per line, in the untracked
  `docs/work/private-words` of the primary checkout, which every worktree
  shares, or in the file that `IMPRIMEUR_PRIVATE_WORDS` names; they match
  as whole words, ignoring the case of ASCII letters. The user name is the
  login, or `IMPRIMEUR_CHECK_USER` when set.
- No U+2013 or U+2014 outside `LICENSE`, `COPYING` and vendored files.
- Every source file carries `SPDX-License-Identifier: EUPL-1.2 OR
  GPL-3.0-or-later` in its first 10 lines.
- Commit titles are in sentence case and the imperative, at most 50
  characters, without a final full stop; a commit message carries no
  `Co-Authored-By` or other attribution trailer.
- Before 1.0.0, only a branch's tip must pass, whatever `workflow:plans` asks of
  each commit: the full checks run once, on its last commit, and a commit before
  it may be broken. `make commits` still reads every commit. No compatibility
  shim is kept for an earlier behaviour. The release 1.0.0 ends this rule.
- Headings in sentence case.
- `README.zh-Hant.md` and `README.zh-Hans.md` translate `README.md`, each separately and
  in its own register, and each names the English commit it follows. Their code blocks
  are the English ones, byte for byte, and their links lead to the English pages. So a
  change to the README's sections, code, pictures or links fails `make docs` until both
  follow it; a change to its prose alone changes both, or leaves their commit to say
  that they lag.
- A century is written in Roman numerals with the ordinal raised: in Markdown
  `XVIII<sup>th</sup>`, in Org `XVIII^{th}`, and `XVIIIth` where nothing can
  raise it, such as a docstring or a commit message; never in figures. A skin's
  own name stays bare: XVII, XVIII, XIX.

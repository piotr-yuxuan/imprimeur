# Working in this repository

This repository holds two Emacs packages: `imprimeur`, which renders the
current buffer into a typeset page shown inside Emacs or in a browser, and
`sommaire`, which shows mini tables of contents in Org and Markdown buffers.
They live together for now and can be split later; `README.md` describes
them for users.

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
imprimeur/imprimeur-sync.el  the lines of an Org page, and the scroll sync
imprimeur/imprimeur-xwidget.el  the view: the page in an Emacs window, by an xwidget
imprimeur/assets/pandoc/   pandoc's data directory, with the Lua filter
imprimeur/assets/page/     the page's shell
imprimeur/assets/js/       the page's runtime
imprimeur/assets/js/blocks.mjs  the block diff, a pure function of the blocks' keys
imprimeur/assets/js/hash.mjs  the FNV-1a hash that names a diagram's drawing
imprimeur/assets/js/line-map.mjs  the map between the source's lines and offsets on the page
imprimeur/assets/js/mermaid.mjs  the page's diagrams: the script, the look, the drawings
imprimeur/assets/js/sync.mjs  what the page decides about scrolling, as pure functions
imprimeur/assets/css/      the base stylesheet, which reads the --imp-* tokens
imprimeur/assets/skins/    one directory per skin
imprimeur/assets/vendor/   third-party code, copied unchanged
tests/run-ert.el           strict ERT runner
tests/run-node             node test runner that fails when there is no test
tests/helpers/             helpers shared by the tests, the CDP client included
tests/helpers/imprimeur-test-themes.el  the themes for the tests of the palette
tests/bin/                 stand-ins for pandoc and Chromium
tests/fixtures/            documents the tests read
tests/fixtures/minitoc/    the fixtures of the minitoc rules, by hand
tests/sommaire/            tests of sommaire
tests/imprimeur/           tests of imprimeur
tests/tools/               tests of the repository's own scripts
tests/js/                  JavaScript tests, run by node
scripts/with-scratch-home  runs a command in a scratch home
scripts/lint.el            byte-compile and checkdoc, one file per Emacs
scripts/complexity.el      cyclomatic complexity of each definition
scripts/check-public       tracked files: text that must not be published, SPDX lines
scripts/check-commits      commits: titles, trailers, text that must not be published
scripts/public-patterns.sh what must not be published, sourced by both checks
scripts/smoke-xwidget      make smoke-xwidget: a separate Emacs on a real display
scripts/smoke-xwidget.el   what that Emacs checks of the view
flake.nix                  the development shell
docs/how-it-works.md       the design explained, with the diagrams
docs/minitoc-rules.md      the rules of minitocs, for sommaire and imprimeur's page
docs/diagrams/             diagram sources, light and dark
docs/images/               exported diagrams and screenshots
docs/social-media-preview.png  the repository's picture for social media
.diagram-design            the diagram-design profile of the diagrams
docs/work/                 ignored: plans and research notes
.worktree/                 ignored: one linked worktree per plan
```

## Packages

- A package's directory, name, main file and symbol prefix are the same;
  private symbols use `--`.
- Neither package requires the other, uses its macros, `defsubst` forms or
  `--` symbols, or lists it in `Package-Requires`. They share only a written
  rule set and its fixtures, which sommaire's tests run, and imprimeur's will
  once its page has minitocs.
- `docs/minitoc-rules.md` is the authority on minitocs: where an implementation
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

`nix develop` provides Emacs 31.1, built for PGTK with xwidgets, with package-lint
and relint, pandoc, Chromium, node, mermaid-cli, ffmpeg and git. Outside it, set
`EMACS`, and put package-lint and relint on the load path.

- `make check` runs `lint` (byte-compilation with warnings as errors of the
  packages, the scripts and the test helpers; checkdoc, package-lint and
  relint of the packages; the cyclomatic complexity of every tracked `.el`
  file), `test` (ERT, then node) and `public`. Each test and lint run
  happens in a scratch home.
- `make commits BASE=main` checks the commits of a branch.
- `make smoke-xwidget` runs a separate `emacs -Q` in a scratch home, on whichever
  display the environment gives, and prints PASS, FAIL or REPORT for what it
  checks of a real xwidget; `make check` does not run it, as it opens a desktop
  window. A second Emacs repeats the report on video with the GStreamer plugins
  of `IMPRIMEUR_SMOKE_GST_PLUGINS`, which the shell of `nix develop` sets. It
  runs on Xvfb: `DISPLAY=:N GDK_BACKEND=x11`, with `WAYLAND_DISPLAY` unset. A real
  Wayland session, and a wheel or a double-click by hand, are the owner's check.
- `tests/run-ert.el` exits 1 on an unexpected result, when there is no
  test, on a test expected to fail, on an `.el` file it would not load
  (outside `helpers/` and `fixtures/`, every one is named `*-test.el`), or
  on a skip whose reason `IMPRIMEUR_TEST_ALLOW_SKIP` does not list (reasons
  separated by commas); `make check` allows none. A test that must skip
  calls `ert-skip` with a string, such as "missing executable pandoc".
- `tests/run-node` exits 1 when there is no `*.test.mjs` file, when a file
  defines no test, or when a test or a suite is skipped or left to do.

## Code

- Before the first edit, name the decisions, the external input and output,
  the owner of each resource, and the failure paths.
- Cyclomatic complexity, counted as 1 plus the decision points by the rules
  in `scripts/complexity.el`, is at most 10. Never move complexity between
  functions only to pass the check.
- No single-use helper function, except a parser of untrusted input at the
  boundary, which gets its own contract and tests. The stages of one such parser,
  split where the limit on complexity asks, share the contract of its entry point
  and have no tests of their own: the fixtures judge them through it, and pandoc
  too when the parser is a scanner. The commentary of its file names them.
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
  the directory of the only fonts that the test on maths sees, whatever the
  machine has, so that its brackets stretch the same everywhere.
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
- The screenshots and the social preview are made by scripts kept in the
  untracked `docs/work/media/` and `docs/work/social-preview/`.

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
- A century is written in Roman numerals with the ordinal raised: in Markdown
  `XVIII<sup>th</sup>`, in Org `XVIII^{th}`, and `XVIIIth` where nothing can
  raise it, such as a docstring or a commit message; never in figures. A skin's
  own name stays bare: XVII, XVIII, XIX.

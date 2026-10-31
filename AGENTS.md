# Working in this repository

This repository holds two Emacs packages: `imprimeur`, which renders the
current buffer into a typeset page shown inside Emacs or in a browser, and
`sommaire`, which shows mini tables of contents in Org and Markdown buffers.
They live together for now and can be split later; `README.md` describes
them for users.

## Workflow

Every change follows the skill `workflow:plans`; load it before the first
edit. In this repository: plans are `docs/work/plans/NNN-slug.md`, not
tracked; the checks are `make check` and `make test-min`, run in
`nix develop`, and before a merge `make commits BASE=main`. The research
behind the plans is under `docs/work/research_notes/`, also not tracked.

## Layout

```
sommaire/                  the package sommaire: shipped .el files only
imprimeur/                 the package imprimeur: shipped .el files and assets/
tests/run-ert.el           strict ERT runner
tests/run-node             node test runner that fails when there is no test
tests/helpers/             helpers shared by the tests
tests/sommaire/            tests of sommaire, also run on its minimum Emacs
tests/imprimeur/           tests of imprimeur, also run on its minimum Emacs
tests/tools/               tests of the repository's own scripts
tests/js/                  JavaScript tests, run by node
scripts/with-scratch-home  runs a command in a scratch home
scripts/lint.el            byte-compile and checkdoc, one file per Emacs
scripts/complexity.el      cyclomatic complexity of each function
scripts/check-public       text that must not be published, SPDX lines
scripts/check-commits      commit titles and trailers
flake.nix                  the development shell
docs/work/                 ignored: plans and research notes
.worktree/                 ignored: one linked worktree per plan
```

## Packages

- A package's directory, name, main file and symbol prefix are the same;
  private symbols use `--`.
- Neither package requires the other, uses its macros, `defsubst` forms or
  `--` symbols, or lists it in `Package-Requires`. They share only a written
  rule set and its fixtures, which both test suites run.
- A package directory holds only what ships; tests live under `tests/`,
  because package-vc compiles a package directory recursively.
- Minimum Emacs: 29.1 for sommaire, 30.1 for imprimeur. `make test-min` runs
  each package's suite on its minimum.
- A package finds its assets through a top-level `defconst` on
  `load-file-name`, never through `eval-when-compile`, which would freeze
  the build machine's path into the compiled file.
- Loading a package prints nothing and adds no timer, global hook or global
  key; the load tests check this.

## Checks

`nix develop` provides Emacs 31.1 with package-lint and relint, Emacs 29.1
and 30.1, pandoc, Chromium, node, mermaid-cli, ffmpeg and git. Outside it,
set `EMACS`, `EMACS_29` and `EMACS_30`, and put package-lint and relint on
the load path.

- `make check` runs `lint` (byte-compilation with warnings as errors,
  checkdoc, package-lint, relint, cyclomatic complexity), `test` (ERT, then
  node) and `public`. Each test and lint run happens in a scratch home.
- `make test-min` runs each package's ERT suite on its minimum Emacs.
- `make commits BASE=main` checks the commits of a branch.
- `tests/run-ert.el` exits 1 on an unexpected result, when there is no
  test, on a test expected to fail, on an `.el` file it would not load
  (outside `helpers/` and `fixtures/`, every one is named `*-test.el`), or
  on a skip whose reason `IMPRIMEUR_TEST_ALLOW_SKIP` does not list (reasons
  separated by commas); `make check` allows none. A test that must skip
  calls `ert-skip` with a string, such as "missing executable pandoc".
- `tests/run-node` exits 1 when there is no `*.test.mjs` file, when a file
  defines no test, or when a test is skipped or left to do.

## Code

- Before the first edit, name the decisions, the external input and output,
  the owner of each resource, and the failure paths.
- Cyclomatic complexity, counted as 1 plus the decision points by the rules
  in `scripts/complexity.el`, is at most 10. Never move complexity between
  functions only to pass the check.
- No single-use helper function, except a parser of untrusted input at the
  boundary, which gets its own contract and tests.
- Documents, file contents, HTTP requests and messages from the page are
  untrusted: parse them at the boundary and let deterministic code decide.

## Tests

- Expectations come from the requirement or the documented contract, never
  from the implementation; each test file states the requirement it checks.
- Tests run in a scratch home made by `scripts/with-scratch-home`: fresh
  HOME, XDG directories and TMPDIR, the git identity `tests@example.invalid`
  passed by environment, no display. No test opens a window, visits the
  user's files or reaches the network beyond the loopback interface.
- `make check` asserts nothing on the wall clock: schedulers and throttles
  are pure functions of a state, an event and a time, judged by decision
  tables; performance budgets belong to a separate target.

## Writing

This repository is public.

- Nothing private in a tracked file or a commit message: no home directory
  path, no machine user name, no e-mail address other than the noreply
  identity and `example.invalid`. Write a real path as `<clone>` or
  `<scratch>`. `scripts/check-public` enforces this, with the extra words
  listed, one per line, in the untracked `docs/work/private-words`.
- No U+2013 or U+2014 outside `LICENSE`, `COPYING` and vendored files.
- Every source file carries `SPDX-License-Identifier: EUPL-1.2 OR
  GPL-3.0-or-later` in its first 10 lines.
- Commit titles are in sentence case and the imperative, at most 50
  characters, without a final full stop; a commit message carries no
  `Co-Authored-By` or other attribution trailer.
- Headings in sentence case.

# The release pipeline

Two workflows of GitHub Actions and one script. None of them holds a check of its own: the
checks are in the `Makefile`, and the release in `scripts/release.py`.

## The workflow CI

`.github/workflows/ci.yml` runs on a push to any branch, and on a pull request from a fork,
which it checks at the pull request's own commit. A newer run of the same reference cancels
the one under way. Its permission is `contents: read`. It runs on `ubuntu-24.04`, with
Nix from `cache.nixos.org` and this repository's own Actions cache, in this order:

| Step | Why |
|---|---|
| `nix-community/cache-nix-action` | Restores the Nix store, and saves it once the job has succeeded: see "What is cached" |
| `sysctl kernel.apparmor_restrict_unprivileged_userns=0` | That runner's AppArmor otherwise stops the sandboxes of Chromium and WebKit, which the tests keep |
| `nix develop -c make check` | The checks |
| `nix develop -c make commits BASE=origin/main` | The commits of a branch, on a branch other than `main` |
| `make smoke-xwidget`, under `xvfb-run` | The view in a real xwidget, which `make check` cannot make |

## The workflow CD

`.github/workflows/cd.yml` runs in two cases, and never in a fork:

- once CI completes on `main`: it goes on only if CI's conclusion is `success`, its event
  `push`, and its commit from this repository;
- by hand on `main`, with an input `bump`: `patch`, the default, `minor` or `major`.

Its permissions are `contents: write` and `actions: read`, with the job's own `github.token` and no secret. Runs
take one at a time: the one that runs is never cancelled, and a newer one takes the place of
the one that waits. It checks out the commit that CI checked, with every tag, and runs
`python3 scripts/release.py`. The runner's Python and `gh` serve: it needs no Nix.

## What is cached

CI's Nix store, in this repository's Actions cache. No third-party binary cache, no
`--accept-flake-config` and no change to `substituters`.

- The key is the runner's system and a hash of `flake.nix` and `flake.lock`. Failing that, the
  newest cache with the same system is restored, and what the job adds is saved under the new key.
- GitHub lets a branch read its own caches and `main`'s, never write to `main`'s. So a branch
  restores `main`'s store and cannot change it.
- A cache is saved at the end of a job that succeeded, if its key has none yet.
- The permission stays `contents: read`: the action calls GitHub's API only to purge, or for
  `restore-prefixes-all-matches`, and CI uses neither.
- Nothing is purged, as GitHub evicts by itself. No garbage is collected, as a collection cannot
  tell old paths from the ones this shell needs. So a new lock's cache holds the old store too;
  to start afresh, delete the caches under **Actions**, then **Caches**.

The tests are not shortened. CI's first run took 731 s for `nix develop -c make check`, against
about 600 s with nothing to fetch, so the fetch and the nine store paths that `cache.nixos.org`
lacks cost about 130 s of 13.5 minutes: the most a cache can save, less the time to restore it.
Nor is the flake's evaluation kept, as its cache is in the home directory.

CD has no cache, as it installs nothing: it runs a script from a checkout, in about 14 s.

## What the release writes

The version is one for the whole repository, and the tag is `X.Y.Z`.

| Write | What it is |
|---|---|
| The version commit on `main` | Through GitHub's API, so that GitHub signs it. It sets `.version` and the `;; Version:` header of each package's main file. Its message is `Version X.Y.Z`, a blank line and `[skip ci]`, so that no CI follows it |
| The release | `X.Y.Z`, with its tag on that commit. Its notes are the table of the files changed since the release before, and the compare link. A first release has neither |

`.version` is written only by the pipeline. A missing file counts as nothing, so the first
release is `0.0.0`, whatever the bump. After that a bump raises its part and sets the parts
after it to zero.

## What a run decides

A run reads first, and makes only the writes that are missing.

| What it finds | What it does | Status |
|---|---|---|
| `main` is at the commit | Both writes | 0 |
| `main` has moved, and the next commit is a version commit whose release exists | Nothing | 0 |
| `main` has moved, and the next commit is a version commit with no release | The release alone: a run cut short finishes | 0 |
| `main` has moved, and the next commit is no version commit | Nothing, as the newer push's run releases | 0 |
| `main` is at a version commit with no release, by hand | The release alone, and no bump: run it again for that | 0 |
| By hand, and CI has not succeeded on `main`'s head, or on its parent when the head is a version commit | Nothing | 2 |
| `.version` is malformed, a package's header is not found exactly once, the next version has its tag, or a version commit's tag is on another commit | Nothing | 2 |
| git or GitHub refuses a call, takes over 120 s, or answers something else | Nothing more. If `main` moved just after the read, GitHub refuses the commit, and the newer push's run releases | 2 |

Only a run of the commit before a version commit finishes that release. A newer push's run does
not: it releases the next version, and the one cut short has none until its own run is run again.

A version commit is told by its message, its one parent, and what it changes: `.version`, and
only main files of packages beside it.

## Raise a version by hand

Open **Actions**, then **CD**, then **Run workflow**, on `main`, and choose the `bump`. Or:

```sh
gh workflow run cd.yml --ref main -f bump=minor
```

## Keep a clone in step

Each release adds a commit to `origin/main`. So a local `main` runs `git pull --ff-only` before
its next merge, or the push of that merge is refused.

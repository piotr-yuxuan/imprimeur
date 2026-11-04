# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The checks of imprimeur and sommaire.  Run them from the repository's
# root in `nix develop`, which provides every tool.  Every test and lint
# run happens in a scratch home.

EMACS ?= emacs
BASE ?= main
# What `test-elisp' runs: CI gives each job some of these directories.
ERT_DIRS ?= tests

SCRATCH := scripts/with-scratch-home
SKINS := $(wildcard imprimeur-skin-*)
CORE_EL := $(wildcard sommaire/*.el imprimeur/*.el)
SKIN_EL := $(wildcard imprimeur-skin-*/*.el)
PACKAGE_EL := $(CORE_EL) $(SKIN_EL)
TOOL_EL := $(wildcard scripts/*.el tests/helpers/*.el) tests/run-ert.el
TRACKED_EL := $(shell git ls-files '*.el')
RUN_ERT := -Q --batch -L sommaire -L imprimeur $(addprefix -L ,$(SKINS)) -L tests/helpers -l tests/run-ert.el

.PHONY: check check-static lint compile checkdoc package-lint relint complexity \
	test test-elisp test-js test-python public docs workflows commits smoke-xwidget gallery demo

check: check-static test-elisp

# All that needs no page, which CI runs apart from each directory's tests.
check-static: lint test-js test-python public docs workflows

lint: compile checkdoc package-lint relint complexity

compile:
	@for file in $(CORE_EL) $(TOOL_EL); do \
	  $(SCRATCH) $(EMACS) -Q --batch -L "$$(dirname "$$file")" -l scripts/lint.el \
	    -f repo-lint-compile "$$file" || exit 1; \
	done
	@for file in $(SKIN_EL); do \
	  $(SCRATCH) $(EMACS) -Q --batch -L imprimeur -L "$$(dirname "$$file")" -l scripts/lint.el \
	    -f repo-lint-compile "$$file" || exit 1; \
	done

checkdoc:
	@for file in $(PACKAGE_EL); do \
	  $(SCRATCH) $(EMACS) -Q --batch -l scripts/lint.el -f repo-lint-checkdoc "$$file" || exit 1; \
	done

package-lint:
	@for package in sommaire imprimeur; do \
	  $(SCRATCH) $(EMACS) -Q --batch -L $$package -l package-lint \
	    --eval "(setq package-lint-main-file \"$$package/$$package.el\")" \
	    --eval "(setq package-lint-batch-fail-on-warnings t)" \
	    -f package-lint-batch-and-exit $$package/*.el || exit 1; \
	done
	@for package in $(SKINS); do \
	  $(SCRATCH) $(EMACS) -Q --batch -L imprimeur -L $$package -l package-lint \
	    --eval "(setq package-lint-main-file \"$$package/$$package.el\")" \
	    --eval "(setq package-lint-batch-fail-on-warnings t)" \
	    -l scripts/lint.el -f repo-lint-sibling-archive \
	    -f package-lint-batch-and-exit $$package/*.el || exit 1; \
	done

relint:
	@$(SCRATCH) $(EMACS) -Q --batch -l relint -f relint-batch $(PACKAGE_EL)

complexity:
	@$(EMACS) -Q --batch -l scripts/complexity.el -f repo-complexity-batch $(TRACKED_EL)

test: test-elisp test-js test-python

test-elisp:
	@$(SCRATCH) $(EMACS) $(RUN_ERT) $(ERT_DIRS)

test-js:
	@$(SCRATCH) tests/run-node tests/js

test-python:
	@PYTHONDONTWRITEBYTECODE=1 $(SCRATCH) python3 -m unittest discover -s tests/tools -p '*_test.py'

public:
	@scripts/check-public

# Every relative link of the Markdown, the READMEs against each other, and what
# the reference must hold.
docs:
	@$(SCRATCH) $(EMACS) -Q --batch -l scripts/check-docs.el -f check-docs-batch-links
	@$(SCRATCH) $(EMACS) -Q --batch -l scripts/check-docs.el -f check-docs-batch-translations
	@$(SCRATCH) $(EMACS) -Q --batch -L sommaire -L imprimeur $(addprefix -L ,$(SKINS)) \
	  -l scripts/check-docs.el -f check-docs-batch-reference

workflows:
	@actionlint

commits:
	@scripts/check-commits $(BASE)

# The page in a real xwidget, on whichever display the environment gives.  It
# opens a desktop window, so `check' does not run it.
smoke-xwidget:
	@EMACS="$(EMACS)" scripts/smoke-xwidget

# The README's pictures, on an Xvfb of its own, with each skin's fonts on a scratch
# font path.  `check' does not run it either.
gallery:
	@EMACS="$(EMACS)" scripts/make-gallery

# The video of docs/demo.mp4, on an Xvfb of its own.  `check' does not run it either.
demo:
	@EMACS="$(EMACS)" scripts/make-demo

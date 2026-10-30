# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# The checks of imprimeur and sommaire.  Run them from the repository's
# root in `nix develop`, which provides every tool and the packages'
# minimum Emacs versions (IMPRIMEUR_EMACS_29 and IMPRIMEUR_EMACS_30).
# Every test and lint run happens in a scratch home.

EMACS ?= emacs
EMACS_29 ?= $(IMPRIMEUR_EMACS_29)
EMACS_30 ?= $(IMPRIMEUR_EMACS_30)
BASE ?= main

SCRATCH := scripts/with-scratch-home
PACKAGE_EL := $(wildcard sommaire/*.el imprimeur/*.el)
TRACKED_EL := $(shell git ls-files '*.el')
RUN_ERT := -Q --batch -L sommaire -L imprimeur -L tests/helpers -l tests/run-ert.el

.PHONY: check lint compile checkdoc package-lint relint complexity \
	test test-elisp test-js test-min public commits

check: lint test public

lint: compile checkdoc package-lint relint complexity

compile:
	@for file in $(PACKAGE_EL); do \
	  $(SCRATCH) $(EMACS) -Q --batch -L "$$(dirname "$$file")" -l scripts/lint.el \
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

relint:
	@$(SCRATCH) $(EMACS) -Q --batch -l relint -f relint-batch $(PACKAGE_EL)

complexity:
	@$(EMACS) -Q --batch -l scripts/complexity.el -f repo-complexity-batch $(TRACKED_EL)

test: test-elisp test-js

test-elisp:
	@$(SCRATCH) $(EMACS) $(RUN_ERT) tests

test-js:
	@$(SCRATCH) tests/run-node tests/js

# Each package's suite on its minimum Emacs; the tests of the tools need
# Emacs 31.1 and run in test-elisp only.
test-min:
	@test -n "$(EMACS_29)" -a -n "$(EMACS_30)" || \
	  { echo "make test-min: set EMACS_29 and EMACS_30, as nix develop does" >&2; exit 2; }
	@$(SCRATCH) $(EMACS_29) -Q --batch -L sommaire -L tests/helpers -l tests/run-ert.el tests/sommaire
	@$(SCRATCH) $(EMACS_30) -Q --batch -L imprimeur -L tests/helpers -l tests/run-ert.el tests/imprimeur

public:
	@scripts/check-public

commits:
	@scripts/check-commits $(BASE)

;;; lint-test.el --- Tests of the lint driver  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: a free variable and a docstring without a final period each
;; make the lint exit 1 and name the file and line (plan 001, acceptance 2).

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(defun lint-test-fixture (docstring body)
  "Return a minimal package file whose one function has DOCSTRING and BODY.
The docstring is on line 7 and the body on line 8."
  (format ";;; fixture.el --- Fixture  -*- lexical-binding: t; -*-
;;; Commentary:
;; Fixture.
;;; Code:

(defun fixture-f (x)
  %S
  %s)

(provide 'fixture)
;;; fixture.el ends here
" docstring body))

(defun lint-test-run (check contents)
  "Run the lint function CHECK on a scratch fixture.el holding CONTENTS.
Return (STATUS . OUTPUT)."
  (let ((directory (repo-test-tree `(("fixture.el" . ,contents)))))
    (repo-test-emacs (list "-L" directory
                           "-l" (expand-file-name "scripts/lint.el" repo-test-root)
                           "-f" check "fixture.el")
                     nil directory)))

(ert-deftest lint-compile-passes-a-clean-file ()
  (should (equal (car (lint-test-run "repo-lint-compile"
                                     (lint-test-fixture "Return X." "(1+ x)")))
                 0)))

(ert-deftest lint-compile-rejects-a-free-variable ()
  (let ((result (lint-test-run "repo-lint-compile"
                               (lint-test-fixture "Return X." "(+ x fixture-free)"))))
    (should (equal (car result) 1))
    (should (string-match-p "fixture\\.el:8:[0-9]+:.*fixture-free" (cdr result)))))

(ert-deftest lint-checkdoc-passes-a-clean-file ()
  (should (equal (car (lint-test-run "repo-lint-checkdoc"
                                     (lint-test-fixture "Return X." "(1+ x)")))
                 0)))

(ert-deftest lint-checkdoc-rejects-a-docstring-without-final-period ()
  (let ((result (lint-test-run "repo-lint-checkdoc"
                               (lint-test-fixture "Return X" "(1+ x)"))))
    (should (equal (car result) 1))
    (should (string-match-p "fixture\\.el:7: First sentence should end with punctuation"
                            (cdr result)))))

;;; lint-test.el ends here

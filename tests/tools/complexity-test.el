;;; complexity-test.el --- Tests of the complexity check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: cyclomatic complexity, counted as 1 plus the decision
;; points by the rules that scripts/complexity.el and AGENTS.md state, may
;; not exceed 10; a function of complexity 11 makes the check exit 1 and
;; name the file and line, one of complexity 10 passes (plan 001,
;; acceptance 2).

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(load (expand-file-name "scripts/complexity.el" repo-test-root) nil t)

(ert-deftest complexity-counts-each-rule ()
  "Each counting rule of the commentary, one form at a time."
  (dolist (case '(((if a b c) . 1)
                  ((when a b) . 1)
                  ((dolist (x xs) (when x y)) . 2)
                  ((cond (a 1) (b 2) (t 3)) . 2)
                  ((cond (a 1) (b 2)) . 2)
                  ((pcase x (1 a) (`(,y) y) (_ c)) . 2)
                  ((cl-case x (1 a) (otherwise b)) . 1)
                  ((condition-case nil x (error y) (quit z)) . 2)
                  ((and a b c) . 2)
                  ((or a) . 0)
                  ((lambda (x) (if x 1 2)) . 1)
                  ('(if a b) . 0)
                  ((let ((x 1)) x) . 0)))
    (should (equal (cons (car case) (repo-complexity--points (car case))) case))))

(defun complexity-test-run (branches)
  "Check a scratch file whose function has BRANCHES `when' forms.
Its complexity is BRANCHES plus 1.  Return (STATUS . OUTPUT)."
  (let ((directory (repo-test-tree
                    `(("fixture.el"
                       . ,(format ";; Fixture.\n(defun fixture (x)\n  \"Doc.\"\n%s)\n"
                                  (mapconcat (lambda (n) (format "  (when x %d)" n))
                                             (number-sequence 1 branches) "\n")))))))
    (repo-test-emacs (list "-l" (expand-file-name "scripts/complexity.el" repo-test-root)
                           "-f" "repo-complexity-batch" "fixture.el")
                     nil directory)))

(ert-deftest complexity-passes-ten ()
  (should (equal (car (complexity-test-run 9)) 0)))

(ert-deftest complexity-rejects-eleven ()
  (let ((result (complexity-test-run 10)))
    (should (equal (car result) 1))
    (should (string-match-p "fixture\\.el:2: fixture has a cyclomatic complexity of 11"
                            (cdr result)))))

;;; complexity-test.el ends here

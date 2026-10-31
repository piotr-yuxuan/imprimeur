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
                  ((seq-doseq (x xs) x) . 1)
                  ((pcase-dolist (`(,a) xs) a) . 1)
                  ((cl-loop for x in xs when x collect x) . 2)
                  ((cl-loop for x in xs while x unless (cdr x) collect x) . 3)
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

(defun complexity-test-run (source)
  "Check a scratch file fixture.el holding SOURCE; return (STATUS . OUTPUT)."
  (repo-test-emacs (list "-l" (expand-file-name "scripts/complexity.el" repo-test-root)
                         "-f" "repo-complexity-batch" "fixture.el")
                   nil (repo-test-tree `(("fixture.el" . ,source)))))

(defun complexity-test-branches (count)
  "Return COUNT `when' forms as source: COUNT decision points."
  (mapconcat (lambda (n) (format "\n  (when x %d)" n)) (number-sequence 1 count) ""))

(ert-deftest complexity-passes-ten ()
  (should (equal (car (complexity-test-run
                       (format ";; Fixture.\n(defun fixture (x)\n  \"Doc.\"%s)\n"
                               (complexity-test-branches 9))))
                 0)))

(ert-deftest complexity-rejects-eleven ()
  (let ((result (complexity-test-run
                 (format ";; Fixture.\n(defun fixture (x)\n  \"Doc.\"%s)\n"
                         (complexity-test-branches 10)))))
    (should (equal (car result) 1))
    (should (string-match-p "fixture\\.el:2: fixture has a cyclomatic complexity of 11"
                            (cdr result)))))

(ert-deftest complexity-measures-every-kind-of-definition ()
  "Tests, modes, aliases and definitions inside containers are measured too."
  (dolist (template '("(ert-deftest fixture ()%s)"
                      "(define-minor-mode fixture \"Doc.\" :global t%s)"
                      "(define-derived-mode fixture text-mode \"F\" \"Doc.\"%s)"
                      "(defalias 'fixture (lambda (x)%s))"
                      "(progn (defun fixture (x)%s))"
                      "(with-eval-after-load 'org (defun fixture (x)%s))"
                      "(define-globalized-minor-mode fixture fixture-mode ignore%s)"
                      "(cl-defgeneric fixture (x)%s)"
                      "(eval-when-compile (defun fixture (x)%s))"
                      "(eval-and-compile (defun fixture (x)%s))"
                      "(when t (defun fixture (x)%s))"
                      "(let ((y 1)) (defun fixture (x)%s))"))
    (let ((result (complexity-test-run (format template (complexity-test-branches 10)))))
      (should (equal (cons template (car result)) (cons template 1)))
      (should (string-match-p "fixture\\.el:1: .*fixture has a cyclomatic complexity of 11"
                              (cdr result))))))

;;; complexity-test.el ends here

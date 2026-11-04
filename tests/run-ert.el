;;; run-ert.el --- Run ERT tests and fail on anything unexpected  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Usage, through scripts/with-scratch-home:
;;
;;   emacs -Q --batch -L DIR... -l tests/run-ert.el TEST-DIR...
;;
;; Loads every *-test.el file under each TEST-DIR and runs all their tests.
;; Exits with status 0 when every test passed; 2 when HOME is not a scratch
;; home; 1 when anything else happened:
;;
;; - an unexpected result, or no test at all;
;; - a test expected to fail (:expected-result other than :passed);
;; - a skip whose reason the environment variable
;;   IMPRIMEUR_TEST_ALLOW_SKIP does not list (reasons separated by
;;   commas, compared as whole strings);
;; - an .el file that would not be loaded: outside a directory named
;;   helpers or fixtures, every .el file but this runner must be named
;;   *-test.el.
;;
;; IMPRIMEUR_TEST_PAGE, as K/N, runs only every Nth test by name, from the Kth, so that
;; N runs share the tests evenly and each test falls in one.  Anything else but an
;; empty value exits 2, as a page that ran nothing must not pass for one that passed.
;;
;; `ert-run-tests-batch-and-exit' would exit 0 on skips and expected
;; failures, which would let a missing tool or a broken test pass.

;;; Code:

(require 'ert)
(require 'seq)

(defconst run-ert-page
  (let ((page (or (getenv "IMPRIMEUR_TEST_PAGE") "")))
    (cond ((equal page "") nil)
          ((and (string-match "\\`\\([1-9][0-9]*\\)/\\([1-9][0-9]*\\)\\'" page)
                (<= (string-to-number (match-string 1 page)) (string-to-number (match-string 2 page))))
           (cons (string-to-number (match-string 1 page)) (string-to-number (match-string 2 page))))
          (t (message "run-ert: IMPRIMEUR_TEST_PAGE is not K/N with K at most N: %s" page)
             (kill-emacs 2))))
  "The page to run, as (K . N), or nil for every test.")

(unless (file-exists-p (expand-file-name "~/.imprimeur-scratch"))
  (message "run-ert: HOME is not a scratch home; use scripts/with-scratch-home")
  (kill-emacs 2))

(let* ((directories (mapcar #'expand-file-name command-line-args-left))
       ;; Each .el file with its name relative to its test directory, so
       ;; that only directories below it can exempt it.
       (all (mapcan (lambda (directory)
                      (mapcar (lambda (file) (cons file (file-relative-name file directory)))
                              (directory-files-recursively directory "\\.el\\'")))
                    directories))
       (files (seq-filter (lambda (file) (string-suffix-p "-test.el" file)) (mapcar #'car all)))
       (misnamed (mapcar #'car
                         (seq-remove (lambda (entry)
                                       (or (member (car entry) files)
                                           (equal (file-truename (car entry))
                                                  (file-truename load-file-name))
                                           (string-match-p "\\(?:\\`\\|/\\)\\(?:helpers\\|fixtures\\)/"
                                                           (cdr entry))))
                                     all)))
       (allowed (split-string (or (getenv "IMPRIMEUR_TEST_ALLOW_SKIP") "")
                              "," t "[[:space:]]+"))
       (refused 0))
  (setq command-line-args-left nil)
  (dolist (file misnamed)
    (message "run-ert: not a test file name, so never loaded: %s" file))
  (mapc #'load files)
  (let ((stats (ert-run-tests-batch
                (if run-ert-page
                    (let ((position 0))
                      (cons 'member
                            (seq-filter (lambda (_name)
                                          (setq position (1+ position))
                                          (= (% (1- position) (cdr run-ert-page)) (1- (car run-ert-page))))
                                        (sort (mapcar #'ert-test-name (ert-select-tests t t))))))
                  t))))
    (mapc (lambda (test)
            (let ((result (ert-test-most-recent-result test)))
              (when (or (not (eq (ert-test-expected-result-type test) :passed))
                        (and (ert-test-skipped-p result)
                             (not (member (cadr (ert-test-result-with-condition-condition
                                                result))
                                          allowed))))
                (message "run-ert: refused: %s (expected to fail, or skipped)"
                         (ert-test-name test))
                (setq refused (1+ refused)))))
          (ert--stats-tests stats))
    (message "run-ert: %d tests in %d files, %d unexpected, %d skipped, %d refused, %d misnamed files"
             (ert-stats-total stats) (length files)
             (ert-stats-completed-unexpected stats)
             (ert-stats-skipped stats) refused (length misnamed))
    (kill-emacs (if (and (> (ert-stats-total stats) 0)
                         (zerop (ert-stats-completed-unexpected stats))
                         (zerop refused)
                         (null misnamed))
                    0
                  1))))

;;; run-ert.el ends here

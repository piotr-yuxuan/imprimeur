;;; run-ert-test.el --- Tests of the strict ERT runner  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: the test runner rejects failing, absent and silently
;; skipped tests, tests expected to fail and test files it would not load,
;; and refuses to run outside a scratch home (plan 001, acceptance 2, and
;; its review).  Each test runs tests/run-ert.el in a child Emacs on a
;; scratch directory of test files.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(defun run-ert-test-status (files &optional environment)
  "Run tests/run-ert.el on a scratch directory holding FILES.
ENVIRONMENT is added to the child's environment.  Return the exit
status."
  (car (repo-test-emacs (list "-l" (expand-file-name "tests/run-ert.el" repo-test-root)
                              (repo-test-tree files))
                        ;; The first of a name wins: a child takes no seed or page of the run around it.
                        (append environment '("IMPRIMEUR_TEST_SEED=" "IMPRIMEUR_TEST_PAGE=")))))

(defconst run-ert-test-passing
  "(ert-deftest fixture-passes () (should t))\n"
  "A test file whose only test passes.")

(ert-deftest run-ert-passes-when-every-test-passes ()
  (should (equal (run-ert-test-status `(("a-test.el" . ,run-ert-test-passing))) 0)))

(ert-deftest run-ert-runs-the-page-it-is-asked-for ()
  ;; By name: the one that fails is the second of two, whichever way they are filed.
  (let ((files `(("b-test.el" . "(ert-deftest fixture-b-fails () (should nil))\n")
                 ("a-test.el" . "(ert-deftest fixture-a-passes () (should t))\n"))))
    (should (equal (run-ert-test-status files '("IMPRIMEUR_TEST_PAGE=1/2")) 0))
    (should (equal (run-ert-test-status files '("IMPRIMEUR_TEST_PAGE=2/2")) 1))
    (should (equal (run-ert-test-status files '("IMPRIMEUR_TEST_PAGE=")) 1))
    (should (equal (run-ert-test-status files) 1))))

(ert-deftest run-ert-pages-of-a-seed-share-the-tests ()
  ;; One test fails: whatever the seed, exactly one of two pages holds it, and the seeds
  ;; do not all put it in the same page.
  (let* ((files `(("a-test.el" . "(ert-deftest fixture-a-passes () (should t))\n")
                  ("b-test.el" . "(ert-deftest fixture-b-fails () (should nil))\n")))
         (status (lambda (seed page)
                   (run-ert-test-status files (list (concat "IMPRIMEUR_TEST_SEED=" seed)
                                                    (concat "IMPRIMEUR_TEST_PAGE=" page)))))
         (firsts (mapcar (lambda (seed)
                           (let ((first (funcall status seed "1/2")))
                             (should (equal (sort (list first (funcall status seed "2/2"))) '(0 1)))
                             first))
                         '("1" "2" "3" "4" "5" "6"))))
    (should (equal (sort (seq-uniq firsts)) '(0 1)))
    ;; The same seed, the same page.
    (should (equal (funcall status "1" "1/2") (car firsts)))))

(ert-deftest run-ert-refuses-a-page-that-is-none ()
  (dolist (page '("3/2" "0/2" "2" "a/b" "1/0" "1/2 "))
    (ert-info (page)
      (should (equal (run-ert-test-status `(("a-test.el" . ,run-ert-test-passing))
                                          (list (concat "IMPRIMEUR_TEST_PAGE=" page)))
                     2)))))

(ert-deftest run-ert-fails-on-a-failing-test ()
  (should (equal (run-ert-test-status
                  `(("a-test.el" . ,run-ert-test-passing)
                    ("b-test.el" . "(ert-deftest fixture-fails () (should nil))\n")))
                 1)))

(ert-deftest run-ert-fails-without-tests ()
  (should (equal (run-ert-test-status '(("README" . "No test here.\n"))) 1)))

(ert-deftest run-ert-fails-on-a-skip-not-allowed ()
  (should (equal (run-ert-test-status
                  '(("a-test.el" . "(ert-deftest fixture-skips () (ert-skip \"missing executable x\"))\n")))
                 1)))

(ert-deftest run-ert-passes-on-an-allowed-skip ()
  (should (equal (run-ert-test-status
                  '(("a-test.el" . "(ert-deftest fixture-skips () (ert-skip \"missing executable x\"))\n"))
                  '("IMPRIMEUR_TEST_ALLOW_SKIP=missing executable y, missing executable x"))
                 0)))

(ert-deftest run-ert-fails-on-a-file-it-would-not-load ()
  (should (equal (run-ert-test-status
                  `(("a-test.el" . ,run-ert-test-passing)
                    ("b-tests.el" . "(ert-deftest fixture-fails () (should nil))\n")))
                 1)))

(ert-deftest run-ert-accepts-helpers-and-fixtures ()
  (should (equal (run-ert-test-status
                  `(("a-test.el" . ,run-ert-test-passing)
                    ("helpers/helper.el" . "(provide 'helper)\n")
                    ("fixtures/sample.el" . "(ignore)\n")))
                 0)))

(ert-deftest run-ert-exempts-only-directories-below-the-test-directory ()
  "A test directory whose own path holds helpers/ gets no exemption."
  (let ((root (repo-test-tree
               `(("helpers/suite/a-test.el" . ,run-ert-test-passing)
                 ("helpers/suite/b-tests.el" . "(ert-deftest fixture-fails () (should nil))\n")))))
    (should (equal (car (repo-test-emacs
                         (list "-l" (expand-file-name "tests/run-ert.el" repo-test-root)
                               (expand-file-name "helpers/suite" root))))
                   1))))

(ert-deftest run-ert-fails-on-a-test-expected-to-fail ()
  (should (equal (run-ert-test-status
                  '(("a-test.el" . "(ert-deftest fixture-fails () :expected-result :failed (should nil))\n")))
                 1)))

(ert-deftest run-ert-refuses-a-home-without-the-marker ()
  (should (equal (run-ert-test-status `(("a-test.el" . ,run-ert-test-passing))
                                      (list (concat "HOME=" (make-temp-file "home" t))))
                 2)))

;;; run-ert-test.el ends here

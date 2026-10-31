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
                        environment)))

(defconst run-ert-test-passing
  "(ert-deftest fixture-passes () (should t))\n"
  "A test file whose only test passes.")

(ert-deftest run-ert-passes-when-every-test-passes ()
  (should (equal (run-ert-test-status `(("a-test.el" . ,run-ert-test-passing))) 0)))

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

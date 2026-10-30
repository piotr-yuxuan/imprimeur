;;; commits-test.el --- Tests of the commit-title check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: the check accepts "Add the thing" and rejects a title in
;; lower case, longer than 50 characters, ending with a full stop or
;; holding U+2013, and an attribution trailer (plan 001, acceptance 6).
;; Each test commits one message in a scratch repository and checks it.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(defun commits-test-status (message)
  "Commit MESSAGE on top of a base commit and return the check's status."
  (let ((directory (repo-test-git-tree '(("a" . "a\n")))))
    (repo-test-git directory "commit" "-q" "-m" "Base")
    (repo-test-git directory "commit" "-q" "--allow-empty" "-m" message)
    (car (repo-test-run (expand-file-name "scripts/check-commits" repo-test-root)
                        '("HEAD~1") nil directory))))

(ert-deftest commits-accept-a-good-title ()
  (should (equal (commits-test-status "Add the thing") 0)))

(ert-deftest commits-reject-a-lower-case-title ()
  (should (equal (commits-test-status "add the thing") 1)))

(ert-deftest commits-reject-a-title-of-51-characters ()
  (should (equal (commits-test-status (concat "Add " (make-string 47 ?x))) 1))
  (should (equal (commits-test-status (concat "Add " (make-string 46 ?x))) 0)))

(ert-deftest commits-reject-a-final-full-stop ()
  (should (equal (commits-test-status "Fix it.") 1)))

(ert-deftest commits-reject-an-attribution-trailer ()
  (should (equal (commits-test-status "Add the thing\n\nCo-Authored-By: Someone <a@example.invalid>")
                 1)))

(ert-deftest commits-reject-a-unicode-dash ()
  (should (equal (commits-test-status (concat "Add the thing " (string #x2013) " twice")) 1)))

;;; commits-test.el ends here

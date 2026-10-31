;;; commits-test.el --- Tests of the commit-title check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: the check accepts "Add the thing" and rejects a title in
;; lower case, longer than 50 characters, ending with a full stop or
;; holding U+2013, and an attribution trailer (plan 001, acceptance 6);
;; it also rejects private text in a message, as AGENTS.md requires (the
;; review of plan 001).  Each test commits one message in a scratch
;; repository and checks it.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(defun commits-test-status (message &optional environment author)
  "Commit MESSAGE on top of a base commit and return the check's status.
ENVIRONMENT is added to the check's environment; AUTHOR, when non-nil,
is the commit's author."
  (let ((directory (repo-test-git-tree '(("a" . "a\n")))))
    (repo-test-git directory "commit" "-q" "-m" "Base")
    (apply #'repo-test-git directory "commit" "-q" "--allow-empty" "-m" message
           (and author (list (concat "--author=" author))))
    (car (repo-test-run (expand-file-name "scripts/check-commits" repo-test-root)
                        '("HEAD~1") environment directory))))

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

;; The private path and the address below are assembled at run time, so
;; that this file passes the public check.

(ert-deftest commits-reject-private-text-in-the-body ()
  (should (equal (commits-test-status (concat "Add the thing\n\nSee /" "home/alice/x.")) 1))
  (should (equal (commits-test-status (concat "Add the thing\n\nWrite to someone" "@"
                                              "example.org."))
                 1))
  (should (equal (commits-test-status "Add the thing\n\nWrite to tests@example.invalid.") 0)))

(ert-deftest commits-reject-a-listed-private-word ()
  (let ((list (make-temp-file "private-words" nil nil "Zanzibar\n")))
    (should (equal (commits-test-status "Add the thing\n\nLunch in Zanzibar."
                                        (list (concat "IMPRIMEUR_PRIVATE_WORDS=" list)))
                   1))))

(ert-deftest commits-reject-indented-or-generated-attribution ()
  (should (equal (commits-test-status "Add the thing\n\n  Co-Authored-By: Someone") 1))
  (should (equal (commits-test-status "Add the thing\n\nGenerated with a tool") 1))
  (should (equal (commits-test-status "Add the thing\n\nFixtures generated with pandoc.") 0)))

(ert-deftest commits-reject-a-private-author-address ()
  (should (equal (commits-test-status "Add the thing" nil
                                      (concat "Someone <someone" "@" "example.org>"))
                 1)))

(ert-deftest commits-reject-the-machine-user-name ()
  (should (equal (commits-test-status "Add the thing\n\nAsk alicewonder."
                                      '("IMPRIMEUR_CHECK_USER=alicewonder"))
                 1)))

(ert-deftest commits-reject-a-word-that-begins-with-an-accent ()
  (let ((list (make-temp-file "private-words" nil nil "\u00c9mile\n")))
    (should (equal (commits-test-status "Add the thing\n\nLunch with \u00c9mile."
                                        (list (concat "IMPRIMEUR_PRIVATE_WORDS=" list)))
                   1))))

(ert-deftest commits-reject-every-attribution-trailer-in-any-case ()
  (dolist (trailer '("Co-Authored-By" "Co-authored-by" "CO-AUTHORED-BY" "Signed-off-by"
                     "Signed-Off-By" "Assisted-by" "Assisted-By" "Generated-by" "Generated-By"))
    (should (equal (cons trailer (commits-test-status
                                  (concat "Add the thing\n\n" trailer ": Someone")))
                   (cons trailer 1)))))

;;; commits-test.el ends here

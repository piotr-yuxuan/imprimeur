;;; commits-test.el --- Tests of the commit-title check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: the check accepts "Add the thing" and rejects a title in
;; lower case, longer than 50 characters, ending with a full stop or
;; holding U+2013, and an attribution trailer (plan 001, acceptance 6);
;; it also rejects private text in a message, as AGENTS.md requires (the
;; review of plan 001).  Each test commits one message in a scratch
;; repository and checks it.  Only a branch's tip must pass the other checks
;; before 1.0.0, but this one reads every commit (plan 008, acceptance 7).
;; A version commit, as the pipeline's GitHub writes it, passes by its exact
;; shape, and nothing about it widens the rule for any other commit (plan 030).

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

(ert-deftest commits-read-every-commit-of-the-branch ()
  (let ((directory (repo-test-git-tree '(("a" . "a\n")))))
    (repo-test-git directory "commit" "-q" "-m" "Base")
    (repo-test-git directory "commit" "-q" "--allow-empty" "-m" "Add the first thing")
    (repo-test-git directory "commit" "-q" "--allow-empty" "-m" "add the second thing")
    (repo-test-git directory "commit" "-q" "--allow-empty" "-m" "Add the third thing")
    (should (equal (car (repo-test-run (expand-file-name "scripts/check-commits" repo-test-root)
                                       '("HEAD~3") nil directory))
                   1))))

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

;; The committer's address is assembled at run time, so that this file passes the
;; public check.

(defconst commits-test-github-people
  (list "GIT_AUTHOR_NAME=github-actions[bot]"
        "GIT_AUTHOR_EMAIL=41898282+github-actions[bot]@users.noreply.github.com"
        "GIT_COMMITTER_NAME=GitHub"
        (concat "GIT_COMMITTER_EMAIL=noreply@" "github.com"))
  "The author and committer of a commit made with GitHub's API by the workflow's token.")

(defun commits-test-pipeline-status (message people)
  "Commit MESSAGE as PEOPLE, a list for the environment, and return the check's status."
  (let ((directory (repo-test-git-tree '(("a" . "a\n")))))
    (repo-test-git directory "commit" "-q" "-m" "Base")
    (let ((process-environment (append people process-environment)))
      (repo-test-git directory "commit" "-q" "--allow-empty" "-m" message))
    (car (repo-test-run (expand-file-name "scripts/check-commits" repo-test-root)
                        '("HEAD~1") nil directory))))

(ert-deftest commits-accept-a-version-commit-of-the-pipeline ()
  (dolist (version '("0.0.0" "1.2.3" "10.20.30"))
    (should (equal (commits-test-pipeline-status
                    (format "Version %s\n\n[skip ci]" version) commits-test-github-people)
                   0))))

(ert-deftest commits-reject-github-as-committer-of-anything-else ()
  (dolist (message '("Version 1.2.3" "Add the thing" "Version 1.2\n\n[skip ci]"
                     "Version 01.2.3\n\n[skip ci]" "Version 1.2.3\n\n[skip ci]\n\nMore."))
    (should (equal (cons message (commits-test-pipeline-status message commits-test-github-people))
                   (cons message 1)))))

(ert-deftest commits-reject-another-identity-on-a-version-commit ()
  (should (equal (commits-test-pipeline-status
                  "Version 1.2.3\n\n[skip ci]"
                  (list (concat "GIT_COMMITTER_EMAIL=someone@" "example.org")))
                 1)))

;;; commits-test.el ends here

;;; public-test.el --- Tests of the public-text check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: a missing SPDX line, a Unicode dash, a private path, the
;; machine's user name, an e-mail address, a private word and an input or
;; output call in a Lua filter each make the check exit 1 and name the file
;; and line, whatever the file's encoding; the licence texts and untracked
;; files are exempt; a check that cannot run exits 2 (plan 001, acceptance
;; 2, and its review).  Each test runs scripts/check-public in a scratch git
;; repository.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(defconst public-test-spdx ";; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later\n"
  "The SPDX line, as an Emacs Lisp comment.")

(defconst public-test-dash-line (concat "Licence " (string #x2014) " text.\n")
  "A line holding U+2014, built at load time like the strings below.")

(defconst public-test-program (expand-file-name "scripts/check-public" repo-test-root)
  "The check under test.")

(defun public-test-run (files &optional untracked environment)
  "Run the check in a scratch repository tracking FILES.
UNTRACKED files are written but not added; ENVIRONMENT is added to the
check's environment.  Return (STATUS . OUTPUT)."
  (let ((directory (repo-test-git-tree files)))
    (pcase-dolist (`(,name . ,contents) untracked)
      (with-temp-file (expand-file-name name directory) (insert contents)))
    (repo-test-run public-test-program nil environment directory)))

(defun public-test-finds (files expected &optional environment)
  "Assert that the check of FILES exits 1 and prints EXPECTED.
ENVIRONMENT is added to the check's environment."
  (let ((result (public-test-run files nil environment)))
    (should (equal (car result) 1))
    (should (string-match-p (regexp-quote expected) (cdr result)))))

(ert-deftest public-passes-clean-files ()
  (should (equal (car (public-test-run `(("a.el" . ,(concat public-test-spdx "(ignore)\n"))
                                         ("README.md" . "Mail tests@example.invalid.\n"))))
                 0)))

(ert-deftest public-finds-a-missing-spdx-line ()
  (public-test-finds '(("a.el" . "(ignore)\n")) "a.el:1: missing SPDX line"))

(ert-deftest public-finds-a-dash-but-not-in-the-licence ()
  (public-test-finds `(("LICENSE" . ,public-test-dash-line)
                       ("sub/LICENSE" . ,public-test-dash-line))
                     "sub/LICENSE:1: Unicode dash")
  (should (equal (car (public-test-run `(("LICENSE" . ,public-test-dash-line)))) 0)))

;; The private path and the address below are assembled at run time, so
;; that this file passes the check it tests.

(ert-deftest public-finds-a-private-path-only-when-tracked ()
  (let ((text (concat "A line.\nSee /" "home/alice/x.\n")))
    (public-test-finds `(("notes.md" . ,text)) "notes.md:2: private path")
    (should (equal (car (public-test-run nil `(("notes.md" . ,text)))) 0))))

(ert-deftest public-finds-the-machine-user-name ()
  (public-test-finds '(("notes.md" . "Written by alicewonder.\n"))
                     "notes.md:1: machine user name"
                     '("IMPRIMEUR_CHECK_USER=alicewonder")))

(ert-deftest public-ignores-a-generic-user-name ()
  (should (equal (car (public-test-run '(("notes.md" . "Run by the test runner.\n"))
                                       nil '("IMPRIMEUR_CHECK_USER=runner")))
                 0)))

(ert-deftest public-finds-a-listed-private-word ()
  (let ((list (make-temp-file "private-words" nil nil "# Comment\nZanzibar\n")))
    (public-test-finds '(("notes.md" . "Lunch in Zanzibar.\n"))
                       "notes.md:1: private word"
                       (list (concat "IMPRIMEUR_PRIVATE_WORDS=" list)))))

(ert-deftest public-reads-the-private-words-of-the-primary-checkout ()
  "From a linked worktree, the list in the primary checkout applies."
  (let ((primary (repo-test-git-tree '(("notes.md" . "Lunch in Zanzibar.\n"))))
        (worktree (expand-file-name "worktree" (make-temp-file "public" t))))
    (repo-test-git primary "commit" "-q" "-m" "Base")
    (repo-test-git primary "worktree" "add" "-q" worktree)
    (make-directory (expand-file-name "docs/work" primary) t)
    (with-temp-file (expand-file-name "docs/work/private-words" primary)
      (insert "Zanzibar\n"))
    (let ((result (repo-test-run public-test-program nil nil worktree)))
      (should (equal (car result) 1))
      (should (string-match-p "notes\\.md:1: private word" (cdr result))))))

(ert-deftest public-reads-files-in-any-encoding ()
  "A Latin-1 file is scanned like any other."
  (let ((directory (repo-test-git-tree nil)))
    (let ((coding-system-for-write 'latin-1))
      (with-temp-file (expand-file-name "notes.txt" directory)
        (insert (concat "Caf" (string #xe9) " near /" "home/alice/x.\n"))))
    (repo-test-git directory "add" "-A")
    (let ((result (repo-test-run public-test-program nil nil directory)))
      (should (equal (car result) 1))
      (should (string-match-p "notes\\.txt:1: private path" (cdr result))))))

(ert-deftest public-fails-outside-a-work-tree ()
  (should (equal (car (repo-test-run public-test-program nil nil (make-temp-file "public" t)))
                 2)))

(ert-deftest public-finds-an-e-mail-address ()
  (public-test-finds `(("notes.md" . ,(concat "Write to someone" "@" "example.org.\n")))
                     "notes.md:1: e-mail address"))

(ert-deftest public-finds-input-or-output-in-a-lua-filter ()
  (public-test-finds `(("imprimeur/assets/filters/f.lua"
                        . ,(concat "-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later\n"
                                   "local f = io.open('/etc/hostname')\n")))
                     "imprimeur/assets/filters/f.lua:2: input, output or code loading"))

;;; public-test.el ends here

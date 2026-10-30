;;; public-test.el --- Tests of the public-text check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: a missing SPDX line, a Unicode dash, a private path, the
;; machine's user name, an e-mail address and an input or output call in a
;; Lua filter each make the check exit 1 and name the file and line; the
;; licence texts and untracked files are exempt (plan 001, acceptance 2).
;; Each test runs scripts/check-public in a scratch git repository.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(defconst public-test-spdx ";; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later\n"
  "The SPDX line, as an Emacs Lisp comment.")

(defconst public-test-dash-line (concat "Licence " (string #x2014) " text.\n")
  "A line holding U+2014, built at load time like the strings below.")

(defun public-test-run (files &optional untracked)
  "Run the check in a scratch repository tracking FILES.
UNTRACKED files are written but not added.  Return (STATUS . OUTPUT)."
  (let ((directory (repo-test-git-tree files)))
    (pcase-dolist (`(,name . ,contents) untracked)
      (with-temp-file (expand-file-name name directory) (insert contents)))
    (repo-test-run (expand-file-name "scripts/check-public" repo-test-root) nil nil directory)))

(defun public-test-finds (files expected)
  "Assert that the check of FILES exits 1 and prints EXPECTED."
  (let ((result (public-test-run files)))
    (should (equal (car result) 1))
    (should (string-match-p (regexp-quote expected) (cdr result)))))

(ert-deftest public-passes-clean-files ()
  (should (equal (public-test-run `(("a.el" . ,(concat public-test-spdx "(ignore)\n"))
                                    ("README.md" . "Mail tests@example.invalid.\n")))
                 '(0 . ""))))

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
  (let ((user (user-login-name)))
    (when (or (< (length user) 4)
              (string-match-p "\\`\\(?:root\\|runner\\|nixbld[0-9]*\\|build\\|user\\|admin\\)\\'"
                              user))
      (ert-skip "generic machine user name"))
    (public-test-finds `(("notes.md" . ,(format "Written by %s.\n" user)))
                       "notes.md:1: machine user name")))

(ert-deftest public-finds-an-e-mail-address ()
  (public-test-finds `(("notes.md" . ,(concat "Write to someone" "@" "example.org.\n")))
                     "notes.md:1: e-mail address"))

(ert-deftest public-finds-input-or-output-in-a-lua-filter ()
  (public-test-finds `(("imprimeur/assets/filters/f.lua"
                        . ,(concat "-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later\n"
                                   "local f = io.open('/etc/hostname')\n")))
                     "imprimeur/assets/filters/f.lua:2: input or output call"))

;;; public-test.el ends here

;;; lint.el --- Lint one Emacs Lisp file per Emacs  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Each function takes the file named by the next command-line argument
;; and exits Emacs with status 0 when it is clean, 1 otherwise, after
;; printing the findings as FILE:LINE: MESSAGE.  The Makefile runs one
;; fresh Emacs per file and per check:
;;
;;   emacs -Q --batch -L DIR -l scripts/lint.el -f repo-lint-compile FILE
;;   emacs -Q --batch -l scripts/lint.el -f repo-lint-checkdoc FILE
;;
;; package-lint and relint have batch entry points of their own.  For a skin, which
;; requires imprimeur, `repo-lint-sibling-archive' first makes imprimeur installable.

;;; Code:

(require 'bytecomp)
(require 'checkdoc)
(require 'lisp-mnt)
(require 'package)

(defun repo-lint-compile ()
  "Byte-compile the next command-line argument, warnings being errors.
The compiled file goes to a temporary directory, never beside the
source."
  (let* ((file (pop command-line-args-left))
         (directory (make-temp-file "repo-lint" t))
         (byte-compile-dest-file-function
          (lambda (_source) (expand-file-name "compiled.elc" directory)))
         (byte-compile-error-on-warn t)
         (compiled (byte-compile-file file)))
    (delete-directory directory t)
    (kill-emacs (if compiled 0 1))))

(defun repo-lint-checkdoc ()
  "Run checkdoc on the next command-line argument.
`checkdoc-batch' prints the findings and signals the first one."
  (with-current-buffer (find-file-noselect (pop command-line-args-left))
    (kill-emacs (condition-case nil
                    (progn (checkdoc-batch) 0)
                  (error 1)))))

(defun repo-lint-sibling-archive ()
  "Make an archive under `package-user-dir' that lists imprimeur at its version.
package-lint refuses a dependency that no archive offers, and imprimeur is
in none yet.  Run in a scratch home, from the root of the repository."
  (let ((directory (expand-file-name "archives/sibling" package-user-dir))
        (version (with-temp-buffer
                   (insert-file-contents "imprimeur/imprimeur.el")
                   (version-to-list (lm-version)))))
    (make-directory directory t)
    (write-region (format "%S" `(1 (imprimeur . [,version nil "The sibling." single nil])))
                  nil (expand-file-name "archive-contents" directory) nil 'silent)
    (setq package-archives '(("sibling" . "https://example.invalid/")))))

;;; lint.el ends here

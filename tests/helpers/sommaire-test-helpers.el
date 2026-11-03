;;; sommaire-test-helpers.el --- The fixtures of the tests of sommaire  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Where the fixtures of docs/minitoc-rules.md are and how to read them.
;; They are read with json.el.

;;; Code:

(require 'json)
(require 'seq)
(require 'repo-test-helpers)

(defconst sommaire-test-directory
  (expand-file-name "tests/fixtures/minitoc" repo-test-root)
  "Where the fixtures are.")

(defconst sommaire-test-fixtures
  '(("archive" "org")
    ("chain" "md" "org")
    ("chain-siblings" "md" "org")
    ("comment-noexport" "org")
    ("deep-anchor" "md" "org")
    ("empty" "md" "org")
    ("explicit-table" "org")
    ("later-child" "md" "org")
    ("markdown-toc" "md")
    ("merged-introduction" "md" "org")
    ("narrowing" "md" "org")
    ("normal" "md" "org")
    ("root-introduction" "md" "org")
    ("single-top" "md" "org")
    ("skipped-levels" "md" "org")
    ("untitled" "md" "org"))
  "Each fixture's name, and the extensions of its documents.")

(defun sommaire-test-walked (function)
  "Call FUNCTION, and return how many elements the sequence library walked for it.
That is the total length of the sequences given to the functions below, each
of which walks all of a list before it can stop: `seq-find', `seq-some' and
`seq-every-p' go through `mapc', which measures its list first.  `make check'
reads no clock, so this count stands for the work that grows with a document."
  (let* ((walked 0)
         (functions '(seq-length seq-find seq-some seq-every-p seq-filter))
         (meter (lambda (&rest arguments)
                  (let ((sequence (if (cdr arguments) (nth 1 arguments) (car arguments))))
                    (setq walked (+ walked (length sequence)))))))
    (dolist (walker functions)
      (advice-add walker :before meter))
    (unwind-protect
        (funcall function)
      (dolist (walker functions)
        (advice-remove walker meter)))
    walked))

(defun sommaire-test-insert-text (size)
  "Insert SIZE characters of plain text, in lines of at most 1000 characters."
  (while (> size 0)
    (let ((line (min size 1000)))
      (insert (make-string (1- line) ?a) "\n")
      (setq size (- size line)))))

(defun sommaire-test-read (name part)
  "Return PART of the fixture NAME, as the rules hold it."
  (let ((json-object-type 'plist) (json-array-type 'list)
        (json-false nil) (json-null nil))
    (json-read-file (expand-file-name (format "%s.%s.json" name part)
                                      sommaire-test-directory))))

(defun sommaire-test-documents (extension)
  "Return the names of the fixtures that have a document of EXTENSION."
  (mapcar #'car (seq-filter (lambda (fixture) (member extension (cdr fixture)))
                            sommaire-test-fixtures)))

(defun sommaire-test-insert (name extension)
  "Insert the document of the fixture NAME with EXTENSION in this buffer.
Leave point at its start."
  (insert-file-contents (expand-file-name (format "%s.%s" name extension)
                                          sommaire-test-directory))
  (goto-char (point-min)))

(defun sommaire-test-narrow-to-usage (mark)
  "Narrow this buffer as the fixture `narrowing' states.
That is the subtree of the heading \"Usage\", up to the heading \"Notes\",
whose lines start with the regexp MARK."
  (goto-char (point-min))
  (re-search-forward (format "^%s Usage$" mark))
  (let ((begin (pos-bol)))
    (re-search-forward (format "^%s Notes$" mark))
    (narrow-to-region begin (pos-bol))
    (goto-char (point-min))))

(provide 'sommaire-test-helpers)

;;; sommaire-test-helpers.el ends here

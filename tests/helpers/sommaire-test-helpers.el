;;; sommaire-test-helpers.el --- The fixtures of the tests of sommaire  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Where the fixtures of docs/minitoc-rules.md are and how to read them.
;; They are read with json.el, since the minimum Emacs is 29.1.

;;; Code:

(require 'json)
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

(defun sommaire-test-read (name part)
  "Return PART of the fixture NAME, as the rules hold it."
  (let ((json-object-type 'plist) (json-array-type 'list)
        (json-false nil) (json-null nil))
    (json-read-file (expand-file-name (format "%s.%s.json" name part)
                                      sommaire-test-directory))))

(provide 'sommaire-test-helpers)

;;; sommaire-test-helpers.el ends here

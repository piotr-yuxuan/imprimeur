;;; check-docs-test.el --- Tests of the documentation's check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement (plan 028): in `make check', every relative link in the Markdown
;; resolves, and every defcustom, command and key of the packages appears in the
;; reference.  Each test runs the check in a scratch git repository that holds the
;; reference as it stands, less its links and what the test removes.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'check-docs (expand-file-name "scripts/check-docs.el" repo-test-root))

(defun check-docs-test-reference ()
  "Return the reference pages as an alist for `repo-test-git-tree', without their links.
Those lead to pages that a scratch repository does not hold."
  (mapcar (lambda (page)
            (cons page (with-temp-buffer
                         (insert-file-contents (expand-file-name page repo-test-root))
                         (replace-regexp-in-string "\\](\\([^() \t\n]+\\))" "]" (buffer-string) t t))))
          '("docs/reference/options.md" "docs/reference/commands-and-keys.md"
            "docs/reference/skin-api.md")))

(defun check-docs-test-run (files)
  "Run the check in a scratch git repository tracking FILES; return (STATUS . OUTPUT)."
  (repo-test-emacs
   (append (mapcan (lambda (directory)
                     (list "-L" (expand-file-name directory repo-test-root)))
                   (cons "sommaire" (cons "imprimeur" (file-expand-wildcards
                                                       (expand-file-name "imprimeur-skin-*" repo-test-root)))))
           (list "-l" (expand-file-name "scripts/check-docs.el" repo-test-root)
                 "-f" "check-docs-batch"))
   nil (repo-test-git-tree files)))

(ert-deftest check-docs-passes-the-reference-as-it-stands ()
  (let ((result (check-docs-test-run (check-docs-test-reference))))
    (should (equal result (cons 0 "")))))

(ert-deftest check-docs-fails-on-a-defcustom-removed-from-the-reference ()
  (let* ((pages (check-docs-test-reference))
         (result (check-docs-test-run
                  (cons (cons "docs/reference/options.md"
                              (string-replace "`imprimeur-render-timeout`" "a timeout"
                                              (cdr (assoc "docs/reference/options.md" pages))))
                        (assoc-delete-all "docs/reference/options.md" pages)))))
    (should (equal (car result) 1))
    (should (string-search "docs/reference/options.md:1: no code span of imprimeur-render-timeout"
                           (cdr result)))))

(ert-deftest check-docs-fails-on-a-command-or-a-key-removed-from-the-reference ()
  (let* ((pages (check-docs-test-reference))
         (result (check-docs-test-run
                  (cons (cons "docs/reference/commands-and-keys.md"
                              (string-replace
                               "`M-g m`" "a key"
                               (string-replace "`imprimeur-copy-url`" "a command"
                                               (cdr (assoc "docs/reference/commands-and-keys.md" pages)))))
                        (assoc-delete-all "docs/reference/commands-and-keys.md" pages)))))
    (should (equal (car result) 1))
    (should (string-search "no code span of imprimeur-copy-url" (cdr result)))
    (should (string-search "no code span of M-g m" (cdr result)))))

(ert-deftest check-docs-fails-on-a-manifest-key-removed-from-the-api ()
  (let* ((pages (check-docs-test-reference))
         (result (check-docs-test-run
                  (cons (cons "docs/reference/skin-api.md"
                              (string-replace "`:notes`" "notes" (cdr (assoc "docs/reference/skin-api.md" pages))))
                        (assoc-delete-all "docs/reference/skin-api.md" pages)))))
    (should (equal (car result) 1))
    (should (string-search "no code span of :notes" (cdr result)))))

(ert-deftest check-docs-judges-each-link ()
  (let ((result (check-docs-test-run
                 (append
                  (check-docs-test-reference)
                  '(("README.md" . "[here](README.md)\n[gone](gone.md)\n\n## A heading's name\n\n[good](#a-headings-name) [bad](#another)\n[page](docs/page.md#top) [wrong](docs/page.md#other) [dir](docs)\n<img src=\"gone.png\">\n\n`[code](gone.md)`\n\n```\n[fence](gone.md)\n```\n\n[web](https://example.invalid/gone.md)\n")
                    ("docs/page.md" . "# Top\n\n[back](../README.md) [wrong](README.md)\n")
                    ("tests/fixture.md" . "[hostile](gone.md)\n"))))))
    (should (equal (car result) 1))
    (should (equal (sort (split-string (cdr result) "\n" t))
                   (sort (list "README.md:2: no tracked file at gone.md"
                               "README.md:6: no anchor for #another"
                               "README.md:7: no anchor for docs/page.md#other"
                               "README.md:8: no tracked file at gone.png"
                               "docs/page.md:3: no tracked file at README.md"))))))

(ert-deftest check-docs-slugs-as-github-does ()
  (dolist (entry '(("Your first preview" . "your-first-preview")
                   ("sommaire's commands" . "sommaires-commands")
                   ("`imprimeur-skin-define`" . "imprimeur-skin-define")
                   ("What folds and following do" . "what-folds-and-following-do")
                   ("Écrivain, à la main" . "écrivain-à-la-main")
                   ("One  two" . "one--two")))
    (should (equal (check-docs-slug (car entry)) (cdr entry)))))

;;; check-docs-test.el ends here

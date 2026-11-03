;;; check-docs-test.el --- Tests of the documentation's check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement (plan 028): in `make check', every relative link in the Markdown
;; resolves, and every defcustom, command and key of the packages appears in the
;; reference.  What judges a tree runs the check in a scratch git repository; the reference's
;; holds that reference as it stands, less what the test removes.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'check-docs (expand-file-name "scripts/check-docs.el" repo-test-root))

(defun check-docs-test-reference ()
  "Return the reference pages as they stand, as an alist for `repo-test-git-tree'."
  (mapcar (lambda (page)
            (cons page (with-temp-buffer
                         (insert-file-contents (expand-file-name page repo-test-root))
                         (buffer-string))))
          '("docs/reference/options.md" "docs/reference/commands-and-keys.md"
            "docs/reference/skin-api.md")))

(defun check-docs-test-run (function files)
  "Run the check FUNCTION in a scratch git repository tracking FILES.
Return (STATUS . OUTPUT)."
  (repo-test-emacs
   (append (mapcan (lambda (directory)
                     (list "-L" (expand-file-name directory repo-test-root)))
                   (cons "sommaire" (cons "imprimeur" (file-expand-wildcards
                                                       (expand-file-name "imprimeur-skin-*" repo-test-root)))))
           (list "-l" (expand-file-name "scripts/check-docs.el" repo-test-root)
                 "-f" function))
   nil (repo-test-git-tree files)))

(defun check-docs-test-without (page text)
  "Run the reference's check, with TEXT, a code span, gone from PAGE."
  (let ((pages (check-docs-test-reference)))
    (check-docs-test-run
     "check-docs-batch-reference"
     (cons (cons page (string-replace text "gone" (cdr (assoc page pages))))
           (assoc-delete-all page pages)))))

(ert-deftest check-docs-passes-the-reference-as-it-stands ()
  (should (equal (check-docs-test-run "check-docs-batch-reference" (check-docs-test-reference))
                 (cons 0 ""))))

(ert-deftest check-docs-fails-on-what-the-reference-lost ()
  (pcase-dolist (`(,page ,span ,message)
                 '(("docs/reference/options.md" "`imprimeur-render-timeout`"
                    "docs/reference/options.md:1: no code span of imprimeur-render-timeout")
                   ("docs/reference/options.md" "`sommaire-button`"
                    "no code span of sommaire-button")
                   ("docs/reference/commands-and-keys.md" "`imprimeur-copy-url`"
                    "no code span of imprimeur-copy-url")
                   ("docs/reference/commands-and-keys.md" "`M-g m`"
                    "no code span of M-g m")
                   ("docs/reference/commands-and-keys.md" "`S-SPC`"
                    "no code span of S-SPC")
                   ("docs/reference/skin-api.md" "`:notes`"
                    "no code span of :notes")))
    (ert-info (span)
      (let ((result (check-docs-test-without page span)))
        (should (equal (car result) 1))
        (should (string-search message (cdr result)))))))

(ert-deftest check-docs-judges-a-link-by-a-table ()
  (let ((tracked '("README.md" "docs/page.md" "docs/images/a.png"))
        (anchors (lambda (name) (and (equal name "docs/page.md") '("top")))))
    (pcase-dolist (`(,file ,target ,expected)
                   '(("README.md" "docs/page.md" nil)
                     ("README.md" "docs/images/a.png" nil)
                     ("README.md" "docs" nil)
                     ("README.md" "docs/images/" nil)
                     ("README.md" "docs/page.md#top" nil)
                     ("docs/page.md" "#top" nil)
                     ("docs/page.md" "../README.md" nil)
                     ("README.md" "https://example.invalid/gone.md" nil)
                     ("README.md" "mailto:a@example.invalid" nil)
                     ("README.md" "docs/images/a.png#anything" nil)
                     ("README.md" "gone.md" "no tracked file at gone.md")
                     ("docs/page.md" "README.md" "no tracked file at README.md")
                     ("README.md" "doc" "no tracked file at doc")
                     ("README.md" "docs/page.md#other" "no anchor for docs/page.md#other")
                     ("docs/page.md" "#other" "no anchor for #other")))
      (ert-info ((concat file " to " target))
        (should (equal (check-docs-link-problem file target tracked anchors) expected))))))

(ert-deftest check-docs-reads-links-outside-code ()
  (should (equal (check-docs-links
                  "[a](one.md)\n`[b](two.md)`\n```\n[c](three.md)\n```\n![d](four.png)\n<img alt=\"e\" src=\"five.png\">\n<source srcset=\"six.png\">\n")
                 '((1 . "one.md") (6 . "four.png") (7 . "five.png") (8 . "six.png")))))

(ert-deftest check-docs-numbers-repeated-anchors ()
  (should (equal (sort (check-docs-anchors "# One\n\n```\n# Not one\n```\n\n## One\n<a id=\"here\"></a>\n"))
                 '("here" "one" "one-1"))))

(ert-deftest check-docs-judges-each-link-of-a-tree ()
  (let ((result (check-docs-test-run
                 "check-docs-batch-links"
                 '(("README.md" . "[here](README.md)\n[gone](gone.md)\n\n## A heading's name\n\n[good](#a-headings-name) [bad](#another)\n[page](docs/page.md#top) [wrong](docs/page.md#other) [dir](docs)\n<img src=\"gone.png\">\n\n`[code](gone.md)`\n\n```\n[fence](gone.md)\n```\n\n[web](https://example.invalid/gone.md)\n")
                   ("docs/page.md" . "# Top\n\n[back](../README.md) [wrong](README.md)\n")
                   ("tests/fixture.md" . "[hostile](gone.md)\n")
                   ("imprimeur/assets/vendor/x/README.md" . "[theirs](gone.md)\n")))))
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
                   ("See [the rules](rules.md) here" . "see-the-rules-here")
                   ("One  two" . "one--two")))
    (should (equal (check-docs-slug (car entry)) (cdr entry)))))

;;; check-docs-test.el ends here

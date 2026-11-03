;;; check-docs-test.el --- Tests of the documentation's check  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement (plan 028): in `make check', every relative link in the Markdown
;; resolves, and every defcustom, command and key of the packages appears in the
;; reference.  What judges a tree runs the check in a scratch git repository; the reference's
;; holds that reference as it stands, less what the test removes.  Requirement (plan 028,
;; part B): the Chinese READMEs hold the same sections, code blocks, pictures and links as
;; README.md, the three link to each other, and neither translation holds the other
;; region's words, nor the traditional one a place's name.  What judges the whole READMEs
;; takes them as they stand, with one change each.

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

(defconst check-docs-test-english
  "# Name\n\nEnglish · [a](README.zh-Hant.md) · [b](README.zh-Hans.md)\n\n<img src=\"p.png\"> [page](docs/page.md)\n\n## One\n\n```sh\nmake\n\n# not a heading\n```\n\n### Two\n\n```elisp\n(a)\n```\n\n## Three\n\nRun `a`.\n\n## Four\n\nRun `b` and `d`.\n"
  "An English README, whose translation below keeps all that it must.")

(defconst check-docs-test-translation
  "<div lang=\"zh-TW\">\n\n# Name\n\n[English](README.md) · 繁體中文 · [b](README.zh-Hans.md)\n\n譯自 `abc1234`。\n\n<img alt=\"圖\" src=\"p.png\"> [頁](docs/page.md)\n\n## 一\n\n```sh\nmake\n\n# not a heading\n```\n\n### 二\n\n```elisp\n(a)\n```\n\n## 三\n\n執行 `a`。\n\n## 四\n\n執行 `b` 與 `d`。\n\n</div>\n"
  "A faithful translation of `check-docs-test-english'.")

(defun check-docs-test-problems (from to)
  "Return the findings on the translation with the string FROM replaced by TO."
  (should (string-search from check-docs-test-translation))
  (check-docs-translation-problems "README.zh-Hant.md"
                                   (string-replace from to check-docs-test-translation)
                                   check-docs-test-english
                                   '("臺灣" "窗口")))

(ert-deftest check-docs-judges-a-translation-by-a-table ()
  (should-not (check-docs-test-problems "## 一" "## 一"))
  ;; A sentence may hold its code spans in its own order.
  (should-not (check-docs-test-problems "`b` 與 `d`" "`d` 與 `b`"))
  (pcase-dolist (`(,from ,to ,expected)
                 '(("## 一\n\n" "" "sections differ from the English, at number 2: (3), not (2)")
                   ("### 二" "## 二" "sections differ from the English, at number 3: (2), not (3)")
                   ("</div>" "## 五\n\n</div>" "sections differ from the English, at number 6: (2), not nil")
                   ("## 三\n\n執行 `a`。\n\n## 四\n\n執行 `b` 與 `d`。" "## 四\n\n執行 `b` 與 `d`。\n\n## 三\n\n執行 `a`。"
                    "sections differ from the English, at number 4")
                   ("`a`" "`c`" "sections differ from the English, at number 4")
                   ("(a)" "(b)" "lines of code blocks differ from the English, at number 7: \"(b)\", not \"(a)\"")
                   ("make\n\n#" "make\n#" "lines of code blocks differ from the English, at number 3")
                   ("(a)" "(a) " "lines of code blocks differ")
                   ("```elisp" "```el" "lines of code blocks differ")
                   ("```elisp\n(a)\n```\n\n" "" "lines of code blocks differ")
                   ("p.png" "q.png" "links and pictures differ from the English, at number 1: \"q.png\", not \"p.png\"")
                   ("docs/page.md" "docs/zh/page.md" "links and pictures differ")
                   ("<img alt=\"圖\" src=\"p.png\"> " "" "links and pictures differ")
                   ("[English](README.md) · " "" "its first two links are not to README.md and README.zh-Hans.md")
                   ("[b](README.zh-Hans.md)" "简体中文" "its first two links are not to")
                   ("`abc1234`" "英文版" "it names no English commit in a code span")
                   ("譯自" "臺灣" "it holds 臺灣")
                   ("譯自" "窗口" "it holds 窗口")))
    (ert-info ((concat from " to " to))
      (let ((problems (check-docs-test-problems from to)))
        (should (seq-some (lambda (problem) (string-search expected problem)) problems))
        (should (seq-every-p (lambda (problem) (string-prefix-p "README.zh-Hant.md:1: " problem))
                             problems))))))

(ert-deftest check-docs-allows-a-forbidden-word-in-a-code-block ()
  ;; The code blocks are the English ones, which no list of words judges.
  (should-not (check-docs-translation-problems
               "README.zh-Hant.md"
               (string-replace "(a)" "(臺灣)" check-docs-test-translation)
               (string-replace "(a)" "(臺灣)" check-docs-test-english)
               '("臺灣"))))

(ert-deftest check-docs-judges-a-readme-s-language-links-by-a-table ()
  (pcase-dolist (`(,file ,text ,fails)
                 '(("README.md" "[繁](README.zh-Hant.md) [简](README.zh-Hans.md) [c](d.md)" nil)
                   ("README.md" "[简](README.zh-Hans.md) [繁](README.zh-Hant.md)" nil)
                   ("README.md" "[c](d.md) [繁](README.zh-Hant.md) [简](README.zh-Hans.md)" t)
                   ("README.md" "[繁](README.zh-Hant.md)" t)
                   ("README.zh-Hans.md" "[e](README.md) [繁](README.zh-Hant.md)" nil)
                   ("README.zh-Hans.md" "[繁](README.zh-Hant.md) [简](README.zh-Hans.md)" t)))
    (ert-info ((concat file ": " text))
      (should (eq (and (check-docs-language-problem file text) t) fails)))))

(defun check-docs-test-translations (file from to)
  "Run the translations' check on the READMEs as they stand, FROM to TO in FILE.
FROM must be there."
  (let* ((readmes (mapcar (lambda (readme)
                            (cons readme (with-temp-buffer
                                           (let ((coding-system-for-read 'utf-8))
                                             (insert-file-contents (expand-file-name readme repo-test-root)))
                                           (buffer-string))))
                          check-docs-readmes))
         (text (cdr (assoc file readmes)))
         (coding-system-for-write 'utf-8))
    (should (string-search from text))
    (setcdr (assoc file readmes) (string-replace from to text))
    (check-docs-test-run "check-docs-batch-translations" readmes)))

(ert-deftest check-docs-passes-the-translations-as-they-stand ()
  (should (equal (check-docs-test-translations "README.md" "# imprimeur" "# imprimeur")
                 (cons 0 ""))))

(ert-deftest check-docs-fails-on-what-a-translation-lost ()
  (pcase-dolist (`(,file ,from ,to ,message)
                 '(("README.zh-Hant.md" "### 先試 xwidgets" "## 先試 xwidgets"
                    "README.zh-Hant.md:1: sections differ")
                   ("README.zh-Hans.md" "### 先试用 xwidgets\n\n" ""
                    "README.zh-Hans.md:1: sections differ")
                   ("README.md" "## Security" "## Security\n\n## Another"
                    "README.zh-Hant.md:1: sections differ")
                   ("README.zh-Hant.md" "(imprimeur-render-delay 0.3)" "(imprimeur-render-delay 0.4)"
                    "README.zh-Hant.md:1: lines of code blocks differ")
                   ("README.zh-Hans.md" ";; Seconds of quiet" ";; 静默的秒数"
                    "README.zh-Hans.md:1: lines of code blocks differ")
                   ("README.md" "make smoke-xwidget\n```" "make check\n```"
                    "README.zh-Hans.md:1: lines of code blocks differ")
                   ("README.zh-Hant.md" "docs/images/gallery/xix.png" "docs/images/gallery/xvii.png"
                    "README.zh-Hant.md:1: links and pictures differ")
                   ("README.zh-Hans.md" "docs/reference/options.md" "docs/zh/options.md"
                    "README.zh-Hans.md:1: links and pictures differ")
                   ("README.zh-Hant.md" "[简体中文](README.zh-Hans.md)" "简体中文"
                    "README.zh-Hant.md:1: its first two links")
                   ("README.md" "[简体中文](README.zh-Hans.md)" "简体中文"
                    "README.md:1: its first two links")
                   ("README.zh-Hant.md" "教育部標準宋體" "民國教育部標準宋體"
                    "README.zh-Hant.md:1: it holds")
                   ("README.zh-Hant.md" "桌面視窗" "桌面窗口"
                    "README.zh-Hant.md:1: it holds")
                   ("README.zh-Hans.md" "桌面窗口" "桌面视窗"
                    "README.zh-Hans.md:1: it holds")))
    (ert-info ((concat file ": " from " to " to))
      (let ((result (check-docs-test-translations file from to)))
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

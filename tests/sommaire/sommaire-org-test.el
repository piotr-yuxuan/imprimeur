;;; sommaire-org-test.el --- The Org adapter of sommaire  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: docs/minitoc-rules.md, "What an adapter puts in the tree", R2,
;; R4, R5 and R6, and plan 005: for every fixture in Org, the adapter's model
;; equals NAME.model.json; the outline is cached per modification tick; a
;; document that Org cannot parse breaks nothing.  The expectations come from
;; those rules, and each document below is written by hand from them.  A title
;; reads as it is displayed, which pandoc judges too, since a page shows what
;; pandoc rendered (plan 008, "Titles as they read", with acceptance 6).

;;; Code:

(require 'ert)
(require 'seq)
(require 'repo-test-helpers)
(require 'sommaire-test-helpers)
(require 'sommaire-org)

(defvar org-export-exclude-tags)

(defmacro sommaire-org-test--with-document (text &rest body)
  "Run BODY in an Org buffer holding TEXT, with point at its start."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,text)
     (org-mode)
     (goto-char (point-min))
     ,@body))

(defun sommaire-org-test--root ()
  "Return the root of this buffer's model."
  (plist-get (plist-get (sommaire-org-outline) :model) :root))

(defun sommaire-org-test--root-of (text)
  "Return the root of the model of an Org buffer holding TEXT."
  (sommaire-org-test--with-document text (sommaire-org-test--root)))

(defun sommaire-org-test--titles (node)
  "Return the titles of the children of NODE."
  (mapcar (lambda (child) (plist-get child :title)) (plist-get node :children)))

(defun sommaire-org-test--first-child (text)
  "Return the first child of the root of the model of TEXT."
  (car (plist-get (sommaire-org-test--root-of text) :children)))

(defun sommaire-org-test--narrowed-root (text from to)
  "Return the root of TEXT narrowed from the text FROM up to the text TO.
FROM and TO are searched for from the start; a nil TO means the end."
  (sommaire-org-test--with-document text
    (let ((begin (progn (search-forward from) (match-beginning 0)))
          (end (if to
                   (progn (search-forward to) (match-beginning 0))
                 (point-max))))
      (narrow-to-region begin end)
      (sommaire-org-test--root))))

(ert-deftest sommaire-org-model-of-every-fixture ()
  "For every fixture in Org, the adapter's model equals NAME.model.json."
  (should (sommaire-test-documents "org"))
  (dolist (name (sommaire-test-documents "org"))
    (ert-info (name)
      (with-temp-buffer
        (sommaire-test-insert name "org")
        (org-mode)
        (when (equal name "narrowing")
          (sommaire-test-narrow-to-usage "\\*"))
        (should (equal (plist-get (sommaire-org-outline) :model)
                       (sommaire-test-read name "model")))))))

(ert-deftest sommaire-org-introduction ()
  "What lies between a heading's metadata and its first child, by kind of element."
  (pcase-dolist (`(,body . ,intro)
                 '(("" . nil)
                   ("\n\n" . nil)
                   ("DEADLINE: <2026-11-02 Mon>\n" . nil)
                   (":PROPERTIES:\n:X: y\n:END:\n" . nil)
                   (":LOGBOOK:\n- A note\n:END:\n" . nil)
                   ("#+html: <a id=\"x\"></a>\n" . nil)
                   ("#+TOC: headlines 1 local\n" . nil)
                   ("#+TOC: headlines 1\n" . nil)
                   ("# A comment\n" . nil)
                   ("#+begin_comment\nA comment\n#+end_comment\n" . nil)
                   ("A paragraph.\n" . t)
                   ("- An item\n" . t)
                   ("| A | table |\n" . t)
                   ("#+begin_src sh\ntrue\n#+end_src\n" . t)
                   ("#+begin_quote\nA quote\n#+end_quote\n" . t)
                   (": Fixed width\n" . t)
                   ("-----\n" . t)
                   ("[fn:1] A note\n" . t)
                   ("DEADLINE: <2026-11-02 Mon>\nThen a paragraph.\n" . t)
                   ("# A comment\n\nThen a paragraph.\n" . t)))
    (ert-info (body)
      (should (eq (plist-get (sommaire-org-test--first-child
                              (concat "* A\n" body "** B\n** C\n"))
                             :intro)
                  intro)))))

(ert-deftest sommaire-org-introduction-of-the-root ()
  "The root's span starts where the document starts, and ends at its first child."
  (should-not (plist-get (sommaire-org-test--root-of "#+title: T\n# Comment\n\n* A\nText\n")
                         :intro))
  (should (plist-get (sommaire-org-test--root-of "#+title: T\n\nText\n\n* A\n") :intro))
  (should (plist-get (sommaire-org-test--root-of "Only text\n") :intro))
  (should (plist-get (sommaire-org-test--root-of "* COMMENT Dropped\n* A\n") :intro))
  (should-not (plist-get (sommaire-org-test--root-of "* A\n* COMMENT Dropped\n") :intro)))

(ert-deftest sommaire-org-dropped-subtree-as-an-introduction ()
  "In a buffer, a dropped subtree before a heading's first child is visible text."
  (pcase-dolist (`(,text ,a ,b)
                 '(;; Before the first child, it is A's.
                   ("* A\n** COMMENT Dropped\n** B\n" t nil)
                   ("* A\n** Dropped :noexport:\n** B\n" t nil)
                   ("* A\n*** COMMENT Deeper than the child\n** B\n" t nil)
                   ;; After the first child, it belongs to no one's span.
                   ("* A\n** B\n** COMMENT Dropped\n" nil nil)
                   ("* A\n** B\n*** C\n** COMMENT Dropped\n" nil nil)
                   ;; Under the child and before its own first child, it is the child's.
                   ("* A\n** B\n*** COMMENT Dropped\n*** C\n" nil t)
                   ;; A leaf's span runs to the end of its subtree.
                   ("* A\n** B\n*** COMMENT Dropped\n" nil t)
                   ;; A toc-org container is an explicit table, not an introduction.
                   ("* A\n** Contents :TOC:\n- A link\n** B\n" nil nil)))
    (ert-info (text)
      (let ((node (sommaire-org-test--first-child text)))
        (should (equal (sommaire-org-test--titles node) '("B")))
        (should (eq (plist-get node :intro) a))
        (should (eq (plist-get (car (plist-get node :children)) :intro) b)))))
  (ert-info ("a leaf whose only child is dropped")
    (should (plist-get (sommaire-org-test--first-child "* A\n** COMMENT Dropped\n* B\n")
                       :intro))))

(ert-deftest sommaire-org-explicit-tables ()
  "R2: what makes a heading explicit, and what does not."
  (pcase-dolist (`(,body . ,explicit)
                 '(("#+TOC: headlines 1 local\n" . t)
                   ("#+TOC: headlines local\n" . t)
                   ("#+toc: headlines 2 local\n" . t)
                   (":CONTENTS:\n- A link\n:END:\n" . t)
                   ("#+TOC: headlines 1\n" . nil)
                   ("#+TOC: tables local\n" . nil)
                   ("#+TOC: listings\n" . nil)
                   ("#+html: headlines local\n" . nil)
                   (":LOGBOOK:\n- A note\n:END:\n" . nil)
                   ("#+begin_src org\n#+TOC: headlines 1 local\n#+end_src\n" . nil)))
    (ert-info (body)
      (should (eq (plist-get (sommaire-org-test--first-child (concat "* A\n" body "** B\n** C\n"))
                             :explicit)
                  explicit))))
  (ert-info ("a table in the first section belongs to the root")
    (let ((root (sommaire-org-test--root-of "#+TOC: headlines 1 local\n\n* A\n")))
      (should (plist-get root :explicit))
      (should-not (plist-get (car (plist-get root :children)) :explicit))))
  (ert-info ("a table in a dropped subtree belongs to no one")
    (let ((node (sommaire-org-test--first-child
                 "* A\n** COMMENT Dropped\n#+TOC: headlines 1 local\n** B\n")))
      (should-not (plist-get node :explicit)))))

(ert-deftest sommaire-org-toc-org-containers ()
  "A heading with a toc-org tag is dropped, and makes the root explicit, wherever it is."
  (dolist (tags '(":TOC:" ":toc:" ":TOC_2:" ":TOC@2:" ":TOC_2_gh:" ":TOC@2@org:"
                  ":TOC:noexport:" ":other:TOC:" ":TOC_3:QUOTE:"))
    (ert-info (tags)
      (let ((root (sommaire-org-test--root-of
                   (format "* A\n** Contents %s\n- A link\n** B\n* C\n" tags))))
        (should (eq (plist-get root :explicit) t))
        (should-not (plist-get root :intro))
        (should (equal (sommaire-org-test--titles root) '("A" "C")))
        (should (equal (sommaire-org-test--titles (car (plist-get root :children))) '("B")))
        ;; At the root only: R2 would take the inline minitoc from the heading above it.
        (should-not (plist-get (car (plist-get root :children)) :explicit)))))
  (dolist (tags '(":TOCK:" ":MYTOC:" ":TOC_x:" ":TOC_:" ":TOC_22:"))
    (ert-info (tags)
      (let ((root (sommaire-org-test--root-of (format "* Contents %s\n* C\n" tags))))
        (should-not (plist-get root :explicit))
        (should (equal (sommaire-org-test--titles root) '("Contents" "C")))))))

(ert-deftest sommaire-org-eligibility ()
  "What is dropped with its subtree, and what is not."
  (pcase-dolist (`(,text . ,titles)
                 '(("* A\n* COMMENT Dropped\n** Gone\n* B\n" . ("A" "B"))
                   ("* A\n* Dropped :noexport:\n** Gone\n* B\n" . ("A" "B"))
                   ("* A\n* Dropped :x:noexport:\n* B\n" . ("A" "B"))
                   ("* A\n* Dropped\n:PROPERTIES:\n:UNNUMBERED: notoc\n:END:\n** Gone\n* B\n" . ("A" "B"))
                   ;; Only the value notoc drops a heading.
                   ("* A\n:PROPERTIES:\n:UNNUMBERED: t\n:END:\n* B\n" . ("A" "B"))
                   ;; A heading in code is none.
                   ("#+begin_src org\n,* Not a heading\n#+end_src\n* A\n" . ("A"))
                   ;; The word COMMENT must be the keyword.
                   ("* Comments on the thing\n" . ("Comments on the thing"))))
    (ert-info (text)
      (should (equal (sommaire-org-test--titles (sommaire-org-test--root-of text)) titles)))))

(ert-deftest sommaire-org-eligibility-reads-the-exclude-tags ()
  "The tags that drop a heading are those of `org-export-exclude-tags'."
  (let ((org-export-exclude-tags '("private")))
    (should (equal (sommaire-org-test--titles
                    (sommaire-org-test--root-of "* A :private:\n* B :noexport:\n"))
                   '("B")))))

(ert-deftest sommaire-org-needs-no-exporter ()
  "Without ox, whose variable it is, the default of `org-export-exclude-tags' holds."
  (should (equal (repo-test-emacs
                  (list "-L" (expand-file-name "sommaire" repo-test-root)
                        "-l" "sommaire-org"
                        "--eval"
                        (concat "(with-temp-buffer"
                                " (insert \"* A :noexport:\\n* B\\n\")"
                                " (org-mode)"
                                " (prin1 (list (featurep 'ox)"
                                " (plist-get (car (plist-get (plist-get (plist-get"
                                " (sommaire-org-outline) :model) :root) :children)) :title))))")))
                 '(0 . "(nil \"B\")"))))

(ert-deftest sommaire-org-archived-headings ()
  "An archived heading is listed as a leaf, and its body and descendants are not read."
  (let ((node (sommaire-org-test--first-child
               "* A :ARCHIVE:\nText\n#+TOC: headlines 1 local\n** B\n** C\n* D\n")))
    (should (equal (plist-get node :title) "A"))
    (should (eq (plist-get node :archived) t))
    (should-not (plist-get node :intro))
    (should-not (plist-get node :explicit))
    (should-not (plist-get node :children)))
  (ert-info ("the tag is case-sensitive, as in Org")
    (should-not (plist-get (sommaire-org-test--first-child "* A :archive:\n") :archived))))

(ert-deftest sommaire-org-heading-titles ()
  "A title is the heading's text without keyword, priority, tags and cookies."
  (pcase-dolist (`(,heading . ,title)
                 '(("* Plain" . "Plain")
                   ("* TODO Keyword" . "Keyword")
                   ("* DONE [#B] Priority" . "Priority")
                   ("* Tags :a:b:" . "Tags")
                   ("* Fraction [1/2]" . "Fraction")
                   ("* Percent [50%]" . "Percent")
                   ("* [/] Empty cookies [%]" . "Empty cookies")
                   ("* Inner [1/2] cookie" . "Inner cookie")
                   ("* TODO [#A] All [1/2] :tag:" . "All")
                   ("* Not a [cookie]" . "Not a [cookie]")
                   ("* Not a [1/2/3] cookie" . "Not a [1/2/3] cookie")
                   ("* 100% done" . "100% done")
                   ;; A priority is the cookie right after the keyword, or at the start.
                   ("* [#A] No keyword" . "No keyword")
                   ("* [#A]Stuck" . "Stuck")
                   ("* [#A]" . "")
                   ("* [#a] A small letter" . "A small letter")
                   ("* [#7] A digit" . "A digit")
                   ("* [#10] Two digits" . "Two digits")
                   ("* TODO [#10] Two digits" . "Two digits")
                   ;; Anywhere else, or of another shape, it stays in the title.
                   ("* Fix bug [#B]" . "Fix bug [#B]")
                   ("* Rate [#A] items" . "Rate [#A] items")
                   ("* TODO Rate [#A] items" . "Rate [#A] items")
                   ("* TODO [#A] [#B] Two cookies" . "[#B] Two cookies")
                   ("* [#A] [#B] Two cookies" . "[#B] Two cookies")
                   ("* [#100] Three digits" . "[#100] Three digits")
                   ("* [#AB] Two letters" . "[#AB] Two letters")
                   ("* [#!] A mark" . "[#!] A mark")
                   ("* [#] Nothing" . "[#] Nothing")
                   ;; A keyword is a whole word at the start, in its own case.
                   ("* TODO" . "")
                   ("* TODO :tag:" . "")
                   ("* DONE [#A]" . "")
                   ("* TODOS are a word" . "TODOS are a word")
                   ("* todo in small letters" . "todo in small letters")
                   ("* TODO\tafter a tab" . "TODO after a tab")
                   ("* Later TODO" . "Later TODO")
                   ("* COMMENTS in capitals" . "COMMENTS in capitals")
                   ;; Tags are the last word, and take their spaces with them.
                   ("* :a:b:" . "")
                   ("* Tags   :a:b:   " . "Tags")
                   ("* No space:a:" . "No space:a:")
                   ("* Not last :a: word" . "Not last :a: word")
                   ("* Spaced   out\twords" . "Spaced out words")
                   ;; A heading reads without its inline markup.
                   ("* TODO [#A] [[https://example.org/a][A link]] and *bold* =code= ~x~ [1/2] :tag:"
                    . "A link and bold code x")))
    (ert-info (heading)
      (should (equal (plist-get (sommaire-org-test--first-child (concat heading "\n")) :title)
                     title)))))

(defconst sommaire-org-test--read-titles
  '(("[[https://example.org/a][A link]] and *bold*" . "A link and bold")
    ("[[https://example.org/plain]]" . "https://example.org/plain")
    ("<https://example.org/angle> and more" . "https://example.org/angle and more")
    ("https://example.org/bare" . "https://example.org/bare")
    ("*bold* /italic/ _under_ +strike+ =verb= ~code~" . "bold italic under strike verb code")
    ("*/nested/* words" . "nested words")
    ("=*literal*= and ~/x/~" . "*literal* and /x/")
    ("=[[https://example.org/a][A link]]=" . "[[https://example.org/a][A link]]")
    ("[[https://example.org/a][*bold* desc]] tail" . "bold desc tail")
    ("*[[https://example.org/a][link in bold]]*" . "link in bold")
    ("(*paren*) \"*quoted*\" {*brace*} -*dash*- '*s*'" . "(paren) \"quoted\" {brace} -dash- 's'")
    ("*a*, *b*. *c*: *d*; *e*! *f*? *g*) *h*'" . "a, b. c: d; e! f? g) h'")
    ("*a* *b*" . "a b")
    ("*a*b*" . "a*b")
    ("=a= b =c=" . "a b c")
    ;; Marks that open or close nothing.
    ("a*b*c and 1+1+1 and p/q/r" . "a*b*c and 1+1+1 and p/q/r")
    ("a*b* and p/q/ and 1+1+" . "a*b* and p/q/ and 1+1+")
    ("2 * 3 * 4 and 2 / 3 / 4" . "2 * 3 * 4 and 2 / 3 / 4")
    ("*not closed and /also not" . "*not closed and /also not")
    ("[not a link] and [[broken]" . "[not a link] and [[broken]"))
  "Titles as a heading holds them, and as they read.")

(ert-deftest sommaire-org-title-reads-as-it-is-displayed ()
  "A heading's inline markup goes, and what is verbatim stays as it stands."
  (pcase-dolist (`(,source . ,title) sommaire-org-test--read-titles)
    (ert-info (source)
      (should (equal (plist-get (sommaire-org-test--first-child (concat "* " source "\n")) :title)
                     title)))))

(ert-deftest sommaire-org-title-reads-as-pandoc-reads-it ()
  "Pandoc, which writes the page, reads each title in the same words."
  (unless (executable-find "pandoc")
    (ert-skip "missing executable pandoc"))
  (should (equal (sommaire-test-pandoc-titles
                  "org" (mapconcat (lambda (row) (concat "* " (car row) "\n"))
                                   sommaire-org-test--read-titles ""))
                 (mapcar #'cdr sommaire-org-test--read-titles))))

(ert-deftest sommaire-org-title-of-a-property-or-a-keyword-reads-as-displayed ()
  "An ALT_TITLE and a #+title read without their inline markup too."
  (should (equal (plist-get (sommaire-org-test--first-child
                             "* Long\n:PROPERTIES:\n:ALT_TITLE: A *short* [[u][one]]\n:END:\n")
                            :title)
                 "A short one"))
  (should (equal (plist-get (sommaire-org-test--root-of "#+title: A *bold* [[u][one]]\n") :title)
                 "A bold one")))

(ert-deftest sommaire-org-title-is-bounded ()
  "A heading's title reads a bounded length, so a hostile line costs little and breaks nothing."
  (pcase-dolist (`(,source . ,prefix)
                 `((,(make-string 5000 ?a) . "aaa")
                   ;; An opener whose closer never comes, which a long search would overflow on.
                   (,(concat "*" (make-string 500000 ?a)) . "*aaa")
                   ;; Marks as deep as the length allows.
                   (,(concat (apply #'concat (make-list 300 "*/ ")) "x") . "*/ *")
                   (,(concat (make-string 400 ?/) "x" (make-string 400 ?/)) . "")))
    (ert-info ((substring source 0 8))
      (let ((title (plist-get (sommaire-org-test--first-child (concat "* " source "\n")) :title)))
        (should (stringp title))
        (should (string-prefix-p prefix title))
        (should (<= (length title) sommaire-rules-longest-title))))))

(ert-deftest sommaire-org-heading-titles-read-the-buffers-keywords ()
  "The TODO keywords of a title are those of this buffer."
  (should (equal (sommaire-org-test--titles
                  (sommaire-org-test--root-of "#+TODO: WAIT | OK\n* WAIT One\n* OK Two\n* TODO Three\n"))
                 '("One" "Two" "TODO Three"))))

(ert-deftest sommaire-org-heading-titles-stay-plain ()
  "A title holds no text property of the buffer, such as fontification."
  (sommaire-org-test--with-document "* A title\n"
    (put-text-property (point-min) (point-max) 'face 'bold)
    (should-not (text-properties-at
                 0 (plist-get (car (plist-get (sommaire-org-test--root) :children)) :title)))))

(ert-deftest sommaire-org-alt-title ()
  "The property ALT_TITLE wins when it has a value."
  (let ((drawer ":PROPERTIES:\n:ALT_TITLE: %s\n:END:\n"))
    (should (equal (plist-get (sommaire-org-test--first-child
                               (concat "* A long [1/2] title\n" (format drawer "Short")))
                              :title)
                   "Short"))
    (should (equal (plist-get (sommaire-org-test--first-child
                               (concat "* The text\n" (format drawer "")))
                              :title)
                   "The text"))))

(ert-deftest sommaire-org-document-title ()
  "The keywords TITLE give the root's title, as they do to Org's exporter."
  (pcase-dolist (`(,text . ,title)
                 '(("#+title: One\n" . "One")
                   ("#+TITLE: Upper\n" . "Upper")
                   ("#+title: One\n#+title: Two\n" . "One Two")
                   ("* A\n#+title: Late\n" . "Late")
                   ("#+title:\n" . nil)
                   ("* A\n" . nil)
                   ("#+begin_src org\n#+title: In code\n#+end_src\n" . nil)
                   ("#+subtitle: Not this\n" . nil)))
    (ert-info (text)
      (should (equal (plist-get (sommaire-org-test--root-of text) :title) title)))))

(ert-deftest sommaire-org-narrowing ()
  "R6: a part that starts at a heading with only deeper ones has it as its root."
  (let ((text "#+title: Document\n\nThe document's text.\n* A\nBody of A.\n** B\n** C\n* D\n"))
    (pcase-dolist (`(,from ,to ,title ,intro ,titles)
                   `(("* A" "* D" "A" t ("B" "C"))
                     ("** B" "** C" "B" nil nil)
                     ;; Another heading as high as the first one: no heading is the root.
                     ("* A" nil nil nil ("A" "D"))
                     ("** B" "* D" nil nil ("B" "C"))
                     ;; A part that does not start at a heading.
                     ("Body of A" "* D" nil t ("B" "C"))
                     ("The document's" "** B" nil t ("A"))
                     ("\n* A" "** B" nil nil ("A"))
                     ;; The title of the document does not survive narrowing.
                     ("#+title" "* D" nil t ("A"))))
      (ert-info ((format "from %S to %S" from to))
        (let ((root (sommaire-org-test--narrowed-root text from to)))
          (should (equal (plist-get root :title) title))
          (should (eq (plist-get root :intro) intro))
          (should (equal (sommaire-org-test--titles root) titles)))))))

(ert-deftest sommaire-org-document-that-starts-at-a-heading ()
  "Without narrowing, the root is the document, whatever it starts with."
  (should (equal (sommaire-org-test--titles (sommaire-org-test--root-of "* A\n** B\n")) '("A"))))

(ert-deftest sommaire-org-narrowed-root-is-eligible-and-read ()
  "The heading that the reader narrowed to is the root, whatever would drop it."
  (pcase-dolist (`(,heading . ,title)
                 '(("* A :ARCHIVE:" . "A")
                   ("* COMMENT A" . "A")
                   ("* A :noexport:" . "A")))
    (ert-info (heading)
      (let ((root (sommaire-org-test--narrowed-root
                   (concat heading "\nBody\n** B\n** C\n* D\n") "* " "* D")))
        (should (equal (plist-get root :title) title))
        (should-not (plist-get root :archived))
        (should (plist-get root :intro))
        (should (equal (sommaire-org-test--titles root) '("B" "C"))))))
  (ert-info ("its own ALT_TITLE and table")
    (let ((root (sommaire-org-test--narrowed-root
                 (concat "* Long\n:PROPERTIES:\n:ALT_TITLE: Short\n:END:\n"
                         "#+TOC: headlines 1 local\n** B\n* D\n")
                 "* " "* D")))
      (should (equal (plist-get root :title) "Short"))
      (should (plist-get root :explicit))
      (should-not (plist-get root :intro))))
  (ert-info ("a container below it")
    (let ((root (sommaire-org-test--narrowed-root
                 "* A\n** Contents :TOC:\n** B\n* D\n" "* " "* D")))
      (should (plist-get root :explicit))
      (should (equal (sommaire-org-test--titles root) '("B"))))))

(ert-deftest sommaire-org-active-heading ()
  "R4: which heading each part of a document belongs to."
  (let ((text (concat "#+title: Document\n\n"
                      "* A\n:PROPERTIES:\n:X: y\n:END:\nBody of A.\n"
                      "** B\nBody of B.\n"
                      "** COMMENT Dropped\nDropped text.\n"
                      "** C :ARCHIVE:\nArchived text.\n*** Under the archive\n"
                      "* COMMENT Top\nTop text.\n"
                      "* D\n")))
    (sommaire-org-test--with-document text
      (let ((outline (sommaire-org-outline)))
        (pcase-dolist (`(,place . ,id)
                       '(("#+title" . 0) ("* A" . 1) (":X: y" . 1) ("Body of A" . 1)
                         ("** B" . 2) ("Body of B" . 2)
                         ("** COMMENT" . 1) ("Dropped text" . 1)
                         ("** C :ARCHIVE:" . 3) ("Archived text" . 3) ("*** Under" . 3)
                         ("* COMMENT Top" . 0) ("Top text" . 0)
                         ("* D" . 4)))
          (ert-info (place)
            (goto-char (point-min))
            (search-forward place)
            (should (eql (sommaire-rules-active outline (match-beginning 0)) id))
            (should (eql (sommaire-rules-active outline (1- (pos-eol))) id))))
        (ert-info ("the very end of the buffer")
          (should (eql (sommaire-rules-active outline (point-max)) 4)))))))

(ert-deftest sommaire-org-active-heading-under-narrowing ()
  "R4 and R6: under narrowing, the positions are those of the accessible part."
  (sommaire-org-test--with-document "* A\nBody\n** B\nText\n* D\n"
    (search-forward "* D")
    (narrow-to-region (point-min) (match-beginning 0))
    (let ((outline (sommaire-org-outline)))
      (should (eql (sommaire-rules-active outline (point-min)) 0))
      (should (eql (sommaire-rules-active outline (point-max)) 1))
      (should-error (sommaire-rules-active outline (1+ (point-max))))))
  (ert-info ("a part in the middle of the buffer that starts at no heading")
    (sommaire-org-test--with-document "Top\n* A\nBody\n** B\nText\n* D\n"
      (search-forward "Body")
      (narrow-to-region (match-beginning 0)
                        (progn (search-forward "* D") (match-beginning 0)))
      (let ((outline (sommaire-org-outline)))
        (should (eql (sommaire-rules-active outline (point-min)) 0))
        (should (eql (sommaire-rules-active outline (point-max)) 1))
        (should-error (sommaire-rules-active outline (1- (point-min))))
        (should-error (sommaire-rules-active outline (1+ (point-max))))))))

(ert-deftest sommaire-org-first-character-after-the-metadata ()
  "R5: an inline minitoc goes after the metadata and before the introduction."
  (pcase-dolist (`(,text . ,body)
                 '(("* A\nText\n" . "Text")
                   ("* A\n\n\nText\n" . "Text")
                   ("* A\n** B\n" . "** B")
                   ("* A\nDEADLINE: <2026-11-02 Mon>\n** B\n" . "** B")
                   ("* A\nDEADLINE: <2026-11-02 Mon>\n:PROPERTIES:\n:X: y\n:END:\n:LOGBOOK:\n- n\n:END:\n\nText\n"
                    . "Text")
                   ;; A comment or a keyword is no metadata, though no introduction either.
                   ("* A\n:PROPERTIES:\n:X: y\n:END:\n# A comment\nText\n" . "# A comment")
                   ("* A\n* C\n" . "* C")))
    (ert-info (text)
      (sommaire-org-test--with-document text
        (search-forward body)
        (should (eql (plist-get (aref (plist-get (sommaire-org-outline) :places) 1) :body)
                     (match-beginning 0))))))
  (ert-info ("a heading at the end of the buffer")
    (sommaire-org-test--with-document "* A\n"
      (should (eql (plist-get (aref (plist-get (sommaire-org-outline) :places) 1) :body)
                   (point-max))))))

(ert-deftest sommaire-org-places-of-the-heading ()
  "A heading's place starts at its line and ends with its subtree."
  (sommaire-org-test--with-document "Text\n* A\n** B\n** C\n* D\n"
    (let ((places (plist-get (sommaire-org-outline) :places))
          (at (lambda (text) (save-excursion (goto-char (point-min)) (search-forward text)
                                             (match-beginning 0)))))
      (should (= (length places) 5))
      (should (eql (plist-get (aref places 0) :begin) (point-min)))
      (should (eql (plist-get (aref places 0) :end) (point-max)))
      (should (eql (plist-get (aref places 1) :begin) (funcall at "* A")))
      (should (eql (plist-get (aref places 1) :end) (funcall at "* D")))
      (should (eql (plist-get (aref places 2) :end) (funcall at "** C")))
      (should (eql (plist-get (aref places 4) :end) (point-max))))))

(ert-deftest sommaire-org-work-is-linear ()
  "A document chooses its width, so a heading must not cost the length of its siblings.
Twice the lines, of any shape, walk at most about twice the elements."
  (pcase-dolist (`(,start . ,lines)
                 '(("" "* x\n")
                   ("* a\n" "** x\n")
                   ("* a\n" "** x\n" "*** y\n" "**** z\n")
                   ("* a\n" "A line of prose.\n\n")))
    (ert-info ((format "%S after %S" lines start))
      (let ((walked (lambda (count)
                      (with-temp-buffer
                        (insert start)
                        (dotimes (index count)
                          (insert (nth (% index (length lines)) lines)))
                        (org-mode)
                        (sommaire-test-walked #'sommaire-org-outline)))))
        (should (<= (funcall walked 2000) (* 2.2 (funcall walked 1000))))))))

(ert-deftest sommaire-org-bounds-what-it-reads ()
  "A part larger than `sommaire-rules-largest-part' has only a root, and is not parsed."
  (with-temp-buffer
    (insert "* A\n")
    (sommaire-test-insert-text (- sommaire-rules-largest-part (buffer-size)))
    (org-mode)
    (ert-info ("up to the limit, it is read")
      (should (equal (sommaire-org-test--titles (sommaire-org-test--root)) '("A"))))
    (goto-char (point-max))
    (insert "a")
    (let ((parses 0)
          (messages nil)
          (parser (symbol-function 'org-element-parse-buffer)))
      (cl-letf (((symbol-function 'org-element-parse-buffer)
                 (lambda (&rest arguments)
                   (setq parses (1+ parses))
                   (apply parser arguments)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) messages))))
        (ert-info ("past it, it is not")
          (let ((outline (sommaire-org-outline)))
            (should (null (plist-get (plist-get (plist-get outline :model) :root) :children)))
            (should (eql (sommaire-rules-active outline (point-max)) 0))
            (should (= parses 0))
            (should (= (length messages) 1))
            (should (string-search "narrow to a part" (car messages)))))
        (ert-info ("a part of the buffer within the limit is")
          (narrow-to-region 1 5)
          (should (equal (plist-get (sommaire-org-test--root) :title) "A"))
          (should (= parses 1))
          (should (= (length messages) 1)))))))

(ert-deftest sommaire-org-outline-is-cached-per-modification-tick ()
  "The parser runs once for a given text and narrowing, whatever else happens."
  (sommaire-org-test--with-document "* A\n* B\n"
    (let* ((parses 0)
           (parser (symbol-function 'org-element-parse-buffer))
           (first nil))
      (cl-letf (((symbol-function 'org-element-parse-buffer)
                 (lambda (&rest arguments)
                   (setq parses (1+ parses))
                   (apply parser arguments))))
        (setq first (sommaire-org-outline))
        (should (eq (sommaire-org-outline) first))
        (should (= parses 1))
        (ert-info ("fontification changes properties, not the text")
          (put-text-property 1 3 'face 'bold)
          (should (eq (sommaire-org-outline) first))
          (should (= parses 1)))
        (ert-info ("point changes nothing")
          (goto-char (point-max))
          (should (eq (sommaire-org-outline) first))
          (should (= parses 1)))
        (ert-info ("an edit that keeps the size parses again")
          (goto-char 3)
          (delete-char 1)
          (insert "A")
          (should-not (eq (sommaire-org-outline) first))
          (should (= parses 2)))
        (ert-info ("an edit parses again")
          (goto-char (point-max))
          (insert "* C\n")
          (should (equal (sommaire-org-test--titles (sommaire-org-test--root)) '("A" "B" "C")))
          (should (= parses 3)))
        (ert-info ("narrowing parses again, and stays cached")
          (narrow-to-region 1 5)
          (should (equal (plist-get (sommaire-org-test--root) :title) "A"))
          (should (= parses 4))
          (sommaire-org-outline)
          (should (= parses 4)))
        (ert-info ("widening does not give the narrowed outline back")
          (widen)
          (should (equal (sommaire-org-test--titles (sommaire-org-test--root)) '("A" "B" "C"))))))))

(ert-deftest sommaire-org-outline-is-per-buffer ()
  "An indirect buffer shares the text, not the narrowing or the cache."
  (sommaire-org-test--with-document "* A\n** B\n* C\n"
    (let ((indirect (clone-indirect-buffer " *sommaire-org-test*" nil)))
      (unwind-protect
          (progn
            (with-current-buffer indirect
              (narrow-to-region 1 10)
              (should (equal (plist-get (sommaire-org-test--root) :title) "A")))
            (should (equal (sommaire-org-test--titles (sommaire-org-test--root)) '("A" "C")))
            (with-current-buffer indirect
              (should (equal (plist-get (sommaire-org-test--root) :title) "A"))))
        (kill-buffer indirect)))))

(ert-deftest sommaire-org-parser-failure-gives-a-root ()
  "A document that the parser refuses gives a root alone, a message, and one try."
  (sommaire-org-test--with-document "* A\n"
    (let ((parses 0) (messages nil))
      (cl-letf (((symbol-function 'org-element-parse-buffer)
                 (lambda (&rest _)
                   (setq parses (1+ parses))
                   (error "Boom")))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) messages))))
        (let ((outline (sommaire-org-outline)))
          (should (equal (plist-get outline :model)
                         '(:schema 1 :root (:id 0 :title nil :archived nil :intro nil
                                            :explicit nil :children nil))))
          (should (eql (sommaire-rules-active outline (point)) 0))
          (should (eq (sommaire-org-outline) outline))
          (should (= parses 1))
          (should (= (length messages) 1))
          (should (string-search "Boom" (car messages))))
        (ert-info ("the next text gets its own try")
          (insert "* B\n")
          (sommaire-org-outline)
          (should (= parses 2)))))))

(ert-deftest sommaire-org-document-too-deep-for-the-parser ()
  "A real document that exhausts the Lisp stack in Org's parser gives a root alone.
The limit of the stack is lowered, since the parser's time grows as the
square of the depth, and it would take a minute to fail at the usual limit."
  (with-temp-buffer
    (dotimes (level 300)
      (insert (make-string (1+ level) ?*) " Deep\n"))
    (org-mode)
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (&rest arguments) (push arguments messages))))
        (let ((max-lisp-eval-depth 200))
          (should (null (plist-get (sommaire-org-test--root) :children)))))
      (should (= (length messages) 1)))))

(ert-deftest sommaire-org-survives-any-depth-the-parser-survives ()
  "A document that Org can parse does not exhaust the Lisp stack here."
  (with-temp-buffer
    (dotimes (level 400)
      (insert (make-string (1+ level) ?*) " Deep\n"))
    (org-mode)
    (let* ((outline (sommaire-org-outline))
           (model (plist-get outline :model))
           (node (plist-get model :root))
           (depth 0))
      (while (plist-get node :children)
        (setq node (car (plist-get node :children))
              depth (1+ depth)))
      (should (= depth 400))
      (should (= (length (plist-get (sommaire-rules-local model 400) :path)) 400)))))

(ert-deftest sommaire-org-leaves-point-and-match-data ()
  "Reading the outline moves nothing that its caller may be using."
  (sommaire-org-test--with-document "#+title: T\n* A\nText\n* B\n"
    (goto-char 15)
    (string-match "b" "abc")
    (let ((match (match-data)))
      (sommaire-org-outline)
      (should (= (point) 15))
      (should (equal (match-data) match)))))

(ert-deftest sommaire-org-reads-whatever-case-fold-search-says ()
  "A buffer's own `case-fold-search' changes nothing in the outline."
  (sommaire-org-test--with-document "* Contents :toc:\n* A\n#+TOC: Headlines 1 LOCAL\n"
    (setq-local case-fold-search nil)
    (let ((root (sommaire-org-test--root)))
      (should (plist-get root :explicit))
      (should (equal (sommaire-org-test--titles root) '("A")))
      (should (plist-get (car (plist-get root :children)) :explicit)))))

(ert-deftest sommaire-org-load-adds-nothing-to-org ()
  "Once Org is there, requiring the adapter adds no timer, hook or key."
  (let ((result (repo-test-emacs
                 (list "-L" (expand-file-name "sommaire" repo-test-root)
                       "-L" (expand-file-name "tests/helpers" repo-test-root)
                       "-l" "org-element"
                       "-l" "load-effects"
                       "--eval" "(load-effects-report 'sommaire-org)"))))
    (should (eql (car result) 0))
    (should (equal (car (read-from-string (cdr result)))
                   '(:timers 0 :hooks nil :global-map nil :minor-modes nil
                     :auto-modes nil :sommaire nil :imprimeur nil)))))

;;; sommaire-org-test.el ends here

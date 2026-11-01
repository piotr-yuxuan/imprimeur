;;; imprimeur-sync-test.el --- Tests of the source's lines on the page  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 004, "Lines on the page" and acceptance 3): the text
;; sent to pandoc for an Org buffer holds `#+IMPRIMEUR_LINE: N' before each
;; headline and at the start of each child of a section, which comes before
;; its affiliated keywords; never before planning lines, property drawers,
;; keywords or comments, and never inside lists or paragraphs.  Above 2 MiB,
;; before headlines alone.  N is a line of the widened buffer, without what
;; is prepended to the text.  For Org fixtures with planning lines, drawers,
;; captions, lists, footnotes and source blocks, pandoc's native output of the
;; anchored text, anchors removed, equals that of the original; a captioned
;; table's anchor carries the #+caption line.
;;
;; The same holds where Org's parser and pandoc read a document differently, as
;; a headline in a source block, since what is read is pandoc's.  A document's
;; shape costs no search per line that opens something, as a hostile document
;; could write many; Org's own parser takes minutes on those.
;;
;; When the scanner fails, the text goes without anchors, as a page without its
;; lines is worth more than none.
;;
;; A render runs this from a timer, where C-g does nothing, so what it reads has
;; a bound (code review of plan 004): tens of thousands of lines in Lisp, whatever
;; the document's size and shape.  Above that many lines, before headlines alone;
;; above that many that may matter, or far above 2 MiB, no anchor at all, and the
;; text otherwise as it is.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-sync)

(defconst imprimeur-sync-test-prefix "#+OPTIONS: H:9\n"
  "What precedes the buffer's text in what pandoc reads.")

(defconst imprimeur-sync-test-fixtures
  (expand-file-name "tests/fixtures/org/" repo-test-root)
  "The Org documents of these tests, with the filter that removes anchors.")

(defun imprimeur-sync-test-text (text)
  "Return what `imprimeur-sync-org-text' gives for a buffer holding TEXT."
  (with-temp-buffer
    (insert text)
    (imprimeur-sync-org-text)))

(defun imprimeur-sync-test-lines (anchored)
  "Return the N of each anchor in ANCHORED, in order."
  (let ((start 0) (lines nil))
    (while (string-match "^#\\+IMPRIMEUR_LINE: \\([0-9]+\\)$" anchored start)
      (push (string-to-number (match-string 1 anchored)) lines)
      (setq start (match-end 0)))
    (nreverse lines)))

(defun imprimeur-sync-test-fixture (name)
  "Return the text of the fixture NAME."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (concat name ".org") imprimeur-sync-test-fixtures))
    (buffer-string)))

(defun imprimeur-sync-test-native (text)
  "Return pandoc's native output for TEXT, without anchors at its top level."
  (with-temp-buffer
    (insert text)
    (should (equal (call-process-region
                    (point-min) (point-max) (imprimeur-test-require "pandoc") t '(t nil) nil
                    "-f" "org" "-t" "native" "-s" "--wrap=none"
                    (concat "--lua-filter="
                            (expand-file-name "remove-anchors.lua" imprimeur-sync-test-fixtures)))
                   0))
    (buffer-string)))

(defconst imprimeur-sync-test-places
  '(("no document at all" "" . "")
    ("no newline at the end" "Words" . "@1\nWords")
    ("a headline, and a paragraph on two lines"
     "* Head\nOne\ntwo\n\nThree\n" . "@1\n* Head\n@2\nOne\ntwo\n\n@5\nThree\n")
    ("a planning line and a property drawer"
     "* Head\nSCHEDULED: <2026-11-01>\n:PROPERTIES:\n:ID: x\n:END:\nBody\n"
     . "@1\n* Head\nSCHEDULED: <2026-11-01>\n:PROPERTIES:\n:ID: x\n:END:\n@6\nBody\n")
    ("a second planning line is a paragraph, to pandoc"
     "* Head\nSCHEDULED: <2026-11-01>\nCLOSED: [2026-11-01]\n:PROPERTIES:\n:ID: x\n:END:\nBody\n"
     . "@1\n* Head\nSCHEDULED: <2026-11-01>\n@3\nCLOSED: [2026-11-01]\n:PROPERTIES:\n:ID: x\n:END:\n@7\nBody\n")
    ("a line that looks like planning, away from a headline"
     "Words\n\nSCHEDULED: x\nmore\n" . "@1\nWords\n\n@3\nSCHEDULED: x\nmore\n")
    ("keywords and comments"
     "#+title: T\n# A comment\n\nWords\n#+foo: x\nMore\n" . "#+title: T\n# A comment\n\n@4\nWords\n#+foo: x\n@6\nMore\n")
    ("a caption, whose anchor comes first"
     "#+caption: C\n#+name: n\n| a |\n| b |\n" . "@1\n#+caption: C\n#+name: n\n| a |\n| b |\n")
    ("a caption parted from its table"
     "#+caption: C\n\n| a |\n" . "#+caption: C\n\n@3\n| a |\n")
    ("a caption before a headline"
     "#+caption: C\n* Head\n" . "#+caption: C\n@2\n* Head\n")
    ("a list, its items and what they hold"
     "- a\n  b\n\n  c\n- d\n  - e\nf\n" . "@1\n- a\n  b\n\n  c\n- d\n  - e\n@7\nf\n")
    ("a list after a paragraph, with no blank line"
     "One\n- a\n" . "@1\nOne\n@2\n- a\n")
    ("a footnote holds what follows, up to two blank lines"
     "[fn:1] a\n\nb\n\n\nc\n" . "@1\n[fn:1] a\n\nb\n\n\n@6\nc\n")
    ("a source block, with text around it and no blank line"
     "One\n#+begin_src sh\necho\n#+end_src\nTwo\n"
     . "@1\nOne\n@2\n#+begin_src sh\necho\n#+end_src\n@5\nTwo\n")
    ("a headline in a source block is code, to pandoc"
     "#+begin_src org\n* Code\n#+end_src\n* Head\n" . "@1\n#+begin_src org\n* Code\n#+end_src\n@4\n* Head\n")
    ("a headline in a drawer is hidden, to pandoc"
     ":D:\n* Hidden\n:END:\n* Head\n" . ":D:\n* Hidden\n:END:\n@4\n* Head\n")
    ("a block without an end is no block"
     "#+begin_src sh\n* Head\n" . "#+begin_src sh\n@2\n* Head\n")
    ("a line in a LaTeX environment is LaTeX, to pandoc"
     "\\begin{align}\na\n* b\n\\end{align}\nc\n" . "@1\n\\begin{align}\na\n* b\n\\end{align}\nc\n")
    ("a source block's results are part of it"
     "#+begin_src sh\necho\n#+end_src\n\n#+RESULTS:\n: 1\n: 2\n\nNext\n"
     . "@1\n#+begin_src sh\necho\n#+end_src\n\n#+RESULTS:\n: 1\n: 2\n\n@9\nNext\n")
    ("characters beyond ASCII count as one line each"
     "É\n\nÉé\n" . "@1\nÉ\n\n@3\nÉé\n"))
  "Each entry is (WHAT TEXT . ANCHORED), `@N' in ANCHORED being an anchor.
Two blank lines go before an anchor, so that no footnote takes it in.")

(ert-deftest imprimeur-sync-places-each-anchor ()
  (pcase-dolist (`(,what ,text . ,anchored) imprimeur-sync-test-places)
    (ert-info (what)
      (should (equal (imprimeur-sync-test-text text)
                     (concat imprimeur-sync-test-prefix
                             (replace-regexp-in-string
                              "^@\\([0-9]+\\)$" "\n\n#+IMPRIMEUR_LINE: \\1" anchored)))))))

(ert-deftest imprimeur-sync-next-decides ()
  (pcase-dolist (`(,state ,class ,indent ,anchor ,next)
                 '(;; Where an anchor goes.
                   ((nil nil) headline 0 t (headline nil))
                   ((text nil) headline 0 t (headline nil))
                   ((blank nil) text 0 t (text nil))
                   ((headline nil) text 0 t (text nil))
                   ((block nil) text 0 t (text nil))
                   ((table nil) text 0 t (text nil))
                   ((blank nil) table 0 t (table nil))
                   ((text nil) table 0 t (table nil))
                   ((text nil) fixed 0 t (fixed nil))
                   ((text nil) block 0 t (block nil))
                   ((block nil) block 0 t (block nil))
                   ((rule nil) rule 0 t (rule nil))
                   ((affiliated nil) table 0 t (table nil))
                   ((keyword nil) text 0 t (text nil))
                   ((comment nil) text 0 t (text nil))
                   ((drawer nil) text 0 t (text nil))
                   ((planning nil) text 0 t (text nil))
                   ;; Where none goes: not before these.
                   ((headline nil) planning 0 nil (planning nil))
                   ((planning nil) drawer 0 nil (drawer nil))
                   ((blank nil) drawer 0 nil (drawer nil))
                   ((blank nil) keyword 0 nil (keyword nil))
                   ((blank nil) comment 0 nil (comment nil))
                   ((blank nil) affiliated 0 nil (affiliated nil))
                   ((blank nil) results 0 nil (results nil))
                   ((nil nil) blank 0 nil (blank nil))
                   ;; Nor in what goes on.
                   ((text nil) text 0 nil (text nil))
                   ((table nil) table 0 nil (table nil))
                   ((fixed nil) fixed 0 nil (fixed nil))
                   ;; What follows results belongs to them.
                   ((results nil) fixed 0 nil (fixed nil))
                   ((results nil) table 0 nil (table nil))
                   ((results nil) item 0 nil (item 0))
                   ((results nil) blank 0 nil (blank nil))
                   ((blank nil) fixed 0 t (fixed nil))
                   ;; A list opens, goes on and ends.
                   ((blank nil) item 2 t (item 2))
                   ((item 0) item 0 nil (inside 0))
                   ((inside 0) text 2 nil (inside 0))
                   ((inside 0) table 2 nil (inside 0))
                   ((inside 0) block 2 nil (inside 0))
                   ((inside 0) affiliated 2 nil (inside 0))
                   ((inside 2) item 0 nil (inside 0))
                   ((inside 0) item 2 nil (inside 0))
                   ((inside 0) blank 0 nil (blank 0))
                   ((blank 0) blank 0 nil (blank 0))
                   ((blank 0) item 0 nil (inside 0))
                   ((blank 0) text 2 nil (inside 0))
                   ((blank 0) text 0 t (text nil))
                   ((inside 0) text 0 t (text nil))
                   ((inside 2) text 2 t (text nil))
                   ((inside 0) table 0 t (table nil))
                   ((inside 0) keyword 0 nil (keyword nil))
                   ((inside 0) headline 0 t (headline nil))
                   ((inside 0) note 0 t (note -1))
                   ;; A footnote opens, goes on and ends.
                   ((text nil) note 0 t (note -1))
                   ((note -1) text 0 nil (inside -1))
                   ((inside -1) item 0 nil (inside -1))
                   ((inside -1) block 0 nil (inside -1))
                   ((inside -1) blank 0 nil (blank -1))
                   ((blank -1) text 0 nil (inside -1))
                   ((blank -1) blank 0 nil (blank nil))
                   ((blank nil) text 0 t (text nil))
                   ((inside -1) note 0 t (note -1))
                   ((inside -1) headline 0 t (headline nil))))
    (ert-info ((format "%S %S %S" state class indent))
      (should (equal (imprimeur-sync--next state class indent) (cons anchor next))))))

(ert-deftest imprimeur-sync-class-reads-a-line-as-pandoc-does ()
  (let ((closers (make-hash-table :test #'equal))
        (later "\n#+end_src\n\\end{x}\n:end:\n"))
    (dolist (closer '("#+end_src" "\\end{x}" ":end:"))
      (puthash closer 1000 closers))
    (pcase-dolist (`(,previous ,line ,class)
                   '((nil "" blank)
                     (nil "   " blank)
                     (nil "* Head" headline)
                     (nil "*** Head" headline)
                     (nil "*Bold*" text)
                     (nil " * item" item)
                     (headline "SCHEDULED: <x>" planning)
                     (headline "SCHEDULED:\t[x]" planning)
                     (headline "  DEADLINE: <x>" planning)
                     (headline "CLOSED:<x>" planning)
                     (headline "DEADLINE: <x> SCHEDULED: <y>CLOSED: [z]" planning)
                     (headline "DEADLINE: <a [b]>" planning)
                     ;; Only the line after a headline, and only dates in it.
                     (planning "DEADLINE: <x>" text)
                     (text "SCHEDULED: <x>" text)
                     (blank "SCHEDULED: <x>" text)
                     (headline "SCHEDULED: x" text)
                     (headline "SCHEDULED:" text)
                     (headline "SCHEDULED: <>" text)
                     (headline "SCHEDULED: <x> words" text)
                     (headline "SCHEDULED: <x> " text)
                     (headline "SCHEDULED: <x> <y>" text)
                     (headline "SCHEDULED: <x]" text)
                     (headline "Scheduled: <x>" text)
                     (headline "deadline: <x>" text)
                     (nil "#+begin_src sh" block)
                     (nil "  #+BEGIN_SRC sh" block)
                     (nil "#+begin_quote" keyword)
                     (nil "#+RESULTS:" results)
                     (nil "#+results[abc]:" results)
                     (nil "#+caption: C" affiliated)
                     (nil "#+CAPTION[s]: C" affiliated)
                     (nil "#+attr_html: :width 5" affiliated)
                     (nil "#+name: n" affiliated)
                     (nil "#+title: T" keyword)
                     (nil "#+nameless: n" keyword)
                     (nil "#+foo" keyword)
                     (nil "# comment" comment)
                     (nil "#" comment)
                     (nil "#hash" text)
                     (nil "[fn:1] note" note)
                     (nil "[fn:name] note" note)
                     (nil "[1] note" note)
                     (nil "[fn:a b] words" text)
                     (nil "[[file:a.png]]" text)
                     (nil "| a |" table)
                     (nil "  | a |" table)
                     (nil "+---+---+" table)
                     (nil "+- words" text)
                     (nil ": fixed" fixed)
                     (nil ":" fixed)
                     (nil ":word" text)
                     (nil "-----" rule)
                     (nil "  --------  " rule)
                     (nil "----" text)
                     (nil "- item" item)
                     (nil "-" item)
                     (nil "+ item" item)
                     (nil "  - item" item)
                     (nil "1. item" item)
                     (nil "12) item" item)
                     (nil "1.5 words" text)
                     (nil "-word" text)
                     (nil ":NAME:" drawer)
                     (nil "  :NAME:  " drawer)
                     (nil ":NAME: words" text)
                     (nil "\\begin{x}" text)
                     (nil "Words" text)))
      (ert-info (line)
        (with-temp-buffer
          (insert line later)
          (goto-char (point-min))
          (let ((case-fold-search t))
            (should (eq (imprimeur-sync--class previous closers) class))))))))

(ert-deftest imprimeur-sync-class-leaves-point-on-a-region-s-last-line ()
  (pcase-dolist (`(,text ,class ,closer ,line)
                 '(("#+begin_src\nx\n#+END_SRC\ny\n" block "#+end_src" 3)
                   (":D:\nx\n* Head\n  :end:\ny\n" drawer ":end:" 4)
                   ("\\begin{x}\ny\n\\end{x}\nz\n" text "\\end{x}" 3)
                   ;; A name closes itself alone, the first time it comes.
                   ("#+begin_a\n#+end_b\n#+end_a\n#+end_a\n" block "#+end_a" 3)))
    (with-temp-buffer
      (insert text)
      (let ((case-fold-search t)
            (closers (make-hash-table :test #'equal)))
        (puthash closer (point-max) closers)
        (goto-char (point-min))
        (should (eq (imprimeur-sync--class nil closers) class))
        (should (= (line-number-at-pos) line))))))

(ert-deftest imprimeur-sync-a-closer-before-its-opener-closes-nothing ()
  ;; Only a later line can close a region, and a closer does not close itself.
  (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text "#+end_src\n\n#+begin_src\n* Head\n"))
                 '(4)))
  (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text ":END:\nmore\n"))
                 '(1))))

(ert-deftest imprimeur-sync-places-what-the-fixtures-say ()
  (pcase-dolist (`(,name . ,lines)
                 '(("planning" 3 5 7 13 15 17 19 21 24 26 29 30 33 34 37 38 41 42 45 47)
                   ("drawers" 6 13 21 25 27 29)
                   ("captions" 3 9 14 21 24 27 32 35 39)
                   ("lists" 1 2 26 28 44 46)
                   ("footnotes" 1 4 8 12 14 16 18 20 21 23 25)
                   ("source-blocks" 3 9 14 16 20 28 35 45 49 55 60 64 68 72 76 77 80 82 87 92 97 99)
                   ;; 999 is the document's own.
                   ("others" 6 9 11 14 16 18 19 21 23 25 28 30 32 35 40 42 44 45 47 48 50 51 999 54)
                   ("ordinary" 4 7 12 14 16 21 34 38 40 45 48 52 54 56)))
    (ert-info (name)
      (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text (imprimeur-sync-test-fixture name)))
                     lines)))))

(ert-deftest imprimeur-sync-keeps-what-pandoc-reads ()
  (dolist (name '("planning" "drawers" "captions" "lists" "footnotes" "source-blocks" "others" "ordinary"))
    (ert-info (name)
      (let* ((text (imprimeur-sync-test-fixture name))
             (anchored (imprimeur-sync-test-text text))
             (original (imprimeur-sync-test-native (concat imprimeur-sync-test-prefix text))))
        ;; An anchor reaches pandoc as a raw block, or this proves nothing.
        (should (string-search "#+IMPRIMEUR_LINE:" anchored))
        (should-not (string-search "IMPRIMEUR_LINE" original))
        (should (equal (imprimeur-sync-test-native anchored) original))))))

(ert-deftest imprimeur-sync-keeps-a-caption-with-its-table ()
  ;; The test of the fixtures compares with the original; this one says what
  ;; the original holds, in case neither kept the caption.
  (let ((native (imprimeur-sync-test-native
                 (imprimeur-sync-test-text "#+caption: The caption\n| a |\n"))))
    (should (string-match-p "Caption[^|]*Str \"caption\"" native))))

(ert-deftest imprimeur-sync-places-the-anchors-of-the-plan ()
  ;; What the plan says, through Org's own parser, on a document where it and
  ;; pandoc agree: before each headline, and at the :begin of each child of a
  ;; section but planning lines, property drawers, keywords and comments.
  (with-temp-buffer
    (insert (imprimeur-sync-test-fixture "ordinary"))
    (org-mode)
    (let ((lines nil))
      (org-element-map (org-element-parse-buffer 'element) '(headline section)
        (lambda (node)
          (dolist (element (if (eq (org-element-type node) 'section) (org-element-contents node) (list node)))
            (unless (memq (org-element-type element) '(planning property-drawer keyword comment))
              (push (line-number-at-pos (org-element-property :begin element) t) lines)))))
      (should (equal (imprimeur-sync-test-lines (imprimeur-sync-org-text))
                     (sort lines #'<))))))

(ert-deftest imprimeur-sync-reads-the-widened-buffer ()
  (let ((text "* One\nFirst\n\n* Two\nSecond\n\n* Three\nThird\n"))
    (with-temp-buffer
      (insert text)
      (goto-char 10)
      (narrow-to-region 14 26)
      (let ((tick (buffer-chars-modified-tick))
            (anchored (imprimeur-sync-org-text)))
        (should (equal anchored (with-temp-buffer (insert text) (imprimeur-sync-org-text))))
        (should (equal (imprimeur-sync-test-lines anchored) '(1 2 4 5 7 8)))
        (should (= (point-min) 14))
        (should (= (point-max) 26))
        (should (= (point) 14))
        (should (= (buffer-chars-modified-tick) tick))))))

(ert-deftest imprimeur-sync-keeps-point-in-the-accessible-part ()
  (with-temp-buffer
    (insert "One\n\nTwo\n\nThree\n")
    (goto-char 7)
    (imprimeur-sync-org-text)
    (should (= (point) 7))))

(defun imprimeur-sync-test-of-size (size head filler)
  "Return text of SIZE bytes: HEAD in ASCII, a line of filler, a headline.
The filler is the character FILLER, of one byte or two, and an x when
that leaves a byte over."
  (let* ((tail "\n\n* Tail\n")
         (room (- size (length head) (length tail)))
         (width (string-bytes (string filler))))
    (concat head (make-string (% room width) ?x) (make-string (/ room width) filler) tail)))

(ert-deftest imprimeur-sync-gives-headlines-alone-above-2-mib ()
  (let* ((limit (* 2 1024 1024))
         (head "* First\n\nA paragraph.\n\n#+begin_src org\n* Code\n#+end_src\n\n- a list\n\n")
         (block-lines '(1 3 5 9 11 13))
         (head-lines '(1 13)))
    (ert-info ("at the limit")
      (should (equal (imprimeur-sync-test-lines
                      (imprimeur-sync-test-text (imprimeur-sync-test-of-size limit head ?x)))
                     block-lines)))
    (ert-info ("a byte above it")
      (should (equal (imprimeur-sync-test-lines
                      (imprimeur-sync-test-text (imprimeur-sync-test-of-size (1+ limit) head ?x)))
                     head-lines)))
    (ert-info ("bytes count, not characters")
      (let ((text (imprimeur-sync-test-of-size (1+ limit) head ?é)))
        (should (< (length text) limit))
        (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text text)) head-lines))))))

(defun imprimeur-sync-test-repeat (line count)
  "Return LINE, COUNT times."
  (mapconcat #'identity (make-list count line)))

(ert-deftest imprimeur-sync-gives-headlines-alone-above-the-line-limit ()
  (let ((text (lambda (lines)
                ;; Four lines, then as many as it takes, then a headline.
                (concat "* First\n\nA paragraph.\n\n"
                        (imprimeur-sync-test-repeat "a\n" (- lines 5))
                        "* Tail\n"))))
    (ert-info ("tens of thousands of lines are read")
      (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text (funcall text 10000)))
                     '(1 3 5 10000))))
    (let ((limit imprimeur-sync--line-limit))
      (ert-info ("at the limit")
        (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text (funcall text limit)))
                       (list 1 3 5 limit))))
      (ert-info ("a line above it")
        (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text (funcall text (1+ limit))))
                       (list 1 (1+ limit))))))))

(ert-deftest imprimeur-sync-gives-no-anchor-above-the-limits ()
  (let* ((limit imprimeur-sync--line-limit)
         (size imprimeur-sync--search-limit)
         (plain (lambda (text)
                  (should (equal (imprimeur-sync-test-text text)
                                 (concat imprimeur-sync-test-prefix text))))))
    (ert-info ("as many headlines as the limit, among more lines")
      (let ((text (concat (imprimeur-sync-test-repeat "* h\n" limit) "a\n")))
        (should (= (length (imprimeur-sync-test-lines (imprimeur-sync-test-text text))) limit))))
    (ert-info ("a headline more")
      (funcall plain (imprimeur-sync-test-repeat "* h\n" (1+ limit))))
    (ert-info ("lines that may open something count")
      (funcall plain (concat "* Head\n" (imprimeur-sync-test-repeat ":x:\n" (1+ limit)))))
    (ert-info ("as many closers as the limit")
      (should (equal (imprimeur-sync-test-lines
                      (imprimeur-sync-test-text
                       (concat "* Head\n" (imprimeur-sync-test-repeat "#+end_x\n" limit))))
                     '(1))))
    (ert-info ("a closer more")
      (funcall plain (concat "* Head\n" (imprimeur-sync-test-repeat "#+end_x\n" (1+ limit)))))
    (ert-info ("at the size")
      (should (equal (imprimeur-sync-test-lines
                      (imprimeur-sync-test-text (imprimeur-sync-test-of-size size "* First\n\n" ?x)))
                     '(1 5))))
    (ert-info ("a byte above it")
      (funcall plain (imprimeur-sync-test-of-size (1+ size) "* First\n\n" ?x)))))

(defun imprimeur-sync-test-work (text)
  "Return what `imprimeur-sync-org-text' does for a buffer holding TEXT.
The result is (CLASSES SEARCHES ANCHORS): the lines it reads in Lisp, the
searches it makes and the anchors it writes."
  (let* ((classes 0)
         (searches 0)
         (class (symbol-function 'imprimeur-sync--class))
         (search (symbol-function 're-search-forward))
         (anchored (cl-letf (((symbol-function 'imprimeur-sync--class)
                              (lambda (&rest arguments)
                                (setq classes (1+ classes))
                                (apply class arguments)))
                             ((symbol-function 're-search-forward)
                              (lambda (&rest arguments)
                                (setq searches (1+ searches))
                                (apply search arguments))))
                     (imprimeur-sync-test-text text))))
    (list classes searches (length (imprimeur-sync-test-lines anchored)))))

(ert-deftest imprimeur-sync-reads-tens-of-thousands-of-lines-at-most ()
  ;; No wall clock judges.  2 MB took 10 s when each line was read, and 6 MB of
  ;; headlines 6 s when only those were.
  (pcase-dolist (`(,line ,count)
                 `(("a\n" 1000000) ("- \n" 666666) ("\n" 2000000) ("| a |\n" 333333)
                   ("[fn:1] x\n" 222222) ("* h\n" 1500000) (":x:\n" 500000)
                   ("#+begin_x\n" 200000) ("\\begin{x}\n" 200000) ("#+end_x\n" 250000)
                   ;; The most that the limits let through: each closer found, each
                   ;; opener read, and a search from each to its closer.
                   ("#+begin_x\n#+end_x\n" ,imprimeur-sync--line-limit)))
    (ert-info ((format "%S, %d times" line count))
      (pcase-let ((`(,classes ,searches ,anchors)
                   (imprimeur-sync-test-work (imprimeur-sync-test-repeat line count))))
        (should (< classes 100000))
        (should (< searches 300000))
        (should (< anchors 100000))))))

(ert-deftest imprimeur-sync-gives-no-anchor-when-the-scanner-fails ()
  ;; Nothing is known to make it fail.  A line of a shape no test foresaw could
  ;; overflow the regexp matcher's stack, which must not cost the page.
  (let ((text "* Head\n\nWords.\n"))
    (dolist (function '(imprimeur-sync--closers imprimeur-sync--class))
      (ert-info ((symbol-name function))
        (with-current-buffer (get-buffer-create " *imprimeur-log*") (erase-buffer))
        (cl-letf (((symbol-function function)
                   (lambda (&rest _) (error "Stack overflow in regexp matcher"))))
          (should (equal (imprimeur-sync-test-text text)
                         (concat imprimeur-sync-test-prefix text))))
        (should (string-search "Stack overflow"
                               (with-current-buffer " *imprimeur-log*" (buffer-string))))))))

(ert-deftest imprimeur-sync-above-the-limit-stays-out-of-regions ()
  (let* ((filler (make-string (* 3 1024 1024) ?x))
         (text (concat "#+begin_src org\n* Code\n#+END_SRC\n:D:\n* Hidden\n:END:\n#+begin_x\n* Open\n"
                       "#+caption: C\n* Last\n" filler "\n")))
    (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text text)) '(8 10)))))

(ert-deftest imprimeur-sync-spends-no-search-on-what-closes-nothing ()
  ;; Org's parser searches on from each of these lines, and so takes minutes on
  ;; a document of them.  Here no wall clock judges: the searches are counted.
  (let ((searches 0)
        (search (symbol-function 're-search-forward)))
    (dolist (shape '("#+begin_x%d\n" "\\begin{x%d}\n" ":x%d:\n"
                     ;; The dotted capital I has no plain lower case, so that a
                     ;; search for a name that holds it might never find it.
                     "#+begin_İ%1$d\n#+end_İ%1$d\n"))
      (ert-info (shape)
        (setq searches 0)
        (with-temp-buffer
          (dotimes (index 2000) (insert (format shape index)))
          (cl-letf (((symbol-function 're-search-forward)
                     (lambda (&rest arguments)
                       (setq searches (1+ searches))
                       (apply search arguments))))
            (imprimeur-sync-org-text)))
        (should (<= searches 1))))))

(ert-deftest imprimeur-sync-takes-any-long-line ()
  ;; A repetition of the wrong kind overflows the regexp matcher's stack on such
  ;; a line, and the render would then fail, for this document, each time.
  (let ((size (* 19 100 1000)))
    (pcase-dolist (`(,before ,char ,after)
                   '(("[fn:" ?a "") ("[fn:" ?a "]") ("[fn:" ?\] "") ("[" ?1 "")
                     ("#+caption[" ?a "") ("#+caption[" ?\] "") ("#+results[" ?\] "") ("#+attr_" ?a "")
                     ("#+begin_" ?a "") ("\\begin{" ?a "") (":" ?a "") ("" ?\s "x") ("" ?\s "#x") ("" ?- "x")
                     ("+-" ?- "x") ("" ?1 "x") ("" ?* "x") ("" ?: "") ("" ?| "") ("" ?\t "- x")))
      (ert-info ((format "%s%c%s" before char after))
        (let ((text (concat before (make-string size char) after "\n* Head\n")))
          (should (equal (car (last (imprimeur-sync-test-lines (imprimeur-sync-test-text text)))) 2)))))
    (ert-info ("dates without end, after a headline")
      (let ((text (concat "* First\n"
                          (mapconcat #'identity (make-list (/ size 14) "DEADLINE: <a> "))
                          "\n* Head\n")))
        (should (equal (imprimeur-sync-test-lines (imprimeur-sync-test-text text)) '(1 2 3)))))))

;;; imprimeur-sync-test.el ends here

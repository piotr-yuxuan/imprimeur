;;; imprimeur-sync.el --- The source's lines on the page  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; pandoc's Org reader says nothing of where a block comes from, so the text
;; sent to it holds anchors: `#+IMPRIMEUR_LINE: N' before a block whose first
;; line is line N of the widened buffer.  pandoc reads an anchor as a raw block
;; of its own, and the filter and the page make it a data-line on the block
;; after it.
;;
;; The anchors go before each headline and where each element of a section
;; starts, before its affiliated keywords; never before a planning line, a
;; drawer, a keyword or a comment, and never inside a list, a paragraph or a
;; footnote.  What decides is how pandoc will read each line, since an anchor
;; where it sees none of these splits what it would have joined.  So this is a
;; scanner of lines and not Org's own parser, which also takes a headline in a
;; source block for a headline, and whose time grows with the square of a long
;; list or of many unclosed blocks: 12 s for 256 KiB of list items, from a
;; timer, where C-g does nothing.
;;
;; From that timer too, the scanner's work has a bound, set on what costs: a
;; line read in Lisp takes microseconds, and a search in C milliseconds per MiB.
;; Up to `imprimeur-sync--anchor-limit' bytes and `imprimeur-sync--line-limit'
;; lines, every line is read.  Above either, only the lines that a search finds
;; are, and only headlines get anchors.  When more lines than that same limit
;; hold a headline, an opener or a closer, or above
;; `imprimeur-sync--search-limit' bytes, nothing gets one, and the page goes by
;; proportion.  In Emacs 31.1 on one laptop, byte-compiled, that same limit of
;; short lines took 0.07 s, or 0.4 s not compiled, and the worst shape found,
;; lines of openers indented as far as the size allows, 0.3 s at 2 MiB and 1.1 s
;; at 8 MiB.  One render runs at a time, and pandoc takes far longer at that size.

;;; Code:

(eval-when-compile (require 'cl-lib))

(defconst imprimeur-sync--anchor-limit (* 2 1024 1024)
  "The size in bytes of a buffer above which only headlines get anchors.")

(defconst imprimeur-sync--line-limit 32768
  "The most lines of a buffer that Lisp reads for its anchors.
Above this many lines, only headlines get anchors, and none do when
more than this many lines hold a headline, an opener or a closer.  At
2 MiB, it lets through lines of 64 bytes on average.")

(defconst imprimeur-sync--search-limit (* 8 1024 1024)
  "The size in bytes of a buffer above which nothing gets an anchor.
Nothing is searched, as pandoc would take more than the 20 s it has on
most text of this size: 20 s to 34 s here, under some load.")

(defconst imprimeur-sync--line-classes
  '((blank "[ \t]*$")
    (headline "\\*+ ")
    (block "[ \t]*#\\+begin_\\([-_a-z0-9]+\\)" "#+end_%s")
    (results "[ \t]*#\\+results?\\(?:\\[[^]\n]*\\]\\)?:")
    (affiliated "[ \t]*#\\+\\(?:attr_[-_a-z0-9]+\\|caption\\|data\\|headers?\\|label\\|name\\|plot\\|resname\\|source\\|srcname\\|tblname\\)\\(?:\\[[^]\n]*\\]\\)?:")
    (keyword "[ \t]*#\\+")
    (comment "[ \t]*#\\(?: \\|$\\)")
    (note "\\[\\(?:[0-9]+\\|fn:[^] \t\n]+\\)\\]")
    (table "[ \t]*\\(?:|\\|\\+-[-+]*[ \t]*$\\)")
    (fixed "[ \t]*:\\(?: \\|$\\)")
    (rule "[ \t]*-----+[ \t]*$")
    (item "\\(?:[ \t]*[-+]\\|[ \t]+\\*\\|[ \t]*[0-9]+[.)]\\)\\(?:[ \t]\\|$\\)")
    (drawer "[ \t]*:[^ \t\n:]+:[ \t]*$" ":end:")
    (text "[ \t]*\\\\begin{\\([-*_a-z0-9]+\\)}[ \t]*$" "\\end{%s}"))
  "How pandoc's Org reader sees a line, ignoring case: the first match wins.
Each entry is (CLASS REGEXP CLOSER), and a line that matches none is of
the class `text'.  CLOSER, if any, is what another line must start with
for this one to open a region that pandoc reads as a whole, across any
headline; with `format', it receives the region's name, REGEXP's first
group.  Without such a line this entry does not apply.  A LaTeX
environment is `text', since pandoc takes it into the paragraph around.
A name is in ASCII, whose case folding searches agree on.  No repetition
may go on where what follows it could match too: on a line of megabytes,
that overflows the regexp matcher's stack.  One limit remains: pandoc
also ends a region at a closer that goes on, as `#+end_srcfoo' ends
`src', and an anchor can then show in the code of such a document.")

(defconst imprimeur-sync--closer-regexp
  "^[ \t]*\\(#\\+end_[-_a-z0-9]+\\|\\\\end{[-*_a-z0-9]+}\\|:end:\\)"
  "A line that closes a region, the closer being its first group.")

(defconst imprimeur-sync--headline-or-opener-regexp
  "^\\(?:\\*+ \\|[ \t]*\\(?:#\\+begin_\\|\\\\begin{\\|:[^ \t\n:]+:[ \t]*$\\)\\)"
  "A headline, or a line that may open a region.")

(defconst imprimeur-sync--planning-regexp
  "\\(?:[ \t]*\\(?:CLOSED\\|DEADLINE\\|SCHEDULED\\):[ \t]*\\(?:<[^>\n]+>\\|\\[[^]\n]+\\]\\)\\)\\{1,3\\}$"
  "A line that pandoc takes for planning: only keywords and their dates.
Org writes each keyword once.  pandoc takes more, but repeating without
a bound overflows the regexp matcher's stack on a line of megabytes, so
a line of four is text here and an anchor comes between it and its
headline.")

(defun imprimeur-sync--class (previous closers)
  "Return the class of the line at point, after a line of class PREVIOUS.
See `imprimeur-sync--line-classes'.  When that line opens a region,
move point to the line that closes it.  CLOSERS maps each closer, in
lower case, to the last place it occurs, so that a region without one
costs no search, however many such lines there are.  A planning line
is one only right after a headline, and in capitals, as
`imprimeur-sync--planning-regexp' says: pandoc takes a second one, or
`Scheduled: Tuesday', for the start of a paragraph."
  (if (and (eq previous 'headline)
           (let ((case-fold-search nil))
             (looking-at-p imprimeur-sync--planning-regexp)))
      'planning
    (cl-loop for (class regexp closer) in imprimeur-sync--line-classes
             when (and (looking-at regexp)
                       (or (not closer)
                           (let ((key (downcase (format closer (match-string-no-properties 1)))))
                             (and (> (gethash key closers 0) (pos-eol))
                                  (goto-char (pos-eol))
                                  (re-search-forward (concat "^[ \t]*" (regexp-quote key)) nil t)))))
             return class
             finally return 'text)))

(defun imprimeur-sync--next (state class indent)
  "Return (ANCHOR . NEXT) for a line of CLASS indented by INDENT, after STATE.
ANCHOR is non-nil when an anchor belongs before that line, and NEXT is
the state after it.  A state is (PREVIOUS INSIDE): PREVIOUS the class
of the line before, or `inside', and INSIDE the indentation of the open
list's least indented bullet, or -1 in a footnote, or nil.  A headline
ends either; a footnote also ends at a new one and at a second blank
line; a list at a line that is no item and not deeper than its bullet,
but not at two blank lines, as pandoc may read on across them, after a
table.  Lines that repeat a class of `text', `table' or `fixed' go on
the same element.  pandoc makes what follows a source block's
`#+RESULTS:' part of that block, which takes no anchor apart."
  (pcase-let ((`(,previous ,inside) state))
    (cond ((eq class 'blank)
           (cons nil (list class (and (not (equal state '(blank -1))) inside))))
          ((and inside
                (not (memq class '(headline note)))
                (or (eq class 'item) (> indent inside)))
           (cons nil (list 'inside (min inside indent))))
          (t (cons (not (or (memq class '(results affiliated keyword comment drawer planning))
                            (eq previous 'results)
                            (and (eq class previous) (memq class '(text table fixed)))))
                   (list class (alist-get class `((item . ,indent) (note . -1)))))))))

(defun imprimeur-sync--closers ()
  "Return a table of the closers in this buffer, each with its last place.
A closer is the text that `imprimeur-sync--closer-regexp' gives, in lower
case, and its place the position right after it.  Return nil when more
than `imprimeur-sync--line-limit' lines hold one."
  (let ((closers (make-hash-table :test #'equal))
        (lines 0))
    (goto-char (point-min))
    (while (and (<= lines imprimeur-sync--line-limit)
                (re-search-forward imprimeur-sync--closer-regexp nil t))
      (puthash (downcase (match-string-no-properties 1)) (point) closers)
      (setq lines (1+ lines)))
    (and (<= lines imprimeur-sync--line-limit) closers)))

(defun imprimeur-sync--headlines (closers)
  "Return where each headline of this buffer starts, outside any region.
Only the lines that may matter are read; return nil when they are more
than `imprimeur-sync--line-limit'.  CLOSERS is as
`imprimeur-sync--closers' gives."
  (let ((anchors nil)
        (lines 0))
    (goto-char (point-min))
    (while (and (<= lines imprimeur-sync--line-limit)
                (re-search-forward imprimeur-sync--headline-or-opener-regexp nil t))
      (goto-char (pos-bol))
      (when (eq (imprimeur-sync--class nil closers) 'headline)
        (push (pos-bol) anchors))
      (forward-line 1)
      (setq lines (1+ lines)))
    (and (<= lines imprimeur-sync--line-limit) (nreverse anchors))))

(defun imprimeur-sync--elements (closers)
  "Return where an anchor goes in this buffer, in order, reading each line.
An element with affiliated keywords starts at the first of them; a
headline, whatever keyword comes before it, at itself.  CLOSERS is as
`imprimeur-sync--closers' gives."
  (let ((anchors nil)
        (pending nil)
        (state (list nil nil)))
    (goto-char (point-min))
    (while (not (eobp))
      (let* ((here (point))
             (indent (current-indentation))
             (class (imprimeur-sync--class (car state) closers))
             (step (imprimeur-sync--next state class indent)))
        (when (car step)
          (push (if (eq class 'headline) here (or pending here)) anchors))
        (setq state (cdr step)
              pending (and (eq (car state) 'affiliated) (or pending here)))
        (forward-line 1)))
    (nreverse anchors)))

(defun imprimeur-sync-org-text ()
  "Return the text to send to pandoc for this Org buffer, widened.
pandoc's default H:3 would turn deeper headlines into list items, and
a later #+OPTIONS still wins, hence the first line.  An anchor goes
as the commentary says, only before headlines or nowhere for a buffer
above its limits, as it also says.  Each N counts in the widened
buffer, without that first line, nor the two blank lines before each
anchor: pandoc takes what comes before a headline or a footnote into
the footnote before it, and these end that footnote."
  (save-excursion
    (save-restriction
      (widen)
      (let* ((case-fold-search t)
             (bytes (1- (position-bytes (point-max))))
             (anchors (when-let* (((<= bytes imprimeur-sync--search-limit))
                                  (closers (imprimeur-sync--closers)))
                        (if (and (<= bytes imprimeur-sync--anchor-limit)
                                 (<= (count-lines (point-min) (point-max)) imprimeur-sync--line-limit))
                            (imprimeur-sync--elements closers)
                          (imprimeur-sync--headlines closers))))
             (pieces (list "#+OPTIONS: H:9\n"))
             (from (point-min))
             (line 1))
        (dolist (anchor anchors)
          (setq line (+ line (count-lines from anchor)))
          (push (buffer-substring-no-properties from anchor) pieces)
          (push (format "\n\n#+IMPRIMEUR_LINE: %d\n" line) pieces)
          (setq from anchor))
        (push (buffer-substring-no-properties from (point-max)) pieces)
        (mapconcat #'identity (nreverse pieces))))))

(provide 'imprimeur-sync)

;;; imprimeur-sync.el ends here

;;; imprimeur-sync.el --- A page and its source in step  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The first half of this file gives the blocks of an Org page their lines, and
;; the second makes the page and its source follow each other's scrolling.
;;
;; pandoc's Org reader says nothing of where a block comes from, so the text
;; sent to it holds anchors: `#+IMPRIMEUR_LINE: N' before a block whose first
;; line is line N of the widened buffer.  pandoc reads an anchor as a raw block
;; of its own, and the filter and the page make it a data-line on the block
;; after it.
;;
;; The anchors go before each headline and where each element of a section
;; starts, before its affiliated keywords; never before a planning line, a
;; drawer, a keyword or a comment, and never inside a list, a paragraph, a
;; footnote or a span, which is what pandoc reads as one inline up to its closer,
;; over any line: maths in \[, \( or $$, raw text in @@ and a LaTeX environment.
;; What decides is how pandoc will read each line, since an anchor where it sees
;; none of these splits what it would have joined, or shows as text.  So this is a
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
;; hold a headline, an opener or a closer, or spans open and close more often than
;; that, or above `imprimeur-sync--search-limit' bytes, nothing gets one, and the
;; page goes by proportion.  In Emacs 31.1 on one laptop, byte-compiled, that same
;; limit of short lines took 0.07 s, or 0.4 s not compiled, and the worst shape
;; found, lines of openers indented as far as the size allows, 0.4 s at 2 MiB and
;; 1.8 s at 8 MiB.  One render runs at a time, and pandoc takes far longer at that
;; size.
;;
;; The scanner is not pandoc's parser either, so an anchor can change what pandoc
;; reads, and the page then differs from pandoc's own export of the document.
;; Each pair of 91 block constructs but five, the fixtures and real files read the
;; same with anchors and without, and so does each of 20 inline openers with 12
;; kinds of line in it, but for what follows: evidence, and no proof.  The realistic
;; cases are where pandoc reads on past what Org ends.  An anchor ends it there, so
;; the page follows Org: pandoc takes the line after a line break `\\' into its
;; paragraph, even a headline or across one blank line, keeps in a footnote what
;; comes two blank lines after a list in it, and lets verbatim, code, a link's
;; description and maths in single dollars go on for a line or two, whatever these
;; look like.  The fixture departures.org pins these.  A LaTeX command whose argument
;; goes on takes the anchor into it, and pandoc writes neither for the page, unless
;; it knows the command as a symbol, whose text is then lost.  Reading the spans is
;; the other way round: one that opens in verbatim, as =\[=, is no span to pandoc,
;; and the lines up to its closer lose their anchors.  Random documents found
;; stranger ones: a lone `::', an empty footnote before a headline, `#+end_src  x',
;; a lone `+---+---+' before text, lines of a verse block.
;;
;; `imprimeur-sync--next' is the scanner's one decision, pure and judged by a
;; table.  `imprimeur-sync--class', `imprimeur-sync--span-end',
;; `imprimeur-sync--closers', `imprimeur-sync--headlines' and
;; `imprimeur-sync--elements' read the document, which is untrusted: together they
;; are the parser at the boundary, which is why each may have a single caller.
;;
;; `imprimeur-follow-mode' is the reader's switch for scroll sync.  Both of its
;; hooks call `imprimeur-sync--window-moved', which only arms a timer, as one of
;; them runs during redisplay, where nothing should write to a process; the timer
;; tells the pages where the source is, at most once per
;; `imprimeur-sync--interval'.  Each move of the window start has its number, the
;; seq of the event `scroll', and a page moves for a number that it has not
;; applied.  So the same number can carry point's line alone, or tell a page that
;; has just reported a revision where to go, and move none that knows already.
;;
;; A move is the window start leaving its text, whose line an edit above changes
;; without moving anything: the page keeps what it shows at its top when the new
;; revision comes, which the browser's scroll anchoring sees to.  A move and an edit
;; together name a line of a text that the page does not hold yet, so that move has
;; a new number when a page reports holding it.  Text that goes in at the window
;; start is one of these: the source shows it at its top, and the page comes to it.

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'imprimeur-server)
;; Loaded when a double-click needs them: see `imprimeur-sync-goto'.
(declare-function org-reveal "org" (&optional siblings))
(declare-function outline-show-entry "outline" ())
(declare-function pulse-momentary-highlight-one-line "pulse" (&optional point face))

(defconst imprimeur-sync--anchor-limit (* 2 1024 1024)
  "The size in bytes of a buffer above which only headlines get anchors.")

(defconst imprimeur-sync--line-limit 32768
  "The most lines of a buffer that Lisp reads for its anchors.
Above this many lines, only headlines get anchors, and none do when
more than this many lines hold a headline, an opener or a closer, or
spans open and close more often than this.  At 2 MiB, it lets through
lines of 64 bytes on average.")

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
    (drawer "[ \t]*:[^ \t\n:]+:[ \t]*$" ":end:"))
  "How pandoc's Org reader sees a line, ignoring case: the first match wins.
Each entry is (CLASS REGEXP CLOSER), and a line that matches none is of
the class `text'.  CLOSER, if any, is what another line must start with
for this one to open a region that pandoc reads as a whole, across any
headline; with `format', it receives the region's name, REGEXP's first
group.  Without such a line this entry does not apply.  A name is in
ASCII, whose case folding searches agree on.  No repetition may go on
where what follows it could match too: on a line of megabytes, that
overflows the regexp matcher's stack.  One limit remains: pandoc also
ends a region at a closer that goes on, as `#+end_srcfoo' ends `src',
and an anchor can then show in the code of such a document.")

(defconst imprimeur-sync--span-regexp
  "\\\\[[(]\\|\\$\\$\\|@@[-[:alnum:]]+:\\|\\\\begin{\\([-*_a-z0-9]+\\)}"
  "What opens a span, anywhere on a line that pandoc reads as inline text.
pandoc reads what follows as one inline up to its closer, over any line,
blank or a headline, and takes an anchor there for its text; or, for an
environment it does not know, as the text it is, unless that stands
alone between lines of its own: it is simpler to take any for a span,
which costs anchors alone.  The first group is an environment's name.")

(defconst imprimeur-sync--span-closers
  '((?\[ . "\\]") (?\( . "\\)") (?$ . "$$") (?@ . "@@") (?b . "\\end{%s}"))
  "The closer of a span, by the second character of its opener in lower case.
With `format', it receives the name of the environment, if any.")

(defconst imprimeur-sync--closer-regexp
  "^[ \t]*\\(#\\+end_[-_a-z0-9]+\\|:end:\\)\\|\\(\\\\[][()]\\|\\$\\$\\|@@\\|\\\\\\(?:begin\\|end\\){[-*_a-z0-9]+}\\)"
  "What closes a region or a span, or opens a span.
The first group is the closer of a region, which starts a line, and
the second what closes or opens a span, anywhere on a line.")

(defconst imprimeur-sync--headline-or-opener-regexp
  (concat "^\\(?:\\*+ \\|[ \t]*\\(?:#\\+begin_\\|:[^ \t\n:]+:[ \t]*$\\)\\)\\|"
          imprimeur-sync--span-regexp)
  "A headline, or a line that may open a region or a span.")

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

(defun imprimeur-sync--span-end (class closers)
  "From a line of CLASS, move point past each span that opens there.
See `imprimeur-sync--span-regexp'.  A span may end on a later line, where
another may open.  An opener with no closer after it is text.  Other
classes hold no text that pandoc reads on from: what a list item holds
ends with it, and so do a caption and a fixed-width line.  CLOSERS is as
`imprimeur-sync--closers' gives."
  (when (memq class '(text headline note table keyword))
    (while (re-search-forward imprimeur-sync--span-regexp (pos-eol) t)
      (let ((closer (downcase (format (alist-get (downcase (char-after (1+ (match-beginning 0))))
                                                 imprimeur-sync--span-closers)
                                      (match-string-no-properties 1)))))
        (when (> (gethash closer closers 0) (point))
          (search-forward closer nil t))))))

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
than `imprimeur-sync--line-limit' lines hold one, or when spans open or
close more often than that."
  (let ((closers (make-hash-table :test #'equal))
        (lines 0))
    (goto-char (point-min))
    (while (and (<= lines imprimeur-sync--line-limit)
                (re-search-forward imprimeur-sync--closer-regexp nil t))
      (puthash (downcase (match-string-no-properties (if (match-beginning 1) 1 2))) (point) closers)
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
      (let* ((here (point))
             (class (imprimeur-sync--class nil closers)))
        (when (eq class 'headline)
          (push here anchors))
        (imprimeur-sync--span-end class closers))
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
        (unless (natnump (cadr state))
          (imprimeur-sync--span-end class closers))
        (forward-line 1)))
    (nreverse anchors)))

(defun imprimeur-sync-org-text ()
  "Return the text to send to pandoc for this Org buffer, widened.
pandoc's default H:3 would turn deeper headlines into list items, and
a later #+OPTIONS still wins, hence the first line.  An anchor goes
as the commentary says, only before headlines or nowhere for a buffer
above its limits, as it also says, and nowhere when the scanner fails,
which goes in the log: the page is worth more than its lines.  It also
says where an anchor can change what pandoc reads.  Each N counts in
the widened buffer, without that first line, nor the two blank lines
before each anchor: pandoc takes what comes before a headline or a
footnote into the footnote before it, and these end that footnote."
  (save-excursion
    (save-restriction
      (widen)
      (let* ((case-fold-search t)
             (bytes (1- (position-bytes (point-max))))
             (anchors (condition-case failure
                          (when-let* (((<= bytes imprimeur-sync--search-limit))
                                      (closers (imprimeur-sync--closers)))
                            (if (and (<= bytes imprimeur-sync--anchor-limit)
                                     (<= (count-lines (point-min) (point-max)) imprimeur-sync--line-limit))
                                (imprimeur-sync--elements closers)
                              (imprimeur-sync--headlines closers)))
                        (error (imprimeur-log "No anchors: %s" (error-message-string failure))
                               nil)))
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

;;;; Following

(defcustom imprimeur-scroll-sync 'both
  "Which way a page and its source follow each other's scrolling.
`both', each follows the other; `to-preview', the page follows the
source alone; nil, neither, and `imprimeur-follow-mode' stays off in a
new session until it is turned on by hand, when each follows the other."
  :type '(choice (const :tag "Each follows the other" both)
                 (const :tag "The page follows the source" to-preview)
                 (const :tag "Neither" nil))
  :group 'imprimeur)

(defconst imprimeur-sync--interval 0.05
  "The least seconds between two reports to the pages.")

(cl-defstruct (imprimeur-sync--state (:constructor imprimeur-sync--state-create) (:copier nil))
  "What the following of one source buffer knows.
BUFFER is the source and SEND, a function of an event's name and its
data, reaches its pages.  SEQ numbers the moves of the window start.
START and POINT are what the pages know: a marker on the window start,
which an edit above carries along as it does the window start itself,
and which passes what goes in at that place, where the window start
stays; or on nothing; and the line of point, or nil.  SHOWN is the text
of the revision that a page last reported, as
`buffer-chars-modified-tick' says, or nil, and AHEAD is non-nil when a
move was told in a later text than that.  SENT-AT is the time of the
last report, and TIMER the one armed for the next, or nil."
  buffer send (seq 0) (start (copy-marker nil t)) point shown ahead (sent-at 0) timer)

(defvar-local imprimeur-sync--state nil
  "The following of this buffer's session, or nil.")
(put 'imprimeur-sync--state 'permanent-local t)

(defun imprimeur-sync--delay (sent-at now)
  "Return the seconds to wait at NOW before a report, the last one at SENT-AT.
They are what remains of `imprimeur-sync--interval': none once it is
over, and no more than it if the clock has gone back."
  (max 0 (min imprimeur-sync--interval (- (+ sent-at imprimeur-sync--interval) now))))

(defun imprimeur-sync--judge (known-start known-point start point)
  "Decide what to tell the pages of a source at START, point on line POINT.
They know KNOWN-START, as far as an edit has carried it, and KNOWN-POINT.
Return `move' when the window start has moved, which they are to follow;
`point' when the line of point has changed, by a move or an edit; and
nil otherwise, as for the echo of a scroll that a page asked for."
  (cond ((not (eql start known-start)) 'move)
        ((not (eql point known-point)) 'point)))

(defun imprimeur-sync--follows-page-p (follow option seq latest)
  "Decide whether the source moves for a scroll that a page has posted.
FOLLOW is `imprimeur-follow-mode' and OPTION `imprimeur-scroll-sync'.
SEQ is the last move of the window start that the page had applied, and
LATEST the last that Emacs has made.  A page that is behind is about to
go where Emacs tells it, so that both end in the same place."
  (and follow (not (eq option 'to-preview)) (eql seq latest)))

(defun imprimeur-sync--line-position (line)
  "Return where LINE of the widened buffer starts, kept within the narrowing."
  (let ((position (save-restriction
                    (widen)
                    (save-excursion
                      (goto-char (point-min))
                      (forward-line (1- line))
                      (point)))))
    (max (point-min) (min position (point-max)))))

(defun imprimeur-sync-total ()
  "Return how many lines this buffer has, widened."
  (save-restriction (widen) (count-lines (point-min) (point-max))))

(defun imprimeur-sync--cancel (state)
  "Cancel the report that STATE has armed, if any."
  (when-let* ((timer (imprimeur-sync--state-timer state)))
    (cancel-timer timer)
    (setf (imprimeur-sync--state-timer state) nil)))

(defun imprimeur-sync--report (state &optional again)
  "Tell the pages of STATE where the source is, if that has changed.
AGAIN tells them even so, with the number of the last move.  The source
is where the Emacs window showing it starts or, when none does, where
point is.  A line counts in the widened buffer, whatever the narrowing."
  (imprimeur-sync--cancel state)
  (when-let* ((buffer (imprimeur-sync--state-buffer state))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (let* ((window (get-buffer-window buffer t))
             (start (if window (window-start window) (point)))
             (point (line-number-at-pos (if window (window-point window) (point)) t))
             (shown (imprimeur-sync--state-shown state))
             (change (imprimeur-sync--judge (marker-position (imprimeur-sync--state-start state))
                                            (imprimeur-sync--state-point state)
                                            start point)))
        (when (or change again)
          (when (eq change 'move)
            (cl-incf (imprimeur-sync--state-seq state))
            (setf (imprimeur-sync--state-ahead state)
                  (and shown (/= shown (buffer-chars-modified-tick)))))
          (set-marker (imprimeur-sync--state-start state) start buffer)
          (setf (imprimeur-sync--state-point state) point
                (imprimeur-sync--state-sent-at state) (float-time))
          (funcall (imprimeur-sync--state-send state) "scroll"
                   (list :line (line-number-at-pos start t)
                         :total (imprimeur-sync-total)
                         :point point
                         :seq (imprimeur-sync--state-seq state))))))))

(defun imprimeur-sync--window-moved (&rest _)
  "Arm the next report of where the source is, unless one is armed.
Both `post-command-hook' and `window-scroll-functions' call this."
  (when-let* ((state imprimeur-sync--state)
              ((not (imprimeur-sync--state-timer state))))
    (setf (imprimeur-sync--state-timer state)
          (run-at-time (imprimeur-sync--delay (imprimeur-sync--state-sent-at state) (float-time))
                       nil #'imprimeur-sync--report state))))
(put 'imprimeur-sync--window-moved 'permanent-local-hook t)

(define-minor-mode imprimeur-follow-mode
  "Make this buffer and its page follow each other's scrolling.
It comes on with a session unless `imprimeur-scroll-sync' is nil, which
also says the directions.  Turned off, neither moves for the other,
though a double-click in the page and `imprimeur-jump' still go where
they are asked; turned on, the page aligns with the source at once.  It
has no effect on rendering."
  :lighter nil
  :group 'imprimeur
  (cond ((not imprimeur-follow-mode)
         (remove-hook 'post-command-hook #'imprimeur-sync--window-moved t)
         (remove-hook 'window-scroll-functions #'imprimeur-sync--window-moved t)
         (when imprimeur-sync--state (imprimeur-sync--cancel imprimeur-sync--state)))
        (imprimeur-sync--state
         (add-hook 'post-command-hook #'imprimeur-sync--window-moved nil t)
         (add-hook 'window-scroll-functions #'imprimeur-sync--window-moved nil t)
         (set-marker (imprimeur-sync--state-start imprimeur-sync--state) nil)
         (imprimeur-sync--report imprimeur-sync--state))
        (t (setq imprimeur-follow-mode nil)
           (user-error "No imprimeur session in this buffer"))))
(put 'imprimeur-follow-mode 'permanent-local t)

(defun imprimeur-sync-start (send)
  "Start the following of this buffer's session.
SEND, a function of an event's name and its data, reaches its pages."
  (setq imprimeur-sync--state (imprimeur-sync--state-create :buffer (current-buffer) :send send))
  (when imprimeur-scroll-sync (imprimeur-follow-mode 1)))

(defun imprimeur-sync-stop ()
  "End the following in this buffer, with its hooks and its timer."
  (imprimeur-follow-mode -1)
  (setq imprimeur-sync--state nil))

(defun imprimeur-sync-page-scrolled (line seq)
  "Bring LINE to the start of the Emacs window showing this buffer, if any.
A page has scrolled there, having applied the move SEQ of the window
start: see `imprimeur-sync--follows-page-p'.  Folds are the reader's: a
line that a fold hides leaves it closed, and the window start rests on
the line that holds it.  The pages know where it rests, so that the
report after this tells them nothing, and the page stays where the
reader put it."
  (when-let* ((state imprimeur-sync--state)
              ((imprimeur-sync--follows-page-p imprimeur-follow-mode imprimeur-scroll-sync seq
                                               (imprimeur-sync--state-seq state)))
              (window (get-buffer-window (current-buffer) t)))
    (let ((start (imprimeur-sync--line-position line)))
      (while (and (> start (point-min)) (invisible-p start))
        (setq start (max (point-min) (1- (previous-single-char-property-change start 'invisible)))))
      (save-excursion
        (goto-char start)
        (setq start (pos-bol)))
      (set-window-start window start)
      (set-marker (imprimeur-sync--state-start state) start))))

(defun imprimeur-sync-goto (line)
  "Put point on LINE of the widened buffer, kept within the narrowing.
A double-click in a page asks for it, whatever `imprimeur-follow-mode'
says.  The buffer is shown if it is hidden, a fold that hides the line
opens, unless nothing here can open it, and the line flashes."
  (require 'pulse)
  (let ((position (imprimeur-sync--line-position line))
        (window (or (get-buffer-window (current-buffer) t) (display-buffer (current-buffer)))))
    (goto-char position)
    (when (invisible-p position)
      (ignore-errors
        (if (derived-mode-p 'org-mode)
            (org-reveal)
          (require 'outline)
          (outline-show-entry))))
    (when window (set-window-point window position))
    (pulse-momentary-highlight-one-line position)
    (when imprimeur-follow-mode (imprimeur-sync--window-moved))))

(defun imprimeur-sync-page-ready (tick)
  "Tell a page that has reported a revision where the source is.
So the first one aligns it, and any other, that knows, does not move,
unless a move was told in a later text, which this revision holds.  TICK
is its text, as `buffer-chars-modified-tick' says, or nil for one that
is not the latest."
  (when imprimeur-follow-mode
    (let ((state imprimeur-sync--state))
      (setf (imprimeur-sync--state-shown state) tick)
      (when (and (imprimeur-sync--state-ahead state) (eql tick (buffer-chars-modified-tick)))
        (setf (imprimeur-sync--state-ahead state) nil)
        (cl-incf (imprimeur-sync--state-seq state)))
      (imprimeur-sync--report state t))))

(provide 'imprimeur-sync)

;;; imprimeur-sync.el ends here

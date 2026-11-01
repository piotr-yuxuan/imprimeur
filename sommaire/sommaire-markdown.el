;;; sommaire-markdown.el --- The Markdown adapter of sommaire  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; Reads a Markdown buffer into the outline of `sommaire-rules-outline', as
;; "What an adapter puts in the tree" in docs/minitoc-rules.md says.  It is
;; a scanner of its own that reads only the buffer's text, so it gives the
;; same outline in markdown-mode, gfm-mode, markdown-ts-mode or no mode.
;;
;; The document is untrusted.  The scanner follows the block structure of
;; CommonMark, as pandoc reads it, line by line and at the outermost level
;; only: a line is of a kind, which `sommaire-markdown--kinds' decides from
;; the line alone and the paragraph left open before it.  What lies in a
;; block quote, a list item or a footnote definition is skipped by its
;; column, since no heading there is eligible.  The work is linear in the
;; size of the part it reads, which `sommaire-rules-check-size' bounds.
;;
;; A container's inner blocks are not followed, only each of its lines, so
;; a line after a fence in a list item may pass for the lazy continuation of
;; a paragraph, which matters only if a setext underline or an HTML tag comes
;; next.  A pipe table counts as a paragraph, so a line of hyphens right below
;; one is an underline, and so does a footnote definition whose label holds an
;; escaped bracket.  Front matter is a block that starts as a YAML mapping and
;; that its delimiters close; the rest of its YAML is not read.
;;
;; `sommaire-markdown--read', `--front-matter', `--step', `--block', `--table',
;; `--add-underlined' and `--assemble' each have one caller: they are the
;; stages of one parser at the boundary, split where the limit on complexity
;; asks, and they share the plist STATE that `sommaire-markdown--read' makes.
;; Their contract is that of `sommaire-markdown-outline', and the fixtures and
;; pandoc judge them through it, so they have no tests of their own.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'sommaire-rules)

(defconst sommaire-markdown--longest-title 1024
  "The characters of a heading's text that are read, so that work stays bounded.")

(defconst sommaire-markdown--html-block-names
  '("address" "article" "aside" "base" "basefont" "blockquote" "body" "caption"
    "center" "col" "colgroup" "dd" "details" "dialog" "dir" "div" "dl" "dt"
    "fieldset" "figcaption" "figure" "footer" "form" "frame" "frameset" "h1" "h2"
    "h3" "h4" "h5" "h6" "head" "header" "hr" "html" "iframe" "legend" "li" "link"
    "main" "menu" "menuitem" "meta" "nav" "noframes" "ol" "optgroup" "option" "p"
    "param" "search" "section" "summary" "table" "tbody" "td" "tfoot" "th" "thead"
    "title" "tr" "track" "ul")
  "The tags that start an HTML block in CommonMark, closed by a blank line.")

(defconst sommaire-markdown--blank-or-div-tag
  "\\` *\\(?:</?div\\(?: [^>]*\\)?> *\\)?\\'"
  "A line that is blank, or a tag of a `<div>' alone: not substantive.")

(defconst sommaire-markdown--footnote-mark
  "\\[\\^ *[^] [][^][]*\\]:"
  "What starts a footnote definition: a label with no bracket, not only spaces.")

(defconst sommaire-markdown--kinds
  (let ((anywhere '(nil paragraph lazy definition)))
    `((underline "\\`\\(?:=+\\|-+\\) *\\'" paragraph)
      (atx "\\`#\\{1,6\\}\\(?: \\|\\'\\)" ,@anywhere)
      (fence "\\`\\(?:`\\{3,\\}[^`]*\\|~\\{3,\\}.*\\)\\'" ,@anywhere)
      (comment "\\`<!--" ,@anywhere)
      (html-cdata "\\`<!\\[CDATA\\[" ,@anywhere)
      (html-declaration "\\`<![a-z]" ,@anywhere)
      (html-instruction "\\`<\\?" ,@anywhere)
      (html-raw "\\`<\\(?:pre\\|script\\|style\\|textarea\\)\\(?:[ >]\\|\\'\\)" ,@anywhere)
      (div ,sommaire-markdown--blank-or-div-tag ,@anywhere)
      (html-block
       ,(concat "\\`</?" (regexp-opt sommaire-markdown--html-block-names) "\\(?:[ >]\\|/>\\|\\'\\)")
       ,@anywhere)
      ;; As in pandoc, which lets a lone tag end a lazy paragraph.
      (html-tag "\\`</?[a-z][a-z0-9-]*\\(?: [^<>]*\\)?/?> *\\'" nil lazy)
      (break "\\`\\([-*_]\\) *\\(?:\\1 *\\)\\{2,\\}\\'" ,@anywhere)
      (block-quote "\\`>" ,@anywhere)
      (item "\\`\\(?:[-+*]\\|[0-9]\\{1,9\\}[.)]\\)\\(?: \\|\\'\\)" nil lazy)
      ;; Only a non-empty item starting at 1 can interrupt a paragraph.
      (item "\\`\\(?:[-+*]\\|0*1[.)]\\) +[^ ]" paragraph definition)
      ;; A footnote definition is a container that any line can start.
      (item ,(concat "\\`" sommaire-markdown--footnote-mark) ,@anywhere)
      (definition
       ,(concat "\\`\\[[^]^][^]]*\\]: *\\(?:<[^>]*>\\|[^ <][^ ]*\\)"
                "\\(?: +\\(?:\"[^\"]*\"\\|'[^']*'\\|([^)]*)\\)\\)? *\\'")
       nil definition)))
  "The kinds of a line that starts a block, first match first.
Each row is (KIND REGEXP . OPEN), where REGEXP reads the line without its
indentation, and OPEN lists what must be open before the line: nothing,
`paragraph' for a paragraph outside any container, `lazy' for one inside
a container, which a line can still continue lazily, or
`definition' for link definitions, which open a paragraph that they then
leave empty, so that no underline can make it a heading.")

(defconst sommaire-markdown--container-marks
  (concat "\\` *\\(?:\\(?:>\\|" sommaire-markdown--footnote-mark
          "\\|\\(?:[-+*]\\|[0-9]\\{1,9\\}[.)]\\)\\(?: \\|\\'\\)\\) *\\)*")
  "What starts a line in a container, before its content.")

(defconst sommaire-markdown--closers
  (let ((blank-line "\\` *\\'"))
    `((comment . "-->")
      (html-cdata . "]]>")
      (html-declaration . ">")
      (html-instruction . "\\?>")
      (html-raw . "</\\(?:pre\\|script\\|style\\|textarea\\)>")
      (div . ,blank-line)
      (html-block . ,blank-line)
      (html-tag . ,blank-line)))
  "The kinds of an HTML line that opens a block, with what ends that block.")

(defconst sommaire-markdown--quiet-kinds '(blank atx underline comment div definition)
  "The kinds of a line that is not substantive.")

(defconst sommaire-markdown--table-start
  (concat "<!-- *\\(?:markdown-toc start"
          "\\|:toc\\(?:[@_][0-9]\\(?:[@_][a-z]+\\)?\\)?:[^ ]* *-->\\)")
  "The marker of a markdown-toc or toc-org table: rule R2.")

(defconst sommaire-markdown--table-end "<!-- *markdown-toc end"
  "What ends a markdown-toc table; the next heading ends either kind of table.")

(defvar-local sommaire-markdown--cache nil
  "The last outline of this buffer, as a pair (KEY . OUTLINE).")

(defun sommaire-markdown--untabify (line)
  "Return LINE with each tab as the spaces up to the next stop of 4 columns."
  (if (string-search "\t" line)
      (let ((column 0))
        (mapconcat (lambda (character)
                     (let ((width (if (eq character ?\t) (- 4 (% column 4)) 1)))
                       (setq column (+ column width))
                       (if (eq character ?\t)
                           (make-string width ?\s)
                         (string character))))
                   line ""))
    line))

(defun sommaire-markdown--kind (line open)
  "Return the kind of LINE, which has no tab, given OPEN.
The value is `blank', `code', `text' or a kind of the table
`sommaire-markdown--kinds', which says what OPEN is."
  (let ((column (string-match "[^ ]" line)))
    (cond ((null column) 'blank)
          ((>= column 4) (if open 'text 'code))
          (t (let ((text (substring line column)))
               (or (car (seq-find (lambda (row)
                                    (and (memq open (cddr row))
                                         (string-match-p (cadr row) text)))
                                  sommaire-markdown--kinds))
                   'text))))))

(defun sommaire-markdown--open-in-container (line)
  "Return what LINE, in a container, leaves open.
That is `lazy' when it holds a paragraph, which a later line can continue
lazily, and nil otherwise.  Only this line is read."
  (string-match sommaire-markdown--container-marks line)
  (and (eq (sommaire-markdown--kind (substring line (match-end 0)) nil) 'text)
       'lazy))

(defun sommaire-markdown--parse-atx (line)
  "Return (LEVEL . TEXT) of the ATX heading LINE, without its closing marks."
  (string-match "\\` *\\(#+\\)\\(.*\\)\\'" line)
  (cons (length (match-string 1 line))
        (replace-regexp-in-string " +#+ *\\'" "" (match-string 2 line))))

(defun sommaire-markdown--closer (kind line)
  "Return the regexp of the line that ends the block that LINE, of KIND, opens.
Return nil when LINE opens no block, or ends it itself.  A fence ends at
the same mark taken at least as many times and nothing else, and a length
beyond what a regexp can count stays at that limit."
  (if (eq kind 'fence)
      (progn
        (string-match "[`~]+" line)
        (format "\\` \\{0,3\\}%c\\{%d,\\} *\\'"
                (aref line (match-beginning 0))
                (min 65535 (- (match-end 0) (match-beginning 0)))))
    (let ((closer (alist-get kind sommaire-markdown--closers)))
      (and closer (not (string-match-p closer line)) closer))))

(defun sommaire-markdown--item-offset (line)
  "Return the column where the content of the item that LINE starts begins.
For a footnote definition, it is column 4, whatever the line holds.  For a
list item, it is the column after the marker and its spaces, or after the
marker and one space when five spaces start an indented block or nothing
follows.  A list item begins with at most one blank line, so an empty one
before a blank line holds nothing, and the value is then nil.  Point is at
LINE."
  (if (string-match-p "\\` *\\[" line)
      4
    (string-match "\\` *\\(?:[-+*]\\|[0-9]+[.)]\\)\\( *\\)" line)
    (let ((after-marker (match-beginning 1))
          (content (match-end 1)))
      (cond ((= content (length line))
             (save-excursion
               (forward-line)
               (and (not (looking-at-p "[ \t]*$")) (1+ after-marker))))
            ((<= (- content after-marker) 4) content)
            (t (1+ after-marker))))))

(defun sommaire-markdown--yaml-scalar (text)
  "Return the string of the YAML scalar TEXT, or nil when it is not on one line.
TEXT is what follows a key's colon and its spaces: a double-quoted string,
a single-quoted one, or a plain one, each with an optional comment."
  (cond
   ((string-match "\\`\"\\(\\(?:[^\"\\]\\|\\\\.\\)*\\)\" *\\(?:#.*\\)?\\'" text)
    (replace-regexp-in-string "\\\\\\(.\\)" "\\1" (match-string 1 text) t))
   ((string-match "\\`'\\(\\(?:[^']\\|''\\)*\\)' *\\(?:#.*\\)?\\'" text)
    (string-replace "''" "'" (match-string 1 text)))
   ((string-match "\\`\\([^][{}|>&*!%@`#'\" ].*?\\)\\(?: +#.*\\)? *\\'" text)
    (match-string 1 text))))

(defun sommaire-markdown--front-matter ()
  "Move point past the front matter that starts at it, and return its title.
Front matter starts at the first position of the buffer, on a line of
three hyphens that comments and then a mapping's key or the last delimiter
follow, and ends at a line of three hyphens or three dots.  Without one,
return nil and leave point."
  (let ((end (and (= (point) 1)
                  (looking-at (concat "---[ \t]*\n\\(?:[ \t]*#.*\n\\)*"
                                      "\\(?:[ \t]*[^ \t\n#-][^:\n]*:\\(?:[ \t]\\|$\\)"
                                      "\\|\\(?:---\\|\\.\\.\\.\\)[ \t]*$\\)"))
                  (save-excursion
                    (forward-line)
                    (re-search-forward "^\\(?:---\\|\\.\\.\\.\\)[ \t]*$" nil t))))
        (case-fold-search nil))
    (when end
      (prog1 (and (re-search-forward "^title:[ \t]+\\(.*\\)$" end t)
                  (sommaire-markdown--yaml-scalar
                   (string-replace "\t" " " (match-string-no-properties 1))))
        (goto-char end)
        (forward-line)))))

(defun sommaire-markdown--mark-substantive (state)
  "Record in STATE that the last heading has an introduction, outside a table."
  (unless (plist-get state :table)
    (plist-put (car (plist-get state :headings)) :intro t)))

(defun sommaire-markdown--table (state line)
  "Record in STATE whether LINE, a comment or a heading, opens or ends a table."
  (cond ((string-match-p sommaire-markdown--table-start line)
         (plist-put state :table t)
         (plist-put (plist-get state :document) :explicit t))
        ((string-match-p sommaire-markdown--table-end line)
         (plist-put state :table nil))))

(defun sommaire-markdown--add-heading (state level text begin)
  "Add to STATE a heading of LEVEL and TEXT, which starts at BEGIN.
Point is on its last line, and a heading ends any table."
  (plist-put state :table nil)
  (plist-put state :headings
             (cons (list :level level
                         :title (string-join
                                 (split-string
                                  (replace-regexp-in-string
                                   "<!--.*?-->" ""
                                   (substring text 0 (min (length text)
                                                          sommaire-markdown--longest-title))))
                                 " ")
                         :intro nil
                         :begin begin
                         :body (save-excursion
                                 (forward-line)
                                 (skip-chars-forward " \t\n")
                                 (pos-bol))
                         :end (point-max))
                   (plist-get state :headings))))

(defun sommaire-markdown--add-underlined (state line)
  "Make the open paragraph of STATE a heading, as its underline LINE says.
The paragraph was no introduction after all."
  (let ((begin (car (plist-get state :paragraph))))
    (plist-put (car (plist-get state :headings)) :intro (cdr (plist-get state :paragraph)))
    (sommaire-markdown--add-heading state
                                    (if (string-search "=" line) 1 2)
                                    (buffer-substring-no-properties begin (point))
                                    begin)))

(defun sommaire-markdown--block (state line)
  "Advance STATE past LINE, which starts at point, in no container or open block."
  (let* ((open (plist-get state :open))
         (kind (sommaire-markdown--kind line open))
         (continuing (and (memq open '(paragraph lazy)) (eq kind 'text))))
    (unless continuing
      (plist-put state :offset (and (eq kind 'item) (sommaire-markdown--item-offset line)))
      (plist-put state :open
                 (if (memq kind '(block-quote item))
                     (sommaire-markdown--open-in-container line)
                   (alist-get kind '((text . paragraph) (definition . definition)))))
      (when (eq kind 'text)
        (plist-put state :paragraph
                   (cons (point) (plist-get (car (plist-get state :headings)) :intro)))))
    (unless (memq kind sommaire-markdown--quiet-kinds)
      (sommaire-markdown--mark-substantive state))
    (plist-put state :quiet (eq kind 'comment))
    (plist-put state :closer (sommaire-markdown--closer kind line))
    (when (eq kind 'underline)
      (sommaire-markdown--add-underlined state line))
    (when (eq kind 'atx)
      (let ((heading (sommaire-markdown--parse-atx line)))
        (sommaire-markdown--add-heading state (car heading) (cdr heading) (point))))
    (when (memq kind '(atx comment))
      (sommaire-markdown--table state line))))

(defun sommaire-markdown--step (state line)
  "Advance STATE past LINE, which starts at point and has no tab.
In a block that LINE does not close, it counts only as its text; in an
item, a blank line or one indented as far as the content belongs to it."
  (let ((closer (plist-get state :closer))
        (offset (plist-get state :offset))
        (column (string-match "[^ ]" line)))
    (cond
     (closer
      (unless (or (plist-get state :quiet)
                  (string-match-p sommaire-markdown--blank-or-div-tag line))
        (sommaire-markdown--mark-substantive state))
      (when (string-match-p closer line)
        (plist-put state :closer nil)))
     ((and offset (or (null column) (>= column offset)))
      (plist-put state :open (sommaire-markdown--open-in-container line)))
     (t (sommaire-markdown--block state line)))))

(defun sommaire-markdown--assemble (document headings)
  "Return the outline of DOCUMENT over HEADINGS, in document order.
The first heading becomes the root when no other is as high, and it has
level 1 or, under narrowing, starts the accessible part: rule R6.  A
heading as high as a subtree ends it, once: `seq-find' here would walk all
the headings for each of them, as it measures its list before it starts."
  (let* ((top (car headings))
         (level (plist-get top :level))
         (promoted (and top
                        (if (buffer-narrowed-p)
                            (= (plist-get top :begin) (point-min))
                          (= level 1))
                        (seq-every-p (lambda (heading) (> (plist-get heading :level) level))
                                     (cdr headings))))
         (others (if promoted (cdr headings) headings))
         ;; The headings whose subtree is still open, innermost first.
         (open nil))
    (dolist (heading others)
      (while (and open (>= (plist-get (car open) :level) (plist-get heading :level)))
        (plist-put (pop open) :end (plist-get heading :begin)))
      (push heading open))
    (sommaire-rules-outline
     (if promoted
         (list :level level
               :title (plist-get top :title)
               :intro (or (plist-get document :intro) (plist-get top :intro))
               :explicit (plist-get document :explicit)
               :begin (point-min)
               :body (plist-get top :body)
               :end (point-max))
       document)
     others)))

(defun sommaire-markdown--read ()
  "Return the outline of this buffer's accessible part, with point anywhere."
  (goto-char (point-min))
  (let* ((title (sommaire-markdown--front-matter))
         (document (list :title (and (not (buffer-narrowed-p)) title)
                         :intro nil
                         :explicit nil
                         :begin (point-min)
                         :body (point)
                         :end (point-max)))
         (state (list :document document
                      :headings (list document)
                      :paragraph nil
                      :open nil
                      :offset nil
                      :closer nil
                      :quiet nil
                      :table nil))
         (case-fold-search t))
    (while (not (eobp))
      (sommaire-markdown--step
       state (sommaire-markdown--untabify (buffer-substring-no-properties (point) (pos-eol))))
      (forward-line))
    (sommaire-markdown--assemble document (cdr (reverse (plist-get state :headings))))))

(defun sommaire-markdown-outline ()
  "Return the outline of the accessible part of this Markdown buffer.
See `sommaire-rules-outline' for its shape.  The value is kept for as
long as the text and the narrowing stay the same, so the caller must not
change it.  A part too large to read, or that the scanner cannot read,
such as one whose line exhausts the stack of the regexp matcher, has only
a root, and a message says why: a document must not break a timer or a
redisplay, or hold them up for long.  Point and the match data stay."
  (let ((key (list (buffer-chars-modified-tick) (point-min) (point-max))))
    (unless (equal key (car sommaire-markdown--cache))
      (setq sommaire-markdown--cache
            (cons key
                  (save-match-data
                    (save-excursion
                      (condition-case failure
                          (progn
                            (sommaire-rules-check-size (- (point-max) (point-min)))
                            (sommaire-markdown--read))
                        (error
                         (message "sommaire: cannot read the headings of this buffer: %s"
                                  (error-message-string failure))
                         (sommaire-rules-outline
                          (list :begin (point-min) :body (point-min) :end (point-max))
                          nil))))))))
    (cdr sommaire-markdown--cache)))

(provide 'sommaire-markdown)

;;; sommaire-markdown.el ends here

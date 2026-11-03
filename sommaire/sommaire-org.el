;;; sommaire-org.el --- The Org adapter of sommaire  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; Reads an Org buffer into the outline of `sommaire-rules-outline', as
;; "What an adapter puts in the tree" in docs/minitoc-rules.md says.  The
;; document is untrusted, and its parser is Org's, at element granularity.
;;
;; `sommaire-org--read', `sommaire-org--eligible' and `sommaire-org--table-p'
;; each have one caller: they are the stages of one parser at the boundary,
;; split where the limit on complexity asks.  Their contract is that of
;; `sommaire-org-outline', and the fixtures and the tests judge them through
;; it, so they have no tests of their own.
;;
;; A title reads as it is displayed.  `sommaire-org--inline' finds a heading's
;; inline markup by itself, in the way of Org's own parser and not through it:
;; `org-element-parse-secondary-string' took 80 times as long in Org 9.8.7, which
;; on the largest part that is read, in headings of one letter, comes to 30 s
;; after each edit.

;;; Code:

(require 'org-element)
(require 'seq)
(require 'subr-x)
(require 'sommaire-rules)

(defvar org-export-exclude-tags)
(defvar org-todo-regexp)

(defconst sommaire-org--container-tag
  "\\`toc\\(?:[@_][0-9]\\(?:[@_][a-z]+\\)?\\)?\\'"
  "What makes a tag that of a toc-org container, in either case, as for toc-org.")

(defconst sommaire-org--priority-and-comment
  (concat "\\(?:\\[#\\(?:[A-Za-z]\\|[0-9]\\{1,2\\}\\)\\][ \t]*\\)?"
          "\\(?:COMMENT\\(?: [ \t]*\\|\\'\\)\\)?")
  "What a heading may hold between its keyword and its text.")

(defconst sommaire-org--metadata-types '(planning property-drawer drawer)
  "The types of the elements of a section that hold a heading's metadata.")

(defconst sommaire-org--quiet-types
  (append sommaire-org--metadata-types '(keyword comment comment-block))
  "The types of the elements of a section that are not substantive.")

(defconst sommaire-org--inline
  (let ((span (concat "\\(?:\\`\\|\\(?4:[- \t('\"{]\\)\\)\\(?5:[%s]\\)"
                      "\\(?%d:[^ \t]\\|[^ \t].*?[^ \t]\\)\\(?3:\\5\\)"
                      "\\(?:[- \t.,;:!?'\")}\\[]\\|\\'\\)")))
    (concat "\\[\\[\\(?1:[^][]+\\)\\]\\(?:\\[\\(?2:.*?\\)\\]\\)?\\]\\|"
            "<\\(?1:[a-z][-a-z0-9+.]+:[^ \t<>]+\\)>\\|"
            (format span "=~" 1) "\\|" (format span "*/_+" 2)))
  "The inline markup that a title loses, in the groups of `sommaire-rules-plain'.
A link gives its description, or else its address, and emphasis, verbatim and
code give their words.  A mark opens and closes where Org's parser says.")

(defvar-local sommaire-org--cache nil
  "The last outline of this buffer, as a pair (KEY . OUTLINE).")

(defun sommaire-org--headlines (element)
  "Return the headlines directly under ELEMENT."
  (seq-filter (lambda (child) (eq (org-element-type child) 'headline))
              (org-element-contents element)))

(defun sommaire-org--title (headline)
  "Return the title of HEADLINE, as the rules define it, and move point there.
That is its ALT_TITLE, or else the text of its line, and then as it reads.
The line is read here and not through `:raw-value', which depends on the
version of Org: Org 9.8 takes a priority from anywhere in the line, and the
title after it alone."
  (string-join
   (split-string
    (sommaire-rules-plain
     (or (org-string-nw-p (org-element-property :ALT_TITLE headline))
         (let* ((case-fold-search nil)
                (line (progn
                        (goto-char (org-element-property :begin headline))
                        (buffer-substring-no-properties (pos-bol) (pos-eol))))
                (text (progn
                        (string-match (concat "\\`\\*+ [ \t]*"
                                              "\\(?:" org-todo-regexp "\\(?: [ \t]*\\|\\'\\)\\)?"
                                              sommaire-org--priority-and-comment)
                                      line)
                        (substring line (match-end 0)))))
           (replace-regexp-in-string
            "\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]" ""
            (replace-regexp-in-string
             "\\(?:\\`\\|[ \t]+\\):[[:alnum:]_@#%:]+:[ \t]*\\'" "" text))))
     sommaire-org--inline))
   " "))

(defun sommaire-org--table-p (element)
  "Return non-nil when ELEMENT, in a section, is an explicit table: rule R2."
  (pcase (org-element-type element)
    ('keyword (let ((value (org-element-property :value element)))
                (and (equal (org-element-property :key element) "TOC")
                     (string-match-p "\\<headlines\\>" value)
                     (string-match-p "\\<local\\>" value))))
    ('drawer (equal (org-element-property :drawer-name element) "CONTENTS"))))

(defun sommaire-org--heading (element title archived)
  "Return the heading of ELEMENT, an `org-data' or a `headline', called TITLE.
An ARCHIVED heading's body is not read."
  (let* ((first-child (car (org-element-contents element)))
         (section (and (eq (org-element-type first-child) 'section)
                       (org-element-contents first-child)))
         (read-section (and (not archived) section))
         (after-metadata (seq-find (lambda (child)
                                     (not (memq (org-element-type child)
                                                sommaire-org--metadata-types)))
                                   (append section (sommaire-org--headlines element)))))
    (list :level (org-element-property :level element)
          :title title
          :archived archived
          :intro (seq-some (lambda (child)
                             (not (memq (org-element-type child) sommaire-org--quiet-types)))
                           read-section)
          :explicit (seq-some #'sommaire-org--table-p read-section)
          :begin (org-element-property :begin element)
          :body (if after-metadata
                    (org-element-property :begin after-metadata)
                  (org-element-property :end element))
          :end (org-element-property :end element))))

(defun sommaire-org--eligible (element root)
  "Return the eligible headings under ELEMENT, the one that ROOT reads.
A toc-org container makes ROOT explicit, and a dropped subtree before a
heading's first child is the introduction of that heading: both change
the heading in place.  The walk is a loop over a stack and does not
recurse, since a document chooses its depth."
  (let ((pending (sommaire-org--headlines element))
        (excluded (if (boundp 'org-export-exclude-tags)
                      org-export-exclude-tags
                    '("noexport")))
        (last-element element)
        (last-heading root)
        (headings nil))
    (while pending
      (let* ((headline (pop pending))
             (tags (org-element-property :tags headline))
             (archived (org-element-property :archivedp headline)))
        (cond
         ((seq-some (lambda (tag) (string-match-p sommaire-org--container-tag tag)) tags)
          (plist-put root :explicit t))
         ((or (org-element-property :commentedp headline)
              (equal (org-element-property :UNNUMBERED headline) "notoc")
              (seq-intersection tags excluded))
          ;; No eligible child came between them, or it would be the last.
          (when (eq (org-element-property :parent headline) last-element)
            (plist-put last-heading :intro t)))
         (t
          (setq last-element headline
                last-heading (sommaire-org--heading
                              headline (sommaire-org--title headline) archived))
          (push last-heading headings)
          (unless archived
            (setq pending (append (sommaire-org--headlines headline) pending)))))))
    (nreverse headings)))

(defun sommaire-org--read (tree)
  "Return the outline of this buffer, whose parse tree is TREE.
Under narrowing, a part that starts at a heading and holds no heading as
high as that one has it as its root: rule R6."
  (let* ((case-fold-search t)
         (narrowed (buffer-narrowed-p))
         (top (sommaire-org--headlines tree))
         (promoted (and narrowed
                        top
                        (null (cdr top))
                        (= (org-element-property :begin (car top)) (point-min))
                        (car top)))
         (element (or promoted tree))
         (root (sommaire-org--heading
                element
                (cond
                 (promoted (sommaire-org--title promoted))
                 ((not narrowed)
                  (org-string-nw-p
                   (sommaire-rules-plain
                    (string-join (org-element-map tree 'keyword
                                   (lambda (keyword)
                                     (and (equal (org-element-property :key keyword) "TITLE")
                                          (org-element-property :value keyword))))
                                 " ")
                    sommaire-org--inline))))
                nil)))
    ;; Under narrowing, `org-data' keeps the bounds of the whole buffer.
    (plist-put root :begin (point-min))
    (plist-put root :end (point-max))
    (let ((headings (sommaire-org--eligible element root)))
      (sommaire-rules-outline root headings))))

(defun sommaire-org-outline ()
  "Return the outline of the accessible part of this Org buffer.
See `sommaire-rules-outline' for its shape.  The value is kept for as
long as the text and the narrowing stay the same, so the caller must not
change it.  A part too large to read, or that Org cannot parse, such as
one nested too deep for the Lisp stack, has only a root, and a message
says why: a document must not break a timer or a redisplay, or hold them
up for long.  Point and the match data stay."
  (let ((key (list (buffer-chars-modified-tick) (point-min) (point-max))))
    (unless (equal key (car sommaire-org--cache))
      (setq sommaire-org--cache
            (cons key
                  (save-match-data
                    (save-excursion
                      (condition-case failure
                          (progn
                            (sommaire-rules-check-size (- (point-max) (point-min)))
                            (sommaire-org--read (org-element-parse-buffer 'element)))
                        (error
                         (message "sommaire: cannot read the headings of this buffer: %s"
                                  (error-message-string failure))
                         (sommaire-rules-outline
                          (list :begin (point-min) :body (point-min) :end (point-max))
                          nil))))))))
    (cdr sommaire-org--cache)))

(provide 'sommaire-org)

;;; sommaire-org.el ends here

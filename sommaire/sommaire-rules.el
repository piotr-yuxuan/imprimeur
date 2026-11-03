;;; sommaire-rules.el --- The rules of mini tables of contents  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The rules of docs/reference/minitoc-rules.md, which is the authority, as pure
;; functions of a model: no buffer, no clock, no state.  A model and the
;; decisions are that file's JSON held as plists with keyword keys, in the
;; same order, where false, null and the empty array are all nil.
;;
;; The adapters of Emacs share the outline, which is a model with the map
;; from its ids to places in the buffer: `sommaire-rules-outline' makes one,
;; and `sommaire-rules-active' finds the active heading in it.  They share how
;; a title loses its inline markup too, in `sommaire-rules-plain', each with a
;; regexp of its format's.

;;; Code:

(require 'seq)
(require 'subr-x)

(defconst sommaire-rules-min-children 2
  "The fewest children of a heading worth a minitoc: rule R1.")

(defconst sommaire-rules-max-depth 2
  "The greatest depth of a heading worth a minitoc: rule R1.")

(defconst sommaire-rules-root-levels 2
  "The levels of entries that the root lists: rule R1.")

(defconst sommaire-rules-section-levels 1
  "The levels of entries that any other heading lists: rule R1.")

(defconst sommaire-rules-largest-part 1000000
  "The most characters of a buffer that an adapter reads.
A document chooses its size, and an adapter reads it again after each edit.")

(defconst sommaire-rules-longest-title 1024
  "The characters of a title that an adapter reads, so that work stays bounded.")

(defconst sommaire-rules-deepest-markup 8
  "The levels of inline markup in a title that an adapter takes off.
A document chooses their depth, and the Lisp stack is what it would reach.")

(defun sommaire-rules-check-size (size)
  "Signal an error when SIZE characters are more than an adapter reads.
Return nil otherwise."
  (when (> size sommaire-rules-largest-part)
    (error "%d characters, more than the %d that are read; narrow to a part of them"
           size sommaire-rules-largest-part)))

(defun sommaire-rules-plain (text inline &optional level)
  "Return TEXT, a one-line title, without the markup that regexp INLINE finds.
So it reads as it is displayed.  Group 1 of INLINE is what shows as it stands,
and group 2 what shows and may hold markup of its own, which comes out too,
down to `sommaire-rules-deepest-markup' levels, of which TEXT is at LEVEL.
Group 3, if it matched, closes a span, and what INLINE looks at after it is
left for the next match; group 4, if it matched, is a character before a
span, which stays.  What INLINE does not find stays, a mark that does not
pair above all.  Only the first `sommaire-rules-longest-title' characters
are read."
  (let ((text (substring text 0 (min (length text) sommaire-rules-longest-title)))
        (level (or level 1))
        (pieces nil)
        (start 0))
    (while (string-match inline text start)
      (let ((before (substring text start (or (match-end 4) (match-beginning 0))))
            (shown (match-string 1 text))
            (inner (match-string 2 text))
            (end (or (match-end 3) (match-end 0))))
        (setq pieces (cons (if (and inner (< level sommaire-rules-deepest-markup))
                               (sommaire-rules-plain inner inline (1+ level))
                             (or inner shown))
                           (cons before pieces))
              start end)))
    (apply #'concat (nreverse (cons (substring text start) pieces)))))

(defun sommaire-rules--node (heading id children)
  "Return the node of tree schema 1 for HEADING, with ID and CHILDREN."
  (list :id id
        :title (plist-get heading :title)
        :archived (and (plist-get heading :archived) t)
        :intro (and (plist-get heading :intro) t)
        :explicit (and (plist-get heading :explicit) t)
        :children children))

(defun sommaire-rules-outline (root headings)
  "Return the outline of the document ROOT over HEADINGS, in document order.
An outline is a plist (:model MODEL :places PLACES).  ROOT and each of
HEADINGS are plists with the keys :title, :archived, :intro and
:explicit of tree schema 1, where any non-nil value is true, and with
places as positions: :begin where the heading starts, :body the first
character after its metadata, and :end the end of its subtree, excluded.
HEADINGS also have :level: a heading's parent is the nearest preceding
heading of a lower level, or else ROOT.  PLACES is the vector of ROOT
and HEADINGS, indexed by id.  The walk goes backwards, from each heading
to the trees that follow it.  It does not recurse, and it takes each tree
once and looks no further, since a document chooses its depth and its
width: the work is linear in HEADINGS."
  (let ((id (length headings))
        ;; Pairs (LEVEL . NODE) of the trees built so far, nearest first.
        (trees nil))
    (dolist (heading (reverse headings))
      (let ((level (plist-get heading :level))
            (children nil))
        (while (and trees (> (caar trees) level))
          (push (cdr (pop trees)) children))
        (push (cons level (sommaire-rules--node heading id (nreverse children))) trees)
        (setq id (1- id))))
    (list :model (list :schema 1 :root (sommaire-rules--node root 0 (mapcar #'cdr trees)))
          :places (vconcat (cons root headings)))))

(defun sommaire-rules-active (outline position)
  "Return the id of the active heading of OUTLINE at POSITION: rule R4.
It is the last heading whose places hold POSITION: headings nest and ids
count in preorder, so that is the innermost one.  The very end of the
document belongs to every heading that reaches it.  Signal an error when
the root does not hold POSITION."
  (let* ((places (plist-get outline :places))
         (end-of-document (plist-get (aref places 0) :end))
         (id (1- (length places))))
    (while (let ((place (aref places id)))
             (not (and (<= (plist-get place :begin) position)
                       (or (< position (plist-get place :end))
                           (= position (plist-get place :end) end-of-document)))))
      (setq id (1- id)))
    id))

(defun sommaire-rules--worth-p (node depth)
  "Return non-nil when NODE, at DEPTH in the tree, is worth a minitoc: rule R1."
  (and (<= depth sommaire-rules-max-depth)
       (>= (length (plist-get node :children)) sommaire-rules-min-children)))

(defun sommaire-rules--candidate-p (node depth)
  "Return non-nil when NODE, at DEPTH, may have an inline minitoc: rule R3.
The root never has one, and an explicit table wins over it: rule R2."
  (and (> depth 0)
       (not (plist-get node :explicit))
       (sommaire-rules--worth-p node depth)))

(defun sommaire-rules--entry (node levels)
  "Return the entry of NODE, which lists LEVELS levels, its own included."
  (list :id (plist-get node :id)
        :title (plist-get node :title)
        :archived (plist-get node :archived)
        :children (and (> levels 1)
                       (mapcar (lambda (child)
                                 (sommaire-rules--entry child (1- levels)))
                               (plist-get node :children)))))

(defun sommaire-rules--reference (node)
  "Return the reference to NODE."
  (list :id (plist-get node :id) :title (plist-get node :title)))

(defun sommaire-rules-minitocs (model)
  "Return the inline minitocs of MODEL, in document order: rule R3.
Each is a plist (:anchor ID :entries ENTRIES), with a button at its
anchor.  No candidate lies deeper than `sommaire-rules-max-depth', so
the walk stops there, whatever the depth of the document.  The merging
relies on that constant being 2: only the first child of an anchor can
then be merged, and nothing under it can be a candidate.  With a greater
value, a run could hold more merged headings than this walk finds."
  (named-let visit ((node (plist-get model :root)) (depth 0) (merged nil))
    (let* ((children (plist-get node :children))
           (anchor (and (not merged) (sommaire-rules--candidate-p node depth)))
           ;; The child merged into this heading's minitoc, if any.
           (expansion (and anchor
                           (not (plist-get node :intro))
                           (sommaire-rules--candidate-p (car children) (1+ depth))
                           (car children))))
      (nconc
       (and anchor
            (list (list :anchor (plist-get node :id)
                        :entries (mapcar (lambda (child)
                                           (sommaire-rules--entry
                                            child (if (eq child expansion)
                                                      (1+ sommaire-rules-section-levels)
                                                    sommaire-rules-section-levels)))
                                         children))))
       (and (< depth sommaire-rules-max-depth)
            (mapcan (lambda (child) (visit child (1+ depth) (eq child expansion)))
                    children))))))

(defun sommaire-rules--chain (model active)
  "Return the headings of MODEL from its root down to the one of id ACTIVE.
A heading's index in the list is its depth.  Ids count in preorder, so
the way down goes through the last child whose id does not exceed ACTIVE.
Signal an error when MODEL has no heading of that id."
  (let ((chain (list (plist-get model :root))))
    (while (not (eql (plist-get (car chain) :id) active))
      (push (or (seq-find (lambda (child)
                            (<= (plist-get child :id) active))
                          (reverse (plist-get (car chain) :children)))
                (error "No heading of id %S in the model" active))
            chain))
    (reverse chain)))

(defun sommaire-rules--from-section (chain)
  "Return the tail of CHAIN that starts at the section of rule R4, or nil if none."
  (let ((depth (seq-find (lambda (depth)
                           (sommaire-rules--worth-p (nth depth chain) depth))
                         (number-sequence (1- (length chain)) 0 -1))))
    (and depth (nthcdr depth chain))))

(defun sommaire-rules-local (model active)
  "Return the local minitoc of MODEL for the active heading of id ACTIVE: rule R4.
It is a plist (:active ID :section REFERENCE :current ID :entries
ENTRIES :path REFERENCES).  Signal an error when MODEL has no heading of
that id."
  (let* ((chain (sommaire-rules--chain model active))
         (way (sommaire-rules--from-section chain))
         (section (car way))
         (levels (if (eq section (car chain))
                     sommaire-rules-root-levels
                   sommaire-rules-section-levels)))
    (list :active active
          :section (and section (sommaire-rules--reference section))
          :current (plist-get (cadr way) :id)
          :entries (mapcar (lambda (child) (sommaire-rules--entry child levels))
                           (plist-get section :children))
          :path (mapcar #'sommaire-rules--reference (cdr chain)))))

(defun sommaire-rules-panel (model active root depth)
  "Return the panel of MODEL for a scope, the active heading being of id ACTIVE.
The scope is ROOT, the symbol `document' or `section', and DEPTH, a
positive integer or the symbol `all'.  The panel is a plist (:root
REFERENCE :current ID :entries ROWS), and each of ROWS a plist (:id ID
:title TITLE :archived FLAG :depth DEPTH), in document order, where
DEPTH is its distance from the scope's root.  The walk does not recurse,
since a document chooses its depth.  Signal an error for any other ROOT
or DEPTH, and when MODEL has no heading of id ACTIVE."
  (let* ((limit (if (eq depth 'all) most-positive-fixnum depth))
         (chain (sommaire-rules--chain model active))
         ;; From the scope's root down to the active heading.
         (way (pcase root
                ('document chain)
                ('section (sommaire-rules--from-section chain))
                (_ (error "No scope has the root %S" root))))
         (pending (mapcar (lambda (child) (cons 1 child))
                          (plist-get (car way) :children)))
         (rows nil))
    (unless (and (integerp limit) (> limit 0))
      (error "No scope has the depth %S" depth))
    (while pending
      (let* ((next (pop pending))
             (level (car next))
             (node (cdr next)))
        (push (list :id (plist-get node :id)
                    :title (plist-get node :title)
                    :archived (plist-get node :archived)
                    :depth level)
              rows)
        (when (< level limit)
          (setq pending (nconc (mapcar (lambda (child) (cons (1+ level) child))
                                       (plist-get node :children))
                               pending)))))
    (list :root (and way (sommaire-rules--reference (car way)))
          :current (plist-get (car (last (seq-take (cdr way) limit))) :id)
          :entries (nreverse rows))))

(defun sommaire-rules-step (model active root depth delta)
  "Return the depth after a step by DELTA, 1 or -1, of a scope's DEPTH.
The scope and ACTIVE are as for `sommaire-rules-panel', on MODEL.  A step
looks at ROOT as it stands at that moment.  The deepest level that it has
below it becomes `all', so the list stops growing where the label says so,
and going back from `all' starts from there.  With nothing listed there is
no deepest level: a number just moves, for the next section to use, and
`all' stays or, going back, becomes the least depth."
  (let* ((rows (plist-get (sommaire-rules-panel model active root 'all) :entries))
         (deepest (seq-reduce #'max
                              (mapcar (lambda (row) (plist-get row :depth)) rows)
                              0))
         (next (+ delta (cond ((eq depth 'all) deepest)
                              (rows (min depth deepest))
                              (t depth)))))
    (cond ((and (eq depth 'all) (> delta 0)) 'all)
          ((< next 1) 1)
          ((and rows (>= next deepest)) 'all)
          (t next))))

(provide 'sommaire-rules)

;;; sommaire-rules.el ends here

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

;; The rules of docs/minitoc-rules.md, which is the authority, as pure
;; functions of a model: no buffer, no clock, no state.  A model and the
;; decisions are that file's JSON held as plists with keyword keys, in the
;; same order, where false, null and the empty array are all nil.

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

(defun sommaire-rules-panel (model active)
  "Return the panel of MODEL for the active heading of id ACTIVE: rule R4.
It is a plist (:active ID :section REFERENCE :current ID :entries
ENTRIES :path REFERENCES).  Ids count in preorder, so the way down to
ACTIVE goes through the last child whose id does not exceed it.  Signal
an error when MODEL has no heading of that id."
  (let* ((chain (let ((chain (list (plist-get model :root))))
                  (while (not (eql (plist-get (car chain) :id) active))
                    (push (or (seq-find (lambda (child)
                                          (<= (plist-get child :id) active))
                                        (reverse (plist-get (car chain) :children)))
                              (error "No heading of id %S in the model" active))
                          chain))
                  (reverse chain)))
         ;; A heading's index in CHAIN is its depth.
         (depth (seq-find (lambda (depth)
                            (sommaire-rules--worth-p (nth depth chain) depth))
                          (number-sequence (1- (length chain)) 0 -1)))
         (section (and depth (nth depth chain)))
         (levels (if (eql depth 0)
                     sommaire-rules-root-levels
                   sommaire-rules-section-levels)))
    (list :active active
          :section (and section (sommaire-rules--reference section))
          :current (and depth (plist-get (nth (1+ depth) chain) :id))
          :entries (mapcar (lambda (child) (sommaire-rules--entry child levels))
                           (plist-get section :children))
          :path (mapcar #'sommaire-rules--reference (cdr chain)))))

(provide 'sommaire-rules)

;;; sommaire-rules.el ends here

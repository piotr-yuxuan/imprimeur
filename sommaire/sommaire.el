;;; sommaire.el --- Mini tables of contents for Org and Markdown  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan <piotr-yuxuan@users.noreply.github.com>
;; Maintainer: piotr-yuxuan <piotr-yuxuan@users.noreply.github.com>
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: outlines, convenience

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the licences
;; for more details.

;;; Commentary:

;; sommaire shows mini tables of contents in Org and Markdown buffers.  It
;; needs no other package.  docs/minitoc-rules.md is the authority on what a
;; document gets; `sommaire-rules' decides it, `sommaire-org' and
;; `sommaire-markdown' read a buffer for it, and this file draws the decisions.
;;
;; `sommaire-mode' shows the section around point in the header line, as
;; "§ Requirements ▾2 › Emacs": the section, the number of its entries and the
;; entry that holds point.  It goes after what the header line already holds,
;; such as the element of breadcrumb, which shows the heading path.  With
;; nothing there the segment shows that path too, so that the row is there as
;; long as the mode is on, and neither appears nor disappears as point moves.
;;
;; `sommaire-jump', on M-g m in the mode's map only, reads a heading of the
;; buffer's scope, which the option `sommaire-scope' gives: a root, the document
;; or the section around point, and a depth.  So the default, the section's
;; direct children, is a short list, and C-u gives the whole document.
;;
;; `sommaire-panel', or a click on the segment, shows that scope in a narrow side
;; Emacs window, which is off by default and which sommaire never selects.  The
;; reader may go there, as to any Emacs window: its keys change the scope, for
;; that buffer alone, so that `clone-indirect-buffer' gives each Emacs window its
;; own, as for folds.
;;
;; A heading that anchors a run, in the sense of rule R3, carries a button
;; "▸ N", which `jit-lock' creates only as the text comes into view.  The button
;; opens that heading's inline minitoc, or `sommaire-toggle-inline' does from
;; the keyboard.  It sits on the first character after the metadata and is shown
;; in one Emacs window, which holds at most one.  Folding the heading hides both:
;; redisplay shows no overlay string at invisible text, so no code here folds.
;;
;; One idle timer serves all the buffers with the mode, and looks at the
;; selected Emacs window only.  A key ends its read, which leaves what is shown
;; as it was.  Redisplay reads no document, only what the timer left.  The timer
;; also places the buttons of what Emacs windows show, for what `jit-lock' does
;; not see again, and an indirect buffer, where it does not run.  Loading this
;; file adds no timer, hook or key, and loads neither Org nor anything of
;; Markdown; the mode's timer, hooks and overlays go when it ends, and so does
;; what it added to the header line.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'sommaire-rules)

(autoload 'sommaire-org-outline "sommaire-org")
(autoload 'sommaire-markdown-outline "sommaire-markdown")

(defgroup sommaire nil
  "Mini tables of contents for Org and Markdown."
  :group 'outlines
  :prefix "sommaire-")

(defcustom sommaire-header-line t
  "Non-nil means that `sommaire-mode' shows its segment in the header line.
The mode reads this when it starts."
  :type 'boolean)

(defcustom sommaire-heading-buttons t
  "Non-nil means that the headings that anchor a run carry a button.
The button opens the heading's inline minitoc.  The mode reads this when it
starts."
  :type 'boolean)

(defcustom sommaire-idle-delay 0.4
  "The seconds of idle time after which `sommaire-mode' follows point.
The timer reads this when it starts, which is when the first buffer turns
the mode on."
  :type 'number)

(defcustom sommaire-scope '(section . 1)
  "The default scope of a buffer: what `sommaire-jump' offers.
It is a pair (ROOT . DEPTH).  ROOT is `document', or `section', the section
around point, which follows it.  DEPTH is the levels listed below ROOT: a
positive integer, or `all' for every level.  So (document . 2) is the first
two levels of the document, and (section . 1) the direct children of the
section.  The keys of `sommaire-panel' give a buffer its own value, which holds
for that buffer alone."
  :type '(cons (choice (const document) (const section))
               (choice (const all) (integer :tag "Levels"))))

(defface sommaire-current '((t :inherit bold))
  "The entry that holds point.")

(defface sommaire-archived '((t :inherit shadow))
  "An archived heading in a list of entries.")

(defface sommaire-button '((t :inherit shadow))
  "The button of a heading, which opens its inline minitoc.")

(defface sommaire-inline '((t :inherit font-lock-doc-face))
  "The entries of an inline minitoc, which is no text of the document.")

(defvar-keymap sommaire-mode-map
  :doc "The keys of `sommaire-mode'."
  "M-g m" #'sommaire-jump)

(defvar-keymap sommaire--button-map
  :doc "The keys of a heading's button, whose string point never enters."
  "<mouse-1>" #'sommaire-toggle-inline)

(defvar-keymap sommaire--inline-map
  :doc "The keys of an inline minitoc, whose string point never enters."
  "<mouse-1>" #'sommaire-follow-inline)

(defvar-keymap sommaire--segment-map
  :doc "The keys of the segment in the header line."
  "<header-line> <mouse-1>" #'sommaire-panel)

(defvar-keymap sommaire-panel-mode-map
  :doc "The keys of the side Emacs window of `sommaire-panel'."
  "RET" #'sommaire-panel-jump
  "<mouse-1>" #'sommaire-panel-jump
  "+" #'sommaire-panel-deeper
  "-" #'sommaire-panel-shallower
  "r" #'sommaire-panel-toggle-root
  "q" #'sommaire-panel-close)

(defconst sommaire--header-element
  '("  " (:eval (alist-get (selected-window) sommaire--segments)))
  "What `sommaire-mode' adds to the header line.
Redisplay selects each Emacs window while it draws that window's header line.")

(defvar sommaire--timer nil
  "The one idle timer, while any buffer has `sommaire-mode'.")

(defvar-local sommaire--header nil
  "While the mode is in the header line, a pair: what it found and what it left.")

(defvar-local sommaire--segments nil
  "An alist from an Emacs window to the segment it shows of this buffer.")

(defvar-local sommaire--too-large nil
  "Non-nil when the accessible part is too large to read and the reader knows.")

(defvar-local sommaire--outline nil
  "The outline that this buffer's overlays follow.")

(defvar-local sommaire--blocks nil
  "The inline minitocs of `sommaire--outline', from `sommaire-rules-minitocs'.")

(defvar-local sommaire--outline-tick nil
  "What `buffer-chars-modified-tick' gave for `sommaire--outline'.")

(defvar-local sommaire--panel nil
  "The buffer of this buffer's panel.  A clone inherits this and not the panel.")

(defvar-local sommaire--source nil
  "In the buffer of a panel, the buffer whose scope it shows.")

(defvar-local sommaire--drawn nil
  "In the buffer of a panel, what it shows: a scope and its decision.")

;;;###autoload
(define-minor-mode sommaire-mode
  "Show mini tables of contents in this Org or Markdown buffer.
The header line names the section around point, after whatever it already
holds, or shows the heading path when it holds nothing.  A heading that
anchors a run has a button that opens its inline minitoc, as does
`sommaire-toggle-inline'.  See the options `sommaire-header-line' and
`sommaire-heading-buttons'.  \\[sommaire-jump] goes to a heading of the buffer's
scope, and `sommaire-panel' shows that scope: see the option `sommaire-scope'.
An Org buffer is read as Org, and any other as Markdown.

\\{sommaire-mode-map}"
  :lighter nil
  :group 'sommaire
  :keymap sommaire-mode-map
  (if (not sommaire-mode)
      (sommaire--stop)
    (when (and sommaire-header-line (not sommaire--header))
      (let* ((found header-line-format)
             ;; A list of constructs takes the element in place, so that a
             ;; later `delete' by its owner still finds what is in it.
             (left (if (or (null found) (stringp (car-safe found)) (consp (car-safe found)))
                       (append found (list sommaire--header-element))
                     (list "" found sommaire--header-element))))
        (setq sommaire--header (cons found left)
              header-line-format left)))
    (when (and sommaire-heading-buttons (not (buffer-base-buffer)))
      (jit-lock-register #'sommaire--place-buttons))
    (add-hook 'change-major-mode-hook #'sommaire--stop nil t)
    (add-hook 'kill-buffer-hook #'sommaire--stop nil t)
    (unless sommaire--timer
      (setq sommaire--timer (run-with-idle-timer sommaire-idle-delay t #'sommaire--tick)))))

(defun sommaire-segment (local with-path)
  "Return the text of the header line for LOCAL, a `sommaire-rules-local' value.
That is the section as \"§ Requirements ▾2\", with its number of entries,
and then its current entry, in the face `sommaire-current'.  With WITH-PATH,
for a header line that nothing else fills, it is the whole heading path with
the section in its place, or the path alone when there is no section.  Every
percent sign of a title is escaped for `header-line-format'.  This function
is pure: it reads only its arguments."
  (let* ((section (plist-get local :section))
         (current (plist-get local :current))
         ;; A root may have no title, and `concat' makes that an empty string.
         (escaped (lambda (reference)
                    (string-replace "%" "%%" (concat (plist-get reference :title)))))
         (section-text
          (and section
               (string-join (delete "" (list "§" (funcall escaped section)
                                             (format "▾%d" (length (plist-get local :entries)))))
                            " ")))
         (shown (if with-path
                    (plist-get local :path)
                  (seq-filter (lambda (reference) (eql (plist-get reference :id) current))
                              (plist-get local :path))))
         (parts (mapcar (lambda (reference)
                          (cond
                           ((eql (plist-get reference :id) (plist-get section :id)) section-text)
                           ((eql (plist-get reference :id) current)
                            (propertize (funcall escaped reference) 'face 'sommaire-current))
                           (t (funcall escaped reference))))
                        shown)))
    (propertize (string-join (if (and section (not (memq section-text parts)))
                                 ;; The root has no place in a path.
                                 (cons section-text parts)
                               parts)
                             " › ")
                'keymap sommaire--segment-map
                'mouse-face 'mode-line-highlight
                'help-echo "mouse-1: show or close the panel")))

(defun sommaire--read ()
  "Return the outline of this buffer's accessible part, read by its adapter.
A part too large to read is not given to the adapter, which would say so
after each edit: it has a root alone, and the reader hears of it once, until
the part gets small enough."
  (if (> (- (point-max) (point-min)) sommaire-rules-largest-part)
      (progn
        (unless sommaire--too-large
          (setq sommaire--too-large t)
          (message "sommaire: this buffer is too large to read; narrow to a part of it"))
        (sommaire-rules-outline (list :begin (point-min) :body (point-min) :end (point-max))
                                nil))
    (setq sommaire--too-large nil)
    (if (derived-mode-p 'org-mode)
        (sommaire-org-outline)
      (sommaire-markdown-outline))))

(defun sommaire--overlays (kind)
  "Return this buffer's overlays of KIND, `button' or `inline', narrowed or not."
  (save-restriction
    (widen)
    (seq-filter (lambda (overlay) (eq (overlay-get overlay 'sommaire) kind))
                (overlays-in (point-min) (point-max)))))

(defun sommaire--line (entry depth current)
  "Return the line of ENTRY, with its id, DEPTH levels below what lists it.
CURRENT means that it holds point, which a mark and a face say."
  (propertize (concat (make-string (* 2 (1- depth)) ?\s)
                      (if current "› " "  ")
                      (plist-get entry :title)
                      "\n")
              'face (cond (current 'sommaire-current)
                          ((plist-get entry :archived) 'sommaire-archived))
              'mouse-face 'highlight
              'sommaire-id (plist-get entry :id)))

(defun sommaire--set-inline (overlay body entries)
  "Put the inline minitoc OVERLAY at BODY, listing ENTRIES, whichever changed.
BODY is the first character after the metadata: rule R5.  Redisplay shows no
string at invisible text, so folding the heading hides this one: rule R6."
  (move-overlay overlay body (1+ body))
  (unless (equal entries (overlay-get overlay 'sommaire-entries))
    (overlay-put overlay 'sommaire-entries entries)
    (overlay-put overlay 'before-string
                 (let ((text (mapconcat
                              (lambda (entry)
                                (concat (sommaire--line entry 1 nil)
                                        (mapconcat (lambda (child) (sommaire--line child 2 nil))
                                                   (plist-get entry :children)
                                                   "")))
                              entries
                              "")))
                   (add-face-text-property 0 (length text) 'sommaire-inline t text)
                   (propertize text
                               'keymap sommaire--inline-map
                               'help-echo "mouse-1: go to this heading")))))

(defun sommaire--adopt (outline)
  "Make OUTLINE the one that this buffer's overlays follow, and return it.
Overlays move with the text, so an edit that leaves the decisions as they
were redraws nothing.  A button that no longer stands at a run anchor, or a
change in the anchors, removes them all, and they come back as text shows.
An inline minitoc stays at an anchor whose metadata still hold it, and goes
with its anchor or its Emacs window."
  (unless (eq outline sommaire--outline)
    (let* ((places (plist-get outline :places))
           (blocks (sommaire-rules-minitocs (plist-get outline :model)))
           (buttons (sommaire--overlays 'button))
           (starts (make-hash-table)))
      (dolist (block blocks)
        (puthash (plist-get (aref places (plist-get block :anchor)) :begin) t starts))
      (if (and (equal blocks sommaire--blocks)
               (seq-every-p (lambda (button) (gethash (overlay-start button) starts)) buttons))
          ;; A new line at the end of a heading must not take its button along.
          (dolist (button buttons)
            (save-excursion
              (goto-char (overlay-start button))
              (move-overlay button (point) (pos-eol))))
        (mapc #'delete-overlay buttons))
      (dolist (inline (sommaire--overlays 'inline))
        (let* ((start (overlay-start inline))
               (block (seq-find (lambda (block)
                                  (let ((place (aref places (plist-get block :anchor))))
                                    (<= (plist-get place :begin) start (plist-get place :body))))
                                blocks)))
          (if (and block (window-live-p (overlay-get inline 'window)))
              (sommaire--set-inline
               inline
               (plist-get (aref places (plist-get block :anchor)) :body)
               (plist-get block :entries))
            (delete-overlay inline))))
      (setq sommaire--outline outline
            sommaire--blocks blocks
            sommaire--outline-tick (buffer-chars-modified-tick))))
  outline)

(defun sommaire--place-buttons (begin end)
  "Give the run anchors whose headings start between BEGIN and END their buttons.
It reads no document, since `jit-lock' calls it in redisplay.  While the text
has changed since `sommaire--outline', its places are old, so it leaves this
to the timer, which calls it too.  The overlay spans the heading's line, so
that text typed at its end keeps the button at the end."
  (when (and sommaire-heading-buttons
             (eql sommaire--outline-tick (buffer-chars-modified-tick)))
    (let ((places (plist-get sommaire--outline :places)))
      (dolist (block sommaire--blocks)
        (let ((start (plist-get (aref places (plist-get block :anchor)) :begin)))
          (when (and (<= begin start)
                     (< start end)
                     (not (seq-some (lambda (overlay) (eq (overlay-get overlay 'sommaire) 'button))
                                    (overlays-at start))))
            (let ((overlay (save-excursion
                             (goto-char start)
                             (make-overlay start (pos-eol) nil nil t))))
              (overlay-put overlay 'sommaire 'button)
              (overlay-put overlay 'evaporate t)
              (overlay-put overlay 'after-string
                           (propertize (format " ▸ %d" (length (plist-get block :entries)))
                                       'face 'sommaire-button
                                       'keymap sommaire--button-map
                                       'mouse-face 'highlight
                                       'help-echo "mouse-1: open or close this minitoc")))))))))

(defun sommaire-toggle-inline ()
  "Open the inline minitoc of the run anchor around point, or close it.
Opening one closes any other in the selected Emacs window, which alone shows
it.  A click on a heading's button acts on that heading."
  (interactive)
  (unless sommaire-mode
    (user-error "This takes `sommaire-mode'"))
  (when (mouse-event-p last-command-event)
    (posn-set-point (event-end last-command-event)))
  (let* ((outline (sommaire--adopt (sommaire--read)))
         (places (plist-get outline :places))
         (begin (plist-get (aref places (sommaire-rules-active outline (point))) :begin))
         ;; Later anchors lie deeper, and the last one around point is the nearest.
         (block (seq-find (lambda (block)
                            (let ((place (aref places (plist-get block :anchor))))
                              (and (<= (plist-get place :begin) begin)
                                   (< begin (plist-get place :end)))))
                          (reverse sommaire--blocks)))
         (body (plist-get (and block (aref places (plist-get block :anchor))) :body))
         (window (selected-window))
         (open (seq-find (lambda (overlay) (eq (overlay-get overlay 'window) window))
                         (sommaire--overlays 'inline))))
    (unless block
      (user-error "No heading around point has an inline minitoc"))
    (if (and open (= (overlay-start open) body))
        (delete-overlay open)
      (let ((overlay (or open (make-overlay body (1+ body)))))
        (overlay-put overlay 'sommaire 'inline)
        (overlay-put overlay 'window window)
        (sommaire--set-inline overlay body (plist-get block :entries))))))

(defun sommaire-follow-inline (event)
  "Go to the heading of the inline minitoc's entry that EVENT, a click, is on."
  (interactive "e")
  (let* ((place (event-end event))
         (string (posn-string place)))
    (select-window (posn-window place))
    (sommaire--go-to (get-text-property (cdr string) 'sommaire-id (car string)))))

(defun sommaire--go-to (id)
  "Move point to the heading of id ID in this buffer, leaving the mark behind."
  (push-mark nil t)
  (goto-char (plist-get (aref (plist-get (sommaire--read) :places) id) :begin)))

(defun sommaire-jump (&optional arg)
  "Read a heading of this buffer's scope, and go to it.
The scope is the value of `sommaire-scope' here.  With \\[universal-argument],
read from the whole document at all depths; with a positive numeric prefix ARG,
from that depth of the scope, this once.  The default is the entry that holds
point, or else the first.  Headings of one title are told apart by a number."
  (interactive "P")
  (let* ((outline (sommaire--read))
         (scope (cond ((consp arg) '(document . all))
                      ((and (integerp arg) (> arg 0)) (cons (car sommaire-scope) arg))
                      (t sommaire-scope)))
         (panel (sommaire-rules-panel (plist-get outline :model)
                                      (sommaire-rules-active outline (point))
                                      (car scope) (cdr scope)))
         (seen (make-hash-table :test #'equal))
         ;; Pairs (NAME . ID), in document order.
         (names (mapcar (lambda (row)
                          (let* ((title (plist-get row :title))
                                 (times (1+ (gethash title seen 0))))
                            (puthash title times seen)
                            (cons (if (> times 1) (format "%s <%d>" title times) title)
                                  (plist-get row :id))))
                        (plist-get panel :entries)))
         (default (or (car (rassq (plist-get panel :current) names)) (caar names))))
    (unless names
      (user-error "No heading in this scope; %s lists the whole document"
                  (substitute-command-keys "\\[universal-argument] \\[sommaire-jump]")))
    (sommaire--go-to
     (cdr (assoc (completing-read (format-prompt "Go to heading" default)
                                  (lambda (string predicate action)
                                    (if (eq action 'metadata)
                                        '(metadata (display-sort-function . identity)
                                                   (cycle-sort-function . identity))
                                      (complete-with-action action names string predicate)))
                                  nil t nil nil default)
                 names)))))

(define-derived-mode sommaire-panel-mode special-mode "Sommaire"
  "The major mode of the side Emacs window that `sommaire-panel' shows.

\\{sommaire-panel-mode-map}"
  (setq-local truncate-lines t
              mode-line-format nil
              cursor-in-non-selected-windows nil))

(defun sommaire--own-panel ()
  "Return the buffer of this buffer's panel, if it has one."
  (and (buffer-live-p sommaire--panel)
       (eq (buffer-local-value 'sommaire--source sommaire--panel) (current-buffer))
       sommaire--panel))

(defun sommaire--close-panel ()
  "Remove this buffer's panel, if it has one: its Emacs window and its buffer.
Killing the buffer deletes a dedicated side window."
  (let ((panel (sommaire--own-panel)))
    (when panel
      (kill-buffer panel)))
  (setq sommaire--panel nil))

(defun sommaire--draw-panel (outline)
  "Show OUTLINE in this buffer's panel, if it has one, in this buffer's scope.
This changes nothing unless what the panel shows has changed.  It leaves the
panel's Emacs windows at the current entry, so that a long list shows it."
  (let ((panel (sommaire--own-panel))
        (scope sommaire-scope))
    (when panel
      (let* ((decision (sommaire-rules-panel (plist-get outline :model)
                                             (sommaire-rules-active outline (point))
                                             (car scope) (cdr scope)))
             (root (plist-get decision :root))
             (current (plist-get decision :current))
             (drawn (cons scope decision)))
        (with-current-buffer panel
          (unless (equal drawn sommaire--drawn)
            (setq sommaire--drawn drawn)
            (let ((inhibit-read-only t)
                  (place (point-min)))
              (erase-buffer)
              (insert (propertize (cond ((null root) "No section here")
                                        ((plist-get root :title))
                                        (t "Document"))
                                  'face 'bold)
                      (propertize (format "\n%s · depth %s\n" (car scope) (cdr scope))
                                  'face 'shadow))
              (dolist (row (plist-get decision :entries))
                (when (eql (plist-get row :id) current)
                  (setq place (point)))
                (insert (sommaire--line row (plist-get row :depth)
                                        (eql (plist-get row :id) current))))
              (goto-char place)
              (dolist (window (get-buffer-window-list nil nil t))
                (set-window-point window place)))))))))

(defun sommaire-panel ()
  "Show this buffer's scope in a side Emacs window, or close it if it shows.
The window is narrow and dedicated, and this leaves the selected Emacs window
selected.  It follows point through the idle timer.  In it,
\\<sommaire-panel-mode-map>\\[sommaire-panel-jump] or a click goes to an entry's heading, \\[sommaire-panel-deeper] and \\[sommaire-panel-shallower] change the
depth, \\[sommaire-panel-toggle-root] toggles the root, and \\[sommaire-panel-close] closes it."
  (interactive "@")
  (unless sommaire-mode
    (user-error "This takes `sommaire-mode'"))
  (let ((panel (sommaire--own-panel)))
    (if (and panel (get-buffer-window panel t))
        (sommaire--close-panel)
      (unless panel
        (let ((source (current-buffer)))
          (setq panel (generate-new-buffer (format " *sommaire: %s*" (buffer-name))))
          (with-current-buffer panel
            (sommaire-panel-mode)
            (setq sommaire--source source))
          (setq sommaire--panel panel)))
      (sommaire--draw-panel (sommaire--adopt (sommaire--read)))
      (unless (display-buffer panel '(display-buffer-in-side-window
                                      (side . right) (slot . 0)
                                      (window-width . 32) (dedicated . t)))
        (sommaire--close-panel)
        (user-error "No room for a side window here")))))

(defun sommaire-panel-close ()
  "Remove this panel: its Emacs window and its buffer."
  (interactive)
  (with-current-buffer sommaire--source
    (sommaire--close-panel)))

(defun sommaire--change-depth (delta)
  "Change by DELTA levels the depth of the scope of this panel's buffer.
The deepest level that the root has below it becomes `all', so the list stops
growing where the label says so, and going back from `all' starts from there."
  (with-current-buffer sommaire--source
    (let* ((outline (sommaire--adopt (sommaire--read)))
           (root (car sommaire-scope))
           (depth (cdr sommaire-scope))
           (rows (plist-get (sommaire-rules-panel (plist-get outline :model)
                                                  (sommaire-rules-active outline (point))
                                                  root 'all)
                            :entries))
           (deepest (seq-reduce #'max
                                (mapcar (lambda (row) (plist-get row :depth)) rows)
                                0))
           (next (+ delta (if (eq depth 'all) deepest (min depth deepest)))))
      (setq-local sommaire-scope (cons root (cond ((< next 1) 1)
                                                  ((>= next deepest) 'all)
                                                  (t next))))
      (sommaire--draw-panel outline))))

(defun sommaire-panel-deeper ()
  "List one level more in this panel's scope."
  (interactive)
  (sommaire--change-depth 1))

(defun sommaire-panel-shallower ()
  "List one level fewer in this panel's scope."
  (interactive)
  (sommaire--change-depth -1))

(defun sommaire-panel-toggle-root ()
  "Make the root of this panel's scope the document, or the section around point."
  (interactive)
  (with-current-buffer sommaire--source
    (setq-local sommaire-scope (cons (if (eq (car sommaire-scope) 'document) 'section 'document)
                                     (cdr sommaire-scope)))
    (sommaire--draw-panel (sommaire--adopt (sommaire--read)))))

(defun sommaire-panel-jump ()
  "Go to the heading of this panel's entry at point, or that a click is on.
That leaves an Emacs window of the panel's buffer selected."
  (interactive)
  (when (mouse-event-p last-command-event)
    (posn-set-point (event-end last-command-event)))
  (let ((id (get-text-property (point) 'sommaire-id))
        (source sommaire--source))
    (when id
      (select-window (or (get-buffer-window source) (display-buffer source)))
      (sommaire--go-to id))))

(defun sommaire--tick ()
  "Bring what the selected Emacs window shows of its buffer up to date.
The read runs in `while-no-input', since an idle timer does not quit: a key
ends it, nothing changes, and the adapter has cached nothing."
  (let ((window (selected-window)))
    (with-current-buffer (window-buffer window)
      (when sommaire-mode
        (let ((outline (while-no-input (sommaire--read))))
          (unless (eq outline t)
            (sommaire--adopt outline)
            (dolist (shown (get-buffer-window-list nil nil t))
              (sommaire--place-buttons (window-start shown) (window-end shown t)))
            (when sommaire--header
              (let ((segment (sommaire-segment
                              (sommaire-rules-local (plist-get outline :model)
                                                    (sommaire-rules-active outline (point)))
                              (equal header-line-format (list sommaire--header-element)))))
                (unless (equal segment (alist-get window sommaire--segments))
                  (setq sommaire--segments
                        (cons (cons window segment)
                              (seq-remove (lambda (pair)
                                            (or (eq (car pair) window)
                                                (not (window-live-p (car pair)))))
                                          sommaire--segments)))
                  (force-mode-line-update))))
            (sommaire--draw-panel outline)))))))

(defun sommaire--stop ()
  "End `sommaire-mode' in this buffer, removing all that it added.
The header line goes back to what the mode found, unless something else has
changed it since, which then keeps its change."
  (setq sommaire-mode nil)
  (when sommaire--header
    (setq header-line-format
          (cond ((eq header-line-format (cdr sommaire--header)) (car sommaire--header))
                ((consp header-line-format) (remove sommaire--header-element header-line-format))
                (t header-line-format))
          sommaire--header nil))
  (setq sommaire--segments nil
        sommaire--outline nil
        sommaire--blocks nil
        sommaire--outline-tick nil)
  (mapc #'delete-overlay (sommaire--overlays 'button))
  (mapc #'delete-overlay (sommaire--overlays 'inline))
  (jit-lock-unregister #'sommaire--place-buttons)
  (sommaire--close-panel)
  (remove-hook 'change-major-mode-hook #'sommaire--stop t)
  (remove-hook 'kill-buffer-hook #'sommaire--stop t)
  (unless (seq-some (lambda (buffer) (buffer-local-value 'sommaire-mode buffer)) (buffer-list))
    (when sommaire--timer
      (cancel-timer sommaire--timer)
      (setq sommaire--timer nil))))

(provide 'sommaire)

;;; sommaire.el ends here

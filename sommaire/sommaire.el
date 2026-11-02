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
;; One idle timer serves all the buffers with the mode, and looks at the
;; selected Emacs window only.  A key ends its read, which leaves what is shown
;; as it was.  Redisplay reads no document, only what the timer left.  Loading
;; this file adds no timer, hook or key, and loads neither Org nor anything of
;; Markdown; the mode's timer and hooks go when it ends, and so does what it
;; added to the header line.

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
section.  A buffer's own value holds for that buffer alone."
  :type '(cons (choice (const document) (const section))
               (choice (const all) (integer :tag "Levels"))))

(defface sommaire-current '((t :inherit bold))
  "The entry that holds point.")

(defvar-keymap sommaire-mode-map
  :doc "The keys of `sommaire-mode'."
  "M-g m" #'sommaire-jump)

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

;;;###autoload
(define-minor-mode sommaire-mode
  "Show mini tables of contents in this Org or Markdown buffer.
The header line names the section around point, after whatever it already
holds, or shows the heading path when it holds nothing.  See the option
`sommaire-header-line'.  \\[sommaire-jump] goes to a heading of the buffer's
scope: see the option `sommaire-scope'.  An Org buffer is read as Org, and
any other as Markdown.

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
    ;; The root has no place in a path.
    (string-join (if (and section (not (memq section-text parts)))
                     (cons section-text parts)
                   parts)
                 " › ")))

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

(defun sommaire--tick ()
  "Bring what the selected Emacs window shows of its buffer up to date.
The read runs in `while-no-input', since an idle timer does not quit: a key
ends it, nothing changes, and the adapter has cached nothing."
  (let ((window (selected-window)))
    (with-current-buffer (window-buffer window)
      (when sommaire-mode
        (let ((outline (while-no-input (sommaire--read))))
          (when (and (not (eq outline t)) sommaire--header)
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
                (force-mode-line-update)))))))))

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
  (setq sommaire--segments nil)
  (remove-hook 'change-major-mode-hook #'sommaire--stop t)
  (remove-hook 'kill-buffer-hook #'sommaire--stop t)
  (unless (seq-some (lambda (buffer) (buffer-local-value 'sommaire-mode buffer)) (buffer-list))
    (when sommaire--timer
      (cancel-timer sommaire--timer)
      (setq sommaire--timer nil))))

(provide 'sommaire)

;;; sommaire.el ends here

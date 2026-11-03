;;; imprimeur-xwidget.el --- The page in an Emacs window  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; A view is a buffer holding one xwidget, which shows a session's page in an
;; Emacs window of the Emacs frame, beside the source.  The session owns the
;; view; the view owns its xwidget and its watchdog's timer, and killing it
;; releases both and asks nothing.  The page does not know where it is: it talks
;; to Emacs by the event stream and by POST, as it does in a browser.
;;
;; xwidget.el comes with the first view and not with this file, as it adds global
;; hooks and keys.  Of what it offers, a view takes the major mode, exactly
;; `xwidget-webkit-mode', whose resizing tests it with `eq', and leaves the rest:
;; `xwidget-webkit-browse-url' reuses the last session and `switch-to-buffer's it,
;; and `xwidget-webkit-callback' renames the buffer and answers a download with a
;; prompt and a file.  So the callback here goes by events, and a page holds no
;; way to write a file, to open a new xwidget or to stay on another site.
;;
;; The keys of `xwidget-webkit-mode' scroll with a script, which the page cannot
;; tell from a scroll of its own, so that the source would not follow.
;; `imprimeur-view-mode' has them ask the page to scroll as the reader's wheel
;; does.  A script holds an integer and nothing of the document.
;;
;; `imprimeur-xwidget--next' is the watchdog's one decision, pure and judged by a
;; table.  Its limit: two viewers of one session share what it hears, as a message
;; says nothing of who sent it.  So a `ready' of a browser's desktop window also
;; counts for the view, and a stream closing only counts when it was the last.

;;; Code:

(require 'seq)
(declare-function imprimeur-jump "imprimeur" ())
(declare-function xwidget-insert "xwidget" (pos type title width height &optional args related))
(declare-function xwidget-put "xwidget" (xwidget propname value))
(declare-function xwidget-webkit-mode "xwidget" ())
(declare-function xwidget-webkit-adjust-size-to-window "xwidget" (xwidget &optional window))
(declare-function set-xwidget-query-on-exit-flag "xwidget.c" (xwidget flag))
(declare-function kill-xwidget "xwidget.c" (xwidget))
(declare-function xwidget-webkit-goto-uri "xwidget.c" (xwidget uri))
(declare-function xwidget-webkit-uri "xwidget.c" (xwidget))
(declare-function xwidget-webkit-execute-script "xwidget.c" (xwidget script &optional callback))

(defcustom imprimeur-display-buffer-action
  '((display-buffer-reuse-window display-buffer-in-direction)
    (direction . right)
    (window . root)
    (window-width . 0.5)
    (dedicated . t)
    (reusable-frames . visible))
  "How `display-buffer' shows a page in an Emacs window.
By default on the right of the Emacs frame, over half its width, in an
Emacs window that shows nothing else; the source stays selected.  With
`((display-buffer-same-window))', the page takes the source's Emacs
window, and quitting it brings the source back.  An entry of
`display-buffer-alist' for the category `imprimeur' comes first."
  :type display-buffer--action-custom-type
  :risky t
  :group 'imprimeur)

(defconst imprimeur-xwidget--wait 3
  "The seconds a page has to report a revision before it counts as lost.")

(defconst imprimeur-xwidget--far (* 1024 1024 1024)
  "A distance in pixels longer than any page, for its two ends.")

(defvar-local imprimeur-xwidget--xwidget nil
  "The xwidget of this view.")

(defvar-local imprimeur-xwidget--url nil
  "The address of the page of this view.")

(defvar-local imprimeur-xwidget--source nil
  "The buffer whose page this view shows.")

(defvar-local imprimeur-xwidget--waiting nil
  "A function that says whether a page is rightly silent, having nothing to show.")

(defvar-local imprimeur-xwidget--state 'loading
  "The state of the watchdog: see `imprimeur-xwidget--next'.")

(defvar-local imprimeur-xwidget--timer nil
  "The timer of the watchdog, while it waits for a page.")

(defvar imprimeur-view-mode-map)

(defun imprimeur-xwidget--next (state event)
  "Return (NEXT . ACTION), what the watchdog does in STATE at EVENT.
A state is `loading', when the page has its first chance; `retrying',
when it has been loaded again for its second; `live', when it has
reported a revision; and `failed', when it has not, and nothing more is
tried.  An event is `timeout', when `imprimeur-xwidget--wait' seconds
have passed; `waiting', when they have, but the page is rightly silent;
`ready', when a page reports a revision; and `closed', when the last
stream of the session closes.  ACTION is `reload', `offer' to offer the
browser, or nil.  A timer runs in the states `loading' and `retrying'."
  (pcase (cons state event)
    (`(,_ . ready) '(live))
    ('(loading . timeout) '(retrying . reload))
    ('(retrying . timeout) '(failed . offer))
    ('(live . closed) '(loading . reload))
    (_ (list state))))

(defun imprimeur-xwidget-note (view event)
  "Tell the watchdog of VIEW of EVENT, an event of `imprimeur-xwidget--next'.
VIEW is a buffer, or nil, or dead, when nothing happens: a session asks
without knowing whether its view is there."
  (when (buffer-live-p view)
    (with-current-buffer view
      (pcase-let ((`(,state . ,action) (imprimeur-xwidget--next imprimeur-xwidget--state event))
                  (waiting imprimeur-xwidget--waiting))
        (setq imprimeur-xwidget--state state
              mode-line-process (and (eq state 'failed) " not answering"))
        (force-mode-line-update)
        (when imprimeur-xwidget--timer (cancel-timer imprimeur-xwidget--timer))
        (setq imprimeur-xwidget--timer
              (and (memq state '(loading retrying))
                   (run-at-time imprimeur-xwidget--wait nil
                                (lambda ()
                                  (imprimeur-xwidget-note view (if (funcall waiting) 'waiting 'timeout))))))
        (pcase action
          ('reload (xwidget-webkit-goto-uri imprimeur-xwidget--xwidget imprimeur-xwidget--url))
          ('offer (message "The page does not answer in %s: `M-x imprimeur-browse' opens it in a browser"
                           (buffer-name))))))))

(defun imprimeur-xwidget--event (url xwidget type)
  "Act on the event of TYPE from XWIDGET, which shows the page at URL.
The rest of it is in `last-input-event'.  A load committed outside the
session, whose addresses all start with URL's up to its token and a
slash, goes back to the page.  A script's result goes to the function
waiting for it.  Anything else does nothing, a download above all."
  (pcase type
    ('load-changed
     (when (and (equal (nth 3 last-input-event) "load-committed")
                (not (string-prefix-p (concat (mapconcat #'identity (seq-take (split-string url "/") 4) "/") "/")
                                      (or (xwidget-webkit-uri xwidget) ""))))
       (xwidget-webkit-goto-uri xwidget url)))
    ('javascript-callback
     (funcall (nth 3 last-input-event) (nth 4 last-input-event)))))

(defun imprimeur-xwidget--one-window (window)
  "Give WINDOW its previous buffer back if another Emacs window shows this view.
An xwidget takes input in one place only."
  (when (cdr (get-buffer-window-list (window-buffer window) nil t))
    (switch-to-prev-buffer window)))

(define-minor-mode imprimeur-view-mode
  "The keys of a view, which holds the page of a buffer in an Emacs window.
The keys that scroll scroll the page as the wheel does, so that the
source follows, and `imprimeur-jump' goes back to the source.

\\{imprimeur-view-mode-map}"
  :interactive nil
  :group 'imprimeur
  (setq-local minor-mode-overriding-map-alist
              (and imprimeur-view-mode (list (cons 'imprimeur-view-mode imprimeur-view-mode-map)))))

(defun imprimeur-xwidget--scroll (pixels)
  "Scroll the page of this view by PIXELS towards its end, as the reader would."
  (xwidget-webkit-execute-script imprimeur-xwidget--xwidget (format "imprimeur.scrollBy(%d)" pixels)))

(defun imprimeur-xwidget--page (lines)
  "Return how many pixels to scroll for LINES, a raw prefix argument.
Without one, nearly the height of the selected Emacs window."
  (if lines
      (* (prefix-numeric-value lines) (window-font-height))
    (- (window-body-height nil t) (* next-screen-context-lines (window-font-height)))))

(defun imprimeur-view-scroll-up (&optional lines)
  "Scroll the page towards its end, by LINES or by nearly its height."
  (interactive "P" imprimeur-view-mode)
  (imprimeur-xwidget--scroll (imprimeur-xwidget--page lines)))

(defun imprimeur-view-scroll-down (&optional lines)
  "Scroll the page towards its start, by LINES or by nearly its height."
  (interactive "P" imprimeur-view-mode)
  (imprimeur-xwidget--scroll (- (imprimeur-xwidget--page lines))))

(defun imprimeur-view-next-line (&optional lines)
  "Scroll the page towards its end by LINES."
  (interactive "p" imprimeur-view-mode)
  (imprimeur-xwidget--scroll (* (or lines 1) (window-font-height))))

(defun imprimeur-view-previous-line (&optional lines)
  "Scroll the page towards its start by LINES."
  (interactive "p" imprimeur-view-mode)
  (imprimeur-xwidget--scroll (- (* (or lines 1) (window-font-height)))))

(defun imprimeur-view-top ()
  "Scroll to the start of the page."
  (interactive nil imprimeur-view-mode)
  (imprimeur-xwidget--scroll (- imprimeur-xwidget--far)))

(defun imprimeur-view-bottom ()
  "Scroll to the end of the page."
  (interactive nil imprimeur-view-mode)
  (imprimeur-xwidget--scroll imprimeur-xwidget--far))

;; After the mode: `define-minor-mode' puts a map that it finds bound in
;; `minor-mode-map-alist', which loading the package leaves alone.
(defvar-keymap imprimeur-view-mode-map
  :doc "The keys of `imprimeur-view-mode'."
  "M-g v" #'imprimeur-jump
  "SPC" #'imprimeur-view-scroll-up
  "S-SPC" #'imprimeur-view-scroll-down
  "DEL" #'imprimeur-view-scroll-down
  "<remap> <scroll-up-command>" #'imprimeur-view-scroll-up
  "<remap> <scroll-down-command>" #'imprimeur-view-scroll-down
  "<remap> <scroll-up>" #'imprimeur-view-next-line
  "<remap> <scroll-down>" #'imprimeur-view-previous-line
  "<remap> <next-line>" #'imprimeur-view-next-line
  "<remap> <previous-line>" #'imprimeur-view-previous-line
  "<remap> <beginning-of-buffer>" #'imprimeur-view-top
  "<remap> <end-of-buffer>" #'imprimeur-view-bottom)

(defun imprimeur-xwidget-open (url source waiting)
  "Return a new view of the page at URL, of the buffer SOURCE, without showing it.
WAITING, a function, says whether a page is rightly silent, which keeps
the watchdog from counting that against it."
  (require 'xwidget)
  (let ((view (generate-new-buffer (format "*imprimeur: %s*" (buffer-name source)))))
    (condition-case failure
        (with-current-buffer view
          (insert " ")
          (let ((xwidget (xwidget-insert (point-min) 'webkit (buffer-name) 800 600)))
            (set-xwidget-query-on-exit-flag xwidget nil)
            (xwidget-put xwidget 'callback (apply-partially #'imprimeur-xwidget--event url))
            (xwidget-put xwidget 'display-callback (lambda (new _source) (kill-xwidget new)))
            (xwidget-webkit-mode)
            (imprimeur-view-mode 1)
            ;; The page has its title, and scrolls by itself.
            (setq header-line-format nil
                  vertical-scroll-bar nil
                  imprimeur-xwidget--xwidget xwidget
                  imprimeur-xwidget--url url
                  imprimeur-xwidget--source source
                  imprimeur-xwidget--waiting waiting)
            (add-hook 'kill-buffer-hook
                      (lambda ()
                        (when imprimeur-xwidget--timer (cancel-timer imprimeur-xwidget--timer)))
                      nil t)
            (add-hook 'window-buffer-change-functions #'imprimeur-xwidget--one-window nil t)
            (xwidget-webkit-goto-uri xwidget url)
            (imprimeur-xwidget-note view 'waiting)
            view))
      (error (kill-buffer view)
             (signal (car failure) (cdr failure))))))

(defun imprimeur-xwidget-display (view)
  "Show VIEW as `imprimeur-display-buffer-action' says, sized to its Emacs window."
  (when-let* ((window (display-buffer view (cons (car imprimeur-display-buffer-action)
                                                 (cons '(category . imprimeur)
                                                       (cdr imprimeur-display-buffer-action))))))
    (xwidget-webkit-adjust-size-to-window (buffer-local-value 'imprimeur-xwidget--xwidget view) window)))

(defun imprimeur-xwidget-close (view)
  "End VIEW, a buffer, or nil, or dead; killing it asks nothing."
  (when (buffer-live-p view)
    (kill-buffer view)))

(defun imprimeur-xwidget-back ()
  "Go from this view to its source, and ask the page for the line at its top.
The Emacs window of the source is selected; when none shows it, this one
does, unless it shows nothing else."
  (xwidget-webkit-execute-script imprimeur-xwidget--xwidget "imprimeur.postTop()")
  (pop-to-buffer imprimeur-xwidget--source '((display-buffer-reuse-window display-buffer-same-window))))

(provide 'imprimeur-xwidget)

;;; imprimeur-xwidget.el ends here

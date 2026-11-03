;;; imprimeur-menu.el --- The menu of a view's skin and options  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; `imprimeur-skin-menu' is a transient drawn anew from the registry after each key:
;; a key per registered skin, and a key per option of the skin shown, which cycles its
;; registered values.  It calls the two commands that a reader may call by completion,
;; and stays open, so that one can try skin after skin.
;;
;; The core loads this file with the first menu, as transient adds a global hook.

;;; Code:

(require 'seq)
(require 'transient)
(require 'imprimeur)

(defun imprimeur-menu--skins (_children)
  "Return the menu's suffixes of the skins, with the one shown marked.
Transient calls this each time that it draws the menu."
  (let* ((shown (imprimeur--session-skin (imprimeur--here)))
         (names (imprimeur-skin-names))
         (keys (imprimeur-skin-menu-keys
                (mapcar (lambda (name) (cons name (plist-get (imprimeur-skin-get name) :menu-key)))
                        names))))
    (transient-parse-suffixes
     'imprimeur-skin-menu
     (seq-keep (lambda (name)
                 (when-let* ((key (cdr (assoc name keys))))
                   (list key
                         (format "%s %s" (if (equal name shown) "*" " ")
                                 (plist-get (imprimeur-skin-get name) :title))
                         (lambda () (interactive) (imprimeur-choose-skin name))
                         :transient t)))
               names))))

(defun imprimeur-menu--options (_children)
  "Return the menu's suffixes of the options of the skin shown, and what keeps them.
None for a skin with no options, which leaves their group out.  An option's
key is a capital, which a skin's cannot be.  Transient calls this each time
that it draws the menu."
  (let* ((session (imprimeur--here))
         (name (imprimeur--session-skin session))
         (manifest (imprimeur-skin-get name))
         (options (plist-get manifest :options))
         (configured (imprimeur-skin-configured name manifest))
         (chosen (cdr (assoc name (imprimeur--session-skin-choices session))))
         (keys (imprimeur-skin-menu-keys
                (mapcar (lambda (option) (list (symbol-name (car option)))) options))))
    (transient-parse-suffixes
     'imprimeur-skin-menu
     (append
      (seq-keep (lambda (option)
                  (when-let* ((id (symbol-name (car option)))
                              (key (cdr (assoc id keys))))
                    (let* ((choices (plist-get (cdr option) :choices))
                           (value (imprimeur-skin-option-value option configured chosen))
                           (next (car (or (cadr (member (assoc value choices) choices)) (car choices)))))
                      (list (upcase key)
                            (format "%s: %s" (plist-get (cdr option) :label) (cdr (assoc value choices)))
                            (lambda () (interactive) (imprimeur-set-skin-option id next))
                            :transient t))))
                options)
      (and chosen
           (list (list :info (format "To keep it: %S" (cons (intern-soft name) chosen)))))))))

(transient-define-prefix imprimeur-skin-menu ()
  "Open the menu of this view's skin and its options, keeping the reader's place.
Each key changes the page at once, and the menu stays open.  In the source
buffer and in the view."
  :refresh-suffixes t
  ["Skin of this view"
   :class transient-column
   :setup-children imprimeur-menu--skins]
  [:description
   (lambda ()
     (format "Options of %s"
             (plist-get (imprimeur-skin-get (imprimeur--session-skin (imprimeur--here))) :title)))
   :class transient-column
   :setup-children imprimeur-menu--options]
  (interactive)
  (imprimeur--here)
  (transient-setup 'imprimeur-skin-menu))

(provide 'imprimeur-menu)

;;; imprimeur-menu.el ends here

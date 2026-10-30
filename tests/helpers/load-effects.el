;;; load-effects.el --- Report what loading a feature changes  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Loaded by a child Emacs in the load tests: `load-effects-report' requires
;; a feature and prints, as one Lisp form, how the global state changed.
;; A package must not change it merely by being loaded.

;;; Code:

(require 'seq)

(defun load-effects--snapshot ()
  "Return the global state that loading a package must leave alone."
  (let (hooks)
    (mapatoms (lambda (symbol)
                (when (and (boundp symbol)
                           (string-match-p "-\\(?:hook\\|functions\\)\\'" (symbol-name symbol))
                           (listp (default-value symbol)))
                  (push (cons symbol (copy-tree (default-value symbol))) hooks))))
    (list :timers (length (append timer-list timer-idle-list))
          :hooks hooks
          ;; Prefix keys such as C-c are bound to symbols whose function
          ;; is a keymap, so the global map's own printed form misses them.
          :global-map (prin1-to-string (accessible-keymaps global-map))
          :minor-modes (prin1-to-string minor-mode-map-alist)
          :auto-modes (prin1-to-string auto-mode-alist))))

(defun load-effects-report (feature)
  "Require FEATURE and print how the global state changed.
The form printed is a plist: the number of timers added, the hook
variables whose global value changed, whether the global keymap,
the minor mode keymaps or `auto-mode-alist' changed, and which of
the repository's two features are loaded."
  (let ((before (load-effects--snapshot)))
    (require feature)
    (let ((after (load-effects--snapshot))
          (old-hooks (plist-get before :hooks)))
      (prin1 (list :timers (- (plist-get after :timers) (plist-get before :timers))
                   :hooks (sort (mapcar #'car
                                        (seq-remove (lambda (entry)
                                                      (equal (cdr entry)
                                                             (cdr (assq (car entry) old-hooks))))
                                                    (plist-get after :hooks)))
                                #'string<)
                   :global-map (not (equal (plist-get after :global-map)
                                           (plist-get before :global-map)))
                   :minor-modes (not (equal (plist-get after :minor-modes)
                                            (plist-get before :minor-modes)))
                   :auto-modes (not (equal (plist-get after :auto-modes)
                                           (plist-get before :auto-modes)))
                   :sommaire (featurep 'sommaire)
                   :imprimeur (featurep 'imprimeur))))))

(provide 'load-effects)

;;; load-effects.el ends here

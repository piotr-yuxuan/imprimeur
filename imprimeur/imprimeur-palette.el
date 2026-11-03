;;; imprimeur-palette.el --- The page's colours, from the Emacs theme  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The page takes its colours and fonts from the faces of the frame that
;; shows the source buffer: they become CSS custom properties, --emacs-bg,
;; --emacs-kw and the like, on :root, which the skins read with their own
;; values as fallbacks.  A property whose face gives nothing is left out.
;;
;; A change of theme enables and disables several themes in a row, each
;; running a hook; the hooks only arm a timer, which reads the faces once,
;; 50 ms later, and calls the watchers, unless `enable-theme' is still
;; running, which something that spins events can let it see: it then waits
;; again.  The hooks are added with the first watcher and removed, with the
;; timer, by the last.

;;; Code:

(require 'cl-lib)
(require 'color)
(require 'seq)

(defcustom imprimeur-appearance 'auto
  "Whether the page is light or dark.
`auto' follows the background mode of the frame whose faces give the
page its colours; `light' and `dark' force one, while the colours stay
the theme's, so that a skin that must read on the ground goes by
--emacs-bg-luminance.  A change shows at the next change of theme, or at
once with `imprimeur-refresh-palette'."
  :type '(choice (const :tag "As the frame" auto)
                 (const :tag "Light" light)
                 (const :tag "Dark" dark))
  :group 'imprimeur)

(defconst imprimeur-palette--colors
  '(("bg" :background default)
    ("fg" :foreground default)
    ("muted" :foreground shadow)
    ("link" :foreground org-link markdown-link-face link button)
    ("h1" :foreground org-level-1 markdown-header-face-1 outline-1)
    ("h2" :foreground org-level-2 markdown-header-face-2 outline-2)
    ("h3" :foreground org-level-3 markdown-header-face-3 outline-3)
    ("h4" :foreground org-level-4 markdown-header-face-4 outline-4)
    ("h5" :foreground org-level-5 markdown-header-face-5 outline-5)
    ("h6" :foreground org-level-6 markdown-header-face-6 outline-6)
    ("region" :background region)
    ("mode-line-bg" :background mode-line)
    ("code-bg" :background org-block markdown-code-face)
    ("ansi-0" :foreground ansi-color-black)
    ("ansi-1" :foreground ansi-color-red)
    ("ansi-2" :foreground ansi-color-green)
    ("ansi-3" :foreground ansi-color-yellow)
    ("ansi-4" :foreground ansi-color-blue)
    ("ansi-5" :foreground ansi-color-magenta)
    ("ansi-6" :foreground ansi-color-cyan)
    ("ansi-7" :foreground ansi-color-white))
  "The colour properties, each (NAME ATTRIBUTE FACE...).
NAME follows --emacs- in the property's name; ATTRIBUTE, :foreground
or :background, is read on the first FACE that exists and gives one.
The faces keep this order, except that `imprimeur-palette' moves those
named org-* according to the buffer's major mode.")

(defconst imprimeur-palette--tokens
  '(("kw" . font-lock-keyword-face) ("str" . font-lock-string-face)
    ("com" . font-lock-comment-face) ("fn" . font-lock-function-name-face)
    ("var" . font-lock-variable-name-face) ("type" . font-lock-type-face)
    ("const" . font-lock-constant-face) ("builtin" . font-lock-builtin-face)
    ("pre" . font-lock-preprocessor-face) ("doc" . font-lock-doc-face)
    ("warn" . font-lock-warning-face))
  "The code tokens, each (NAME . FACE): their colour, weight and slant.")

(defconst imprimeur-palette--weights
  '((0 . 100) (40 . 200) (50 . 300) (55 . 350) (80 . 400) (100 . 500)
    (180 . 600) (200 . 700) (205 . 800) (210 . 900) (250 . 950))
  "CSS font weights, by the numbers that `font-weight-table' gives.")

(defconst imprimeur-palette--slants
  '((0 . "oblique") (10 . "italic") (100 . "normal") (200 . "italic") (210 . "oblique"))
  "CSS font styles, by the numbers that `font-slant-table' gives.")

(defvar imprimeur-palette--watchers nil
  "The functions to call, with no argument, when the palette may change.")

(defvar imprimeur-palette--timer nil
  "The armed timer that calls the watchers, or nil.")

(defun imprimeur-palette-color (spec graphic)
  "Return the colour SPEC as #rrggbb, or nil when it names none.
SPEC is a face attribute's value: a string such as \"#abc\",
\"#00c000c000c0\", \"rgb:f/8/0\" or a colour's name, or a symbol such
as `unspecified'.  GRAPHIC is a graphic frame, whose display resolves
the names, or nil: the standard names then do, in any case.  Each
channel of 16 bits is scaled to 8 by rounding."
  (when-let* (((stringp spec))
              (values (or (color-values-from-color-spec spec)
                          (if graphic
                              (color-values spec graphic)
                            (tty-color-standard-values (downcase spec))))))
    (apply #'format "#%02x%02x%02x" (mapcar (lambda (value) (round value 257)) values))))

(defun imprimeur-palette-luminance (color)
  "Return the relative luminance of COLOR, from 0 to 1, as text, or nil.
COLOR is a colour as #rrggbb, or nil, which has none."
  (when color
    (format "%.4f" (nth 1 (apply #'color-srgb-to-xyz
                                 (mapcar (lambda (value) (/ value 65535.0))
                                         (color-values-from-color-spec color)))))))

(defun imprimeur-palette-css (faces)
  "Return the CSS that gives the page the colours and fonts of FACES.
FACES is an alist from a NAME, such as \"kw\", to a plist of what its
faces give: :color, a colour as #rrggbb, or nil, or for \"bg-luminance\"
what `imprimeur-palette-luminance' gives; :weight, :slant and :family, as
`face-attribute' gives them.  Each becomes a custom
property on :root: :color --emacs-NAME, :weight --emacs-NAME-weight,
:slant --emacs-NAME-style and :family --emacs-NAME, quoted, when it
holds only letters, digits, spaces, dots, hyphens and underscores.
An attribute that is nil, unspecified or unknown is left out, as is
the family \"default\" of a text terminal's faces, which names no
font.  The CSS names no colour scheme: the page takes it from the
palette's appearance."
  (let ((css (lambda (symbol table values)
               ;; The CSS value for SYMBOL, by the number Emacs's TABLE gives it.
               (and (not (eq symbol 'unspecified))
                    (alist-get (seq-some (lambda (entry)
                                           (and (memq symbol (append entry nil)) (aref entry 0)))
                                         table)
                               values)))))
    (concat
     ":root {\n"
     (mapconcat
      (lambda (face)
        (let ((name (car face))
              (color (plist-get (cdr face) :color))
              (family (plist-get (cdr face) :family)))
          (concat
           (when color (format "  --emacs-%s: %s;\n" name color))
           (when-let* ((weight (funcall css (plist-get (cdr face) :weight) font-weight-table
                                        imprimeur-palette--weights)))
             (format "  --emacs-%s-weight: %d;\n" name weight))
           (when-let* ((style (funcall css (plist-get (cdr face) :slant) font-slant-table
                                       imprimeur-palette--slants)))
             (format "  --emacs-%s-style: %s;\n" name style))
           (when (and (stringp family) (not (equal family "default"))
                      (string-match-p "\\`[[:alnum:] ._-]+\\'" family))
             (format "  --emacs-%s: \"%s\";\n" name family)))))
      faces "")
     "}\n")))

(defun imprimeur-palette--inverse (attribute foreground background page)
  "Return the colour that a face in inverse video shows as its ATTRIBUTE.
Emacs paints the face's text in BACKGROUND, on a block of FOREGROUND, each
of them that of `default' where the face gives none.  So `:foreground' asks
for BACKGROUND and `:background' for FOREGROUND, except that a page has no
block: text in PAGE, its own background, would vanish there, and takes the
block's colour."
  (if (and (eq attribute :foreground) (not (equal background page)))
      background
    foreground))

(defun imprimeur-palette--shown (attribute inverse)
  "Return the attribute of a face that Emacs paints as its ATTRIBUTE, on a block.
INVERSE says that the face is in inverse video, which swaps the two."
  (cond ((not inverse) attribute)
        ((eq attribute :foreground) :background)
        (t :foreground)))

(defun imprimeur-palette (buffer)
  "Return the palette of BUFFER's page: (:css CSS :appearance APPEARANCE).
The faces are read on a graphic frame showing BUFFER, else on the
selected frame, with their inheritance and inverse video; for each
property, the first face of its list that exists and gives a value
wins.  A face named org-* comes first in a buffer whose major mode
derives from `org-mode' and last in any other, or a dead one, so that
a page does not change colours when an Org file happens to load Org.
APPEARANCE, \"light\" or \"dark\", is that frame's background mode
unless `imprimeur-appearance' forces one."
  (let* ((frame (or (seq-find #'display-graphic-p
                              (mapcar #'window-frame (and (buffer-live-p buffer)
                                                          (get-buffer-window-list buffer nil t))))
                    (selected-frame)))
         (graphic (and (display-graphic-p frame) frame))
         (org (and (buffer-live-p buffer) (with-current-buffer buffer (derived-mode-p 'org-mode))))
         (painted (lambda (face attribute)
                    ;; What Emacs paints, where a face leaves a colour to `default'.
                    (imprimeur-palette-color (face-attribute face attribute frame 'default) graphic)))
         (inverse (lambda (face) (eq (face-attribute face :inverse-video frame t) t)))
         (page (funcall painted 'default (imprimeur-palette--shown :background (funcall inverse 'default))))
         (color (lambda (attribute faces)
                  (seq-some (lambda (face)
                              (and (facep face)
                                   (if (funcall inverse face)
                                       (imprimeur-palette--inverse attribute
                                                                   (funcall painted face :foreground)
                                                                   (funcall painted face :background)
                                                                   page)
                                     (imprimeur-palette-color (face-attribute face attribute frame t)
                                                              graphic))))
                            (sort faces :key (lambda (face)
                                               (if (xor org (string-prefix-p "org-" (symbol-name face)))
                                                   1
                                                 0))))))
         (appearance (if (memq imprimeur-appearance '(light dark))
                         imprimeur-appearance
                       (frame-parameter frame 'background-mode))))
    (list :css (imprimeur-palette-css
                (append (mapcar (lambda (entry)
                                  (list (car entry) :color (funcall color (cadr entry) (cddr entry))))
                                imprimeur-palette--colors)
                        (mapcar (lambda (token)
                                  (list (car token)
                                        :color (funcall color :foreground (list (cdr token)))
                                        :weight (face-attribute (cdr token) :weight frame t)
                                        :slant (face-attribute (cdr token) :slant frame t)))
                                imprimeur-palette--tokens)
                        (list (list "bg-luminance" :color (imprimeur-palette-luminance page))
                              ;; On its own bar, so what Emacs paints, in inverse video too.
                              (list "mode-line-fg"
                                    :color (funcall painted 'mode-line
                                                    (imprimeur-palette--shown :foreground (funcall inverse 'mode-line))))
                              (list "font-mono" :family (face-attribute 'default :family frame t))
                              (list "font-variable"
                                    :family (face-attribute 'variable-pitch :family frame t)))))
          :appearance (symbol-name appearance))))

(defun imprimeur-palette-watch (function)
  "Call FUNCTION, with no argument, whenever the palette may have changed.
That is 50 ms after a theme is enabled or disabled, and at
`imprimeur-refresh-palette'.  The first watcher adds the theme hooks."
  (add-hook 'enable-theme-functions #'imprimeur-palette--arm)
  (add-hook 'disable-theme-functions #'imprimeur-palette--arm)
  (cl-pushnew function imprimeur-palette--watchers))

(defun imprimeur-palette-unwatch (function)
  "Stop calling FUNCTION; the last watcher removes the hooks and the timer."
  (setq imprimeur-palette--watchers (delq function imprimeur-palette--watchers))
  (unless imprimeur-palette--watchers
    (remove-hook 'enable-theme-functions #'imprimeur-palette--arm)
    (remove-hook 'disable-theme-functions #'imprimeur-palette--arm)
    (when imprimeur-palette--timer (cancel-timer imprimeur-palette--timer))
    (setq imprimeur-palette--timer nil)))

(defun imprimeur-palette--arm (&rest _)
  "Arm the timer that calls the watchers, unless it is armed.
The theme hooks run this for each theme of a switch, and only this:
the faces are read once, after the last."
  (unless imprimeur-palette--timer
    (setq imprimeur-palette--timer (run-at-time 0.05 nil #'imprimeur-palette--settle))))

(defun imprimeur-palette--settle ()
  "Refresh the palette, unless `enable-theme' is running: then arm again.
A timer runs wherever something spins events, as the `:set' of a theme's
option does with a D-Bus call.  Inside `enable-theme', the functions of
`enable-theme-functions' have not finished the faces yet."
  (setq imprimeur-palette--timer nil)
  (if (backtrace-frame 0 #'enable-theme)
      (imprimeur-palette--arm)
    (imprimeur-refresh-palette)))

(defun imprimeur-refresh-palette ()
  "Give the current palette to every page whose palette changed.
A change of theme does this by itself; a face changed otherwise, or
`imprimeur-appearance', shows after this command."
  (interactive)
  (when imprimeur-palette--timer (cancel-timer imprimeur-palette--timer))
  (setq imprimeur-palette--timer nil)
  (mapc #'funcall imprimeur-palette--watchers))

(provide 'imprimeur-palette)

;;; imprimeur-palette.el ends here

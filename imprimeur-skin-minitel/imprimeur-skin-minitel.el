;;; imprimeur-skin-minitel.el --- A tribute to the Minitel, for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.6
;; Package-Requires: ((emacs "31.1") (imprimeur "0.0.0"))
;; Keywords: text, wp

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The skin Minitel of imprimeur: a tribute to the terminal, not a costume of it.  An
;; 80-column block of Emacs's own family in a thin frame that stays on the screen, row 0
;; above it, the terminal's keys below it, and every colour from the Emacs theme.
;; Installing this package registers it once imprimeur loads, and `imprimeur-skin' at
;; `auto' then starts every page in it; `M-g o' chooses its palette, columns and key bar.
;; README.md beside this file says what its keys do and what it gives up of a view's.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-minitel-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin Minitel, beside this file.")

(imprimeur-skin-define 'minitel
  :title "Minitel"
  :directory imprimeur-skin-minitel-directory
  :stylesheets '("skin.css")
  :module "page.mjs"
  :keys '("s" "p" "n" "?" "e" "g" "q" "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
          "Enter" "Backspace" "Escape")
  :auto t
  :options
  '((palette :label "Palette" :default "emacs"
             :choices (("emacs" . "Emacs: every colour from the theme, past a floor of lightness")
                       ("videotex" . "Vidéotex: the terminal's eight colours")
                       ("greys" . "Minitel 1 greys: the same eight as a Minitel 1 showed them")))
    (columns :label "Columns" :default "80"
             :choices (("80" . "80")
                       ("40" . "40: the purist's screen, in larger letters")))
    (keys :label "Key bar" :default "fixed"
          :choices (("fixed" . "On the screen")
                    ("end" . "At the end of the document; the keys still answer")
                    ("off" . "None; the keys still answer")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-minitel: %S" (require 'imprimeur-skin-minitel)))

(provide 'imprimeur-skin-minitel)

;;; imprimeur-skin-minitel.el ends here

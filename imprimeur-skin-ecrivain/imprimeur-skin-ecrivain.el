;;; imprimeur-skin-ecrivain.el --- Handwriting on paper, for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.4
;; Package-Requires: ((emacs "31.1") (imprimeur "0.0.0"))
;; Keywords: text, wp

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The skin Écrivain of imprimeur: handwriting on paper.  Cahier by default, the French
;; school hand Playwrite FR Moderne on Seyès paper, each baseline on a thick line and the
;; x-height on the first thin line above it; Trad is one choice away, and Carnet, Notes and
;; Ardoise the other papers.  One long sheet by default, or leaves of a notebook.
;; Installing this package registers it once imprimeur loads; `M-g s' then chooses it, and
;; `M-g o' its variant, hand, ink and sheet.  README.md beside this file lists the fonts,
;; which fonts.nix builds: without them the letters do not sit on the ruling.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-ecrivain-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin Écrivain, beside this file.")

(imprimeur-skin-define 'ecrivain
  :title "Écrivain"
  :directory imprimeur-skin-ecrivain-directory
  :stylesheets '("skin.css")
  :filters '(common "filter.lua" french)
  :smart t
  :notes 'section
  :module "leaves.mjs"
  :options
  '((variant :label "Variant" :default "cahier"
             :choices (("cahier" . "Cahier: a school hand on Seyès paper")
                       ("carnet" . "Carnet: an orderly informal hand, on dots")
                       ("notes" . "Notes: a marker's hand, on small squares")
                       ("ardoise" . "Ardoise: chalk on a board")))
    (hand :label "Hand, in Cahier" :default "moderne"
          :choices (("moderne" . "Playwrite FR Moderne")
                    ("trad" . "Playwrite FR Trad")))
    (ink :label "Ink" :default "variante"
         :choices (("variante" . "The variant's own")
                   ("bleu-noir" . "Blue-black")
                   ("bleu" . "Royal blue")
                   ("noir" . "Black")
                   ("violet" . "School violet")
                   ("sepia" . "Sepia")))
    (sheet :label "Sheet" :default "pageless"
           :choices (("pageless" . "Pageless: one long sheet")
                     ("pages" . "Pages: leaves of a notebook")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-ecrivain: %S" (require 'imprimeur-skin-ecrivain)))

(provide 'imprimeur-skin-ecrivain)

;;; imprimeur-skin-ecrivain.el ends here

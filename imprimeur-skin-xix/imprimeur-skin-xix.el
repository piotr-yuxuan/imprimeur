;;; imprimeur-skin-xix.el --- French books of the XIXth century, for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.7
;; Package-Requires: ((emacs "31.1") (imprimeur "0.0.0"))
;; Keywords: text, wp

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The skin XIX of imprimeur: a French book of the XIXth century, in Junicode with
;; its ligatures, a vermilion title and lettrine, words broken by hyphenation, and
;; paper or candlelight as the theme's appearance says.  Installing this package
;; registers it once imprimeur loads; `M-g s' then chooses it, and `M-g o' its text
;; face, ligatures and measure.
;; README.md beside this file lists the fonts, which fonts.nix installs.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-xix-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin XIX, beside this file.")

(imprimeur-skin-define 'xix
  :title "XIX"
  :menu-key "9"
  :directory imprimeur-skin-xix-directory
  :stylesheets '("skin.css")
  :filters '(common french hyphenate "filter.lua")
  :smart t
  :notes 'section
  :options
  `((text-face :label "Text face" :default "junicode"
               :choices (("junicode" . "Junicode")
                         ("bodoni-moda" . "Bodoni Moda")
                         ("bodoni-moda-optical" . "Bodoni Moda, optical: a cut each for the title, the text and the notes")
                         ("playfair" . "Playfair")
                         ("playfair-display" . "Playfair Display")
                         ("old-standard" . "Old Standard")
                         ("theano" . "Theano Didot: no italic, no small capitals of its own")
                         ("libertinus" . "Libertinus Serif")
                         ("eb-garamond" . "EB Garamond 12")))
    (ligatures :label "Ligatures" :default "discretionary"
               :choices (("none" . "None")
                         ("common" . "Common")
                         ("discretionary" . "Discretionary, with Junicode's looped ct and st")
                         ("historical" . "Historical: as the default under Junicode, whose own abbreviates French")))
    (measure :label "Measure" :default "30"
             :choices ,(mapcar (lambda (half)
                                 (if (zerop (% half 2))
                                     (cons (format "%d" (/ half 2)) (format "%d rem" (/ half 2)))
                                   (cons (format "%d-5" (/ half 2)) (format "%d.5 rem" (/ half 2)))))
                               (number-sequence 48 80)))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-xix: %S" (require 'imprimeur-skin-xix)))

(provide 'imprimeur-skin-xix)

;;; imprimeur-skin-xix.el ends here

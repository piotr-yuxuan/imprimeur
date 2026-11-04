;;; imprimeur-skin-xviii.el --- French books of the XVIIIth century, for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.5
;; Package-Requires: ((emacs "31.1") (imprimeur "0.0.0"))
;; Keywords: text, wp

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The skin XVIII of imprimeur: a French book of the XVIIIth century, in Baskervville
;; with no long s, a red title in spaced capitals, fleuron bands, framed two-line
;; lettrines, and paper or candlelight as the theme's appearance says.  Installing this
;; package registers it once imprimeur loads; `M-g s' then chooses it, and `M-g o' its
;; face, long s and bands.  README.md beside this file lists the fonts, which fonts.nix
;; installs.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-xviii-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin XVIII, beside this file.")

(imprimeur-skin-define 'xviii
  :title "XVIII"
  :menu-key "8"
  :directory imprimeur-skin-xviii-directory
  :stylesheets '("skin.css")
  :filters '(common french hyphenate "filter.lua")
  :smart t
  :notes 'section
  :options
  '((face :label "Face" :default "baskervville"
          :choices (("baskervville" . "Baskervville")
                    ("junicode" . "Junicode")))
    (long-s :label "Long s, under Junicode only: Baskervville has none" :default "off"
            :choices (("off" . "Off")
                      ("on" . "On, under Junicode only")))
    (bands :label "Fleuron bands" :default "fleurons"
           :choices (("fleurons" . "Fleurons")
                     ("rinceau" . "Rinceau")
                     ("entrelacs" . "Entrelacs")
                     ("perles" . "Perles")
                     ("filet" . "Filet: no ornament, a thick and a thin rule")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-xviii: %S" (require 'imprimeur-skin-xviii)))

(provide 'imprimeur-skin-xviii)

;;; imprimeur-skin-xviii.el ends here

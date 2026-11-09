;;; imprimeur-skin-dubai.el --- An Arabic business memo, for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.8
;; Package-Requires: ((emacs "31.1") (imprimeur "0.0.0"))
;; Keywords: text, wp

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The skin Dubai of imprimeur: what Briefing is to Latin, an Arabic business memo set
;; right to left, which gives the answer first: a bottom line, callouts, chips over
;; action titles, and columns of figures.  Its text is Noto Kufi Arabic with Inter for
;; Latin, its headings Alexandria, and its masthead and labels Kufam.  Installing this
;; package registers it once imprimeur loads; `M-g s' then chooses it, and `M-g o' its
;; accent, density, skim view, face and Hijri date.  It has no relation to the
;; Government of Dubai.  README.md beside this file lists the fonts, which fonts.nix
;; installs.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-dubai-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin Dubai, beside this file.")

(imprimeur-skin-define 'dubai
  :title "Dubai"
  :directory imprimeur-skin-dubai-directory
  :stylesheets '("skin.css")
  :filters '(common "filter.lua")
  :smart t
  :module "page.mjs"
  :menu-key "d"
  :options
  '((accent :label "Accent" :default "teal"
            :choices (("teal" . "Teal")
                      ("blue" . "Ink blue")
                      ("aubergine" . "Aubergine")
                      ("graphite" . "Graphite: links and keywords read as text")))
    (density :label "Density" :default "compact"
             :choices (("compact" . "Compact")
                       ("regular" . "Regular")
                       ("airy" . "Airy")))
    (skim :label "Skim view: the bottom line, the titles to level three and the callouts"
          :default "off"
          :choices (("off" . "Off")
                    ("on" . "On")))
    (face :label "Face of the text and headings" :default "kufi"
          :choices (("kufi" . "Noto Kufi Arabic, Alexandria and Inter")
                    ("plex" . "IBM Plex Sans Arabic and Plex Sans")))
    (hijri :label "Umm al-Qura date beside the masthead's date" :default "off"
           :choices (("off" . "Off")
                     ("on" . "On")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-dubai: %S" (require 'imprimeur-skin-dubai)))

(provide 'imprimeur-skin-dubai)

;;; imprimeur-skin-dubai.el ends here

;;; imprimeur-skin-briefing.el --- A modern business memo, for imprimeur  -*- lexical-binding: t; -*-

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

;; The skin Briefing of imprimeur: a modern business memo in Inter, read rather than
;; presented, compact by default, with one accent, colour otherwise only for status, and
;; the answer first: a bottom line, callouts, chips over action titles, and columns of
;; figures on the right.  Installing this package registers it once imprimeur loads;
;; `M-g s' then chooses it, and `M-g o' its accent, density and skim view.  README.md
;; beside this file lists the fonts, which fonts.nix installs.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-briefing-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin Briefing, beside this file.")

(imprimeur-skin-define 'briefing
  :title "Briefing"
  :directory imprimeur-skin-briefing-directory
  :stylesheets '("skin.css")
  :filters '(common french "filter.lua")
  :smart t
  :module "page.mjs"
  :options
  '((accent :label "Accent" :default "blue"
            :choices (("blue" . "Ink blue")
                      ("teal" . "Teal")
                      ("aubergine" . "Aubergine")
                      ("graphite" . "Graphite: links and keywords read as text")))
    (density :label "Density" :default "compact"
             :choices (("compact" . "Compact")
                       ("regular" . "Regular")
                       ("airy" . "Airy")))
    (skim :label "Skim view: the bottom line, the titles to level three and the callouts"
          :default "off"
          :choices (("off" . "Off")
                    ("on" . "On")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-briefing: %S" (require 'imprimeur-skin-briefing)))

(provide 'imprimeur-skin-briefing)

;;; imprimeur-skin-briefing.el ends here

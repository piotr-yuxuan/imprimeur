;;; imprimeur-skin-xvii.el --- French books of the XVIIth century, for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.10
;; Package-Requires: ((emacs "31.1") (imprimeur "0.0.0"))
;; Keywords: text, wp

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The skin XVII of imprimeur: a French book of the XVIIth century, in IM Fell English
;; with long s and historical ligatures, a red and black title page, woodcut bands,
;; three-line block initials, manchettes, and paper or candlelight as the theme's
;; appearance says.  Installing this package registers it once imprimeur loads; `M-g s'
;; then chooses it, and `M-g o' its face, long s, ligatures and manchettes.  README.md
;; beside this file lists the fonts, which fonts.nix installs.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-xvii-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin XVII, beside this file.")

(imprimeur-skin-define 'xvii
  :title "XVII"
  :menu-key "7"
  :directory imprimeur-skin-xvii-directory
  :stylesheets '("skin.css")
  :filters '(common french hyphenate "filter.lua")
  :smart t
  :notes 'section
  :options
  '((face :label "Face" :default "im-fell"
          :choices (("im-fell" . "IM Fell English")
                    ("eb-garamond" . "EB Garamond 12")
                    ("garamond-libre" . "Garamond Libre")))
    (long-s :label "Long s: Garamond Libre has none to give" :default "on"
            :choices (("on" . "On")
                      ("off" . "Off")))
    (ligatures :label "Historical ligatures: ct and a tied long s under IM Fell, none under Garamond Libre"
               :default "on"
               :choices (("on" . "On")
                         ("off" . "Off")))
    (manchettes :label "Manchettes: notes in the margin, or at the end of the section" :default "on"
                :choices (("on" . "On, where the Emacs window has a margin")
                          ("off" . "Off")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-xvii: %S" (require 'imprimeur-skin-xvii)))

(provide 'imprimeur-skin-xvii)

;;; imprimeur-skin-xvii.el ends here

;;; imprimeur-skin-yaqut.el --- An Arabic manuscript page, for imprimeur  -*- lexical-binding: t; -*-

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

;; The skin Yaqut of imprimeur: an Arabic manuscript page, after the schools that followed
;; Yaqut al-Musta'simi.  The text stands in a jadwal of ruled frames under an illuminated
;; headpiece, its headings and emphasis in red and gold, its notes in the margin, and it ends
;; on a colophon dated in the Hijri calendar, with a seal.  Installing this package registers
;; it once imprimeur loads; `M-g s' then chooses it, and `M-g o' its preset, title face, notes
;; and calendar.  README.md beside this file lists the fonts, which fonts.nix installs.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-yaqut-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin Yaqut, beside this file.")

(imprimeur-skin-define 'yaqut
  :title "Yaqut"
  :directory imprimeur-skin-yaqut-directory
  :stylesheets '("skin.css")
  :files '("unwan.svg" "rosette.svg")
  :filters '(common "filter.lua")
  :smart t
  :module "page.mjs"
  :menu-key "y"
  :options
  '((preset :label "Preset" :default "mamluk"
            :choices (("mamluk" . "Mamluk, Naskh under gold thuluth")
                      ("ottoman" . "Ottoman, Naskh under a vermilion thuluth")
                      ("persian" . "Persian, Nastaliq on lapis")))
    (title :label "Title face" :default "auto"
           :choices (("auto" . "Follows the preset")
                     ("thuluth" . "Thuluth, Katibeh")
                     ("kufi" . "Kufi, Qahiri")
                     ("raqq" . "Raqq, under the AGPL")))
    (notes :label "Notes" :default "auto"
           :choices (("auto" . "Follows the preset")
                     ("margin" . "In the margin")
                     ("oblique" . "Oblique in the margin")
                     ("foot" . "At the foot")))
    (calendar :label "Calendar" :default "umalqura"
              :choices (("umalqura" . "Umm al-Qura")
                        ("civil" . "Tabular, civil")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-yaqut: %S" (require 'imprimeur-skin-yaqut)))

(provide 'imprimeur-skin-yaqut)

;;; imprimeur-skin-yaqut.el ends here

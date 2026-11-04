;;; imprimeur-skin-tianlu.el --- A Song block-print page in vertical text, for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.2
;; Package-Requires: ((emacs "31.1") (imprimeur "0.0.0"))
;; Keywords: text, wp

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; The skin Tianlu of imprimeur: a Southern Song block-print page in Qing palace dress, set
;; in vertical text, in framed bands that still scroll down, each band a half-leaf with its
;; fold column.  A Chinese document takes corner brackets, double-line notes in place, and
;; 注音; code, diagrams, pictures and wide tables are horizontal plates.  Installing this
;; package registers it once imprimeur loads; `M-g s' then chooses it, and `M-g o' its
;; preset and face.  README.md beside this file lists the fonts, which fonts.nix installs.

;;; Code:

(require 'imprimeur-skin)

(defconst imprimeur-skin-tianlu-directory
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The files of the skin Tianlu, beside this file.")

(imprimeur-skin-define 'tianlu
  :title "Tianlu"
  :directory imprimeur-skin-tianlu-directory
  :stylesheets '("skin.css")
  :filters '(common "filter.lua")
  :smart t
  :module "page.mjs"
  :options
  '((preset :label "Preset" :default "song"
            :choices (("song" . "宋槧 Song, 10 × 20")
                      ("juzhen" . "聚珍 Juzhen, 9 × 21")
                      ("siku" . "四庫 Siku, 8 × 21")))
    (face :label "Face" :default "auto"
          :choices (("auto" . "Follows the preset")
                    ("moe" . "教育部宋 MOE Song")
                    ("kai" . "楷 Kai")
                    ("ming" . "明 Ming, 宋 Song")
                    ("fang" . "仿宋 Fangsong")))))

;; A skin that fails to load must not stop the mode, so a failure only says so.
;;;###autoload (with-eval-after-load 'imprimeur-skin (with-demoted-errors "imprimeur-skin-tianlu: %S" (require 'imprimeur-skin-tianlu)))

(provide 'imprimeur-skin-tianlu)

;;; imprimeur-skin-tianlu.el ends here

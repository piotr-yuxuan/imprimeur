;;; imprimeur-test-themes.el --- Two themes for the tests of the palette  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; A night theme and a day theme, defined but not enabled.  The night
;; theme writes its colours in each form a theme may use: a 16-bit spec,
;; a short spec, a name in mixed case; it leaves `link' unspecified and
;; gives `org-link' and `button', after it in the chain of links, colours
;; of their own; `font-lock-doc-face' inherits the string
;; colour, weight and slant, `org-level-1' the function name colour
;; through `outline-1'; `region' and `font-lock-warning-face' are in
;; inverse video, which `font-lock-builtin-face' inherits.  The day
;; theme gives each face of the chains of links and headings a colour of
;; its own, so that the first face of a chain that exists is seen to win.

;;; Code:

(deftheme imprimeur-test-night "A dark theme for the tests of imprimeur.")

(custom-theme-set-faces
 'imprimeur-test-night
 '(default ((t :foreground "#c5c8c6" :background "#1d1f21")))
 '(shadow ((t :foreground "#00c000c000c0")))
 '(font-lock-keyword-face ((t :foreground "#abc" :weight semi-bold :slant italic)))
 '(font-lock-comment-face ((t :foreground "Gray50")))
 '(font-lock-string-face ((t :foreground "#b5bd68" :weight light :slant oblique)))
 '(font-lock-function-name-face ((t :foreground "#81a2be")))
 '(font-lock-warning-face ((t :inverse-video t :background "#cc6666")))
 '(font-lock-builtin-face ((t :inherit font-lock-warning-face)))
 '(link ((t nil)))
 '(org-link ((t :foreground "#8abeb7")))
 '(button ((t :foreground "#de935f")))
 '(region ((t :inverse-video t :foreground "#373b41"))))

(deftheme imprimeur-test-day "A light theme for the tests of imprimeur.")

(custom-theme-set-faces
 'imprimeur-test-day
 '(default ((t :foreground "#4d4d4c" :background "#ffffff")))
 '(font-lock-keyword-face ((t :foreground "#8959a8")))
 '(org-link ((t :foreground "#3e999f")))
 '(link ((t :foreground "#4271ae")))
 '(button ((t :foreground "#718c00")))
 '(org-level-1 ((t :foreground "#c82821")))
 '(org-level-2 ((t :foreground "#c82822")))
 '(org-level-3 ((t :foreground "#c82823")))
 '(org-level-4 ((t :foreground "#c82824")))
 '(org-level-5 ((t :foreground "#c82825")))
 '(org-level-6 ((t :foreground "#c82826")))
 '(outline-1 ((t :foreground "#f58711")))
 '(outline-2 ((t :foreground "#f58712")))
 '(outline-3 ((t :foreground "#f58713")))
 '(outline-4 ((t :foreground "#f58714")))
 '(outline-5 ((t :foreground "#f58715")))
 '(outline-6 ((t :foreground "#f58716"))))

(provide 'imprimeur-test-themes)

;;; imprimeur-test-themes.el ends here

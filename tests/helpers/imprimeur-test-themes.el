;;; imprimeur-test-themes.el --- Themes for the tests of the palette  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; A night, a day, a mono and a no-button theme, defined but not enabled.
;; The night theme writes its colours in each form a theme may use: a 16-bit spec,
;; a short spec, a name in mixed case; it leaves `link' unspecified and
;; gives `org-link' and `button', after it in the chain of links, colours
;; of their own; `font-lock-doc-face' inherits the string
;; colour, weight and slant, `org-level-1' the function name colour
;; through `outline-1'; `region' and `font-lock-warning-face' are in
;; inverse video, which `font-lock-builtin-face' inherits.  The day
;; theme gives each face of the chains of links, headings and code panes
;; a colour of its own, so that the first face of a chain that exists is
;; seen to win; the faces of markdown-mode exist only where a test defines
;; them.
;; The mono theme gives the default face a family, which no machine is
;; expected to have, and nothing else: on a text terminal, as in batch
;; Emacs, a theme enabled after it that sets the default face's colours
;; leaves the family "default", so mono is enabled last.  The no-button
;; theme, enabled after the night theme, leaves `button' unspecified too.

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
 '(markdown-link-face ((t :foreground "#7f5f3a")))
 '(markdown-header-face-1 ((t :foreground "#2f6b11")))
 '(markdown-header-face-2 ((t :foreground "#2f6b12")))
 '(markdown-header-face-3 ((t :foreground "#2f6b13")))
 '(markdown-header-face-4 ((t :foreground "#2f6b14")))
 '(markdown-header-face-5 ((t :foreground "#2f6b15")))
 '(markdown-header-face-6 ((t :foreground "#2f6b16")))
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
 '(outline-6 ((t :foreground "#f58716")))
 '(org-block ((t :background "#f0f0e1")))
 '(markdown-code-face ((t :background "#f0f0e2"))))

(deftheme imprimeur-test-mono "A family for the default face, for the tests of imprimeur.")

(custom-theme-set-faces
 'imprimeur-test-mono
 '(default ((t :family "Imprimeur Test Mono"))))

(deftheme imprimeur-test-no-button "A button of no colour, for the tests of imprimeur.")

(custom-theme-set-faces
 'imprimeur-test-no-button
 '(button ((t :foreground unspecified))))

(provide 'imprimeur-test-themes)

;;; imprimeur-test-themes.el ends here

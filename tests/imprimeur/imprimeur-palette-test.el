;;; imprimeur-palette-test.el --- Tests of the page's palette  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 003, acceptance 1, and its decisions "Palette in
;; Emacs" and "CSS custom properties"): on a non-graphic frame, a test
;; theme's #00c000c000c0 gives #010101, #abc #aabbcc, gray50 #7f7f7f, an
;; unspecified link the org-link colour; inheritance and inverse video are
;; honoured, inheritance for colours, weights, slants and inverse video
;; alike; every colour matches ^#[0-9a-f]{6}$, with or without Org
;; loaded.  A colour is a spec first, then a name that a graphic frame's
;; display resolves, or else a standard name in any case; 16-bit channels
;; are rounded to 8.  A property's faces are tried in order until one
;; that exists gives a value: for links `org-link', `markdown-link-face',
;; `link', `button'; for headings `org-level-N',
;; `markdown-header-face-N', `outline-N'; for the background of code
;; panes `org-block', `markdown-code-face'.  They are read on a graphic
;; frame showing the buffer, whatever else shows it, and on the selected
;; frame for a buffer that no Emacs window shows, even a dead one.
;; The properties sit on :root, with no colour scheme, which the page
;; takes from the appearance; one whose face gives nothing is left out; a
;; token has a weight and a style; a font family is kept, quoted, only
;; when it holds letters, digits, spaces, dots, hyphens and underscores,
;; and the family "default" of a text terminal is no font.
;; `imprimeur-appearance' overrides the frame's background mode.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'repo-test-helpers)
(require 'imprimeur-test-themes)
(require 'imprimeur-palette)

(ert-deftest imprimeur-palette-color-decides ()
  (dolist (case '(("#00c000c000c0" "#010101") ("#abc" "#aabbcc") ("#ABCDEF" "#abcdef")
                  ("#ffffffffffff" "#ffffff") ("rgb:f/8/0" "#ff8800") ("gray50" "#7f7f7f")
                  ("Gray50" "#7f7f7f") ("unspecified-fg" nil) ("no such colour" nil) ("" nil)
                  (unspecified nil) (reset nil) (nil nil)))
    (should (equal (list (car case) (imprimeur-palette-color (car case) nil)) case))))

(ert-deftest imprimeur-palette-color-asks-a-graphic-display-for-names ()
  (let ((frame (selected-frame)))
    (cl-letf (((symbol-function 'color-values)
               (lambda (name &optional display)
                 (and (equal name "MidnightBlue") (eq display frame) '(257 514 771)))))
      (should (equal (imprimeur-palette-color "MidnightBlue" frame) "#010203"))
      (should (equal (imprimeur-palette-color "#abc" frame) "#aabbcc"))
      (should-not (imprimeur-palette-color "gray50" frame)))))

(defun imprimeur-palette-test-properties (css)
  "Return the declarations of CSS, a :root rule, as (NAME . VALUE) pairs."
  (should (string-match "\\`:root {\n\\(\\(?:  [^\n]*\n\\)*\\)}\n\\'" css))
  (mapcar (lambda (line)
            (should (string-match "\\`  \\([-a-z0-9]+\\): \\(.*\\);\\'" line))
            (cons (match-string 1 line) (match-string 2 line)))
          (split-string (match-string 1 css) "\n" t)))

(ert-deftest imprimeur-palette-css-decides ()
  (dolist (case
           '(((("kw" :color "#aabbcc" :weight semi-bold :slant italic))
              (("--emacs-kw" . "#aabbcc") ("--emacs-kw-weight" . "600") ("--emacs-kw-style" . "italic")))
             ((("bg" :color nil) ("a" :weight unspecified :slant unspecified)
               ("b" :weight reset :slant reset) ("c"))
              ())
             ((("a" :weight thin) ("b" :weight semibold) ("c" :weight demi) ("d" :weight normal)
               ("e" :weight book) ("f" :weight bold) ("g" :weight ultra-bold) ("h" :weight heavy)
               ("i" :weight ultra-heavy) ("j" :weight light))
              (("--emacs-a-weight" . "100") ("--emacs-b-weight" . "600")
               ("--emacs-c-weight" . "600") ("--emacs-d-weight" . "400") ("--emacs-e-weight" . "400")
               ("--emacs-f-weight" . "700") ("--emacs-g-weight" . "800") ("--emacs-h-weight" . "900")
               ("--emacs-i-weight" . "950") ("--emacs-j-weight" . "300")))
             ((("a" :slant i) ("b" :slant oblique) ("c" :slant reverse-italic) ("d" :slant normal))
              (("--emacs-a-style" . "italic") ("--emacs-b-style" . "oblique")
               ("--emacs-c-style" . "italic") ("--emacs-d-style" . "normal")))
             ((("font-mono" :family "Iosevka Term") ("a" :family "Fira_Code-1.2")
               ("b" :family "Écran") ("c" :family "default") ("d" :family "Evil\"; } body { x: y")
               ("e" :family "a;b") ("f" :family "") ("g" :family unspecified)
               ;; Without a semicolon, a family can still close the value and the rule.
               ("h" :family "X\" } body { background: url(http://203.0.113.1/) } :root { --y: \"")
               ("i" :family "a\"b") ("j" :family "a}b") ("k" :family "a\\b") ("l" :family "a\nb")
               ("m" :family "a/*b*/"))
              (("--emacs-font-mono" . "\"Iosevka Term\"")
               ("--emacs-a" . "\"Fira_Code-1.2\"") ("--emacs-b" . "\"Écran\"")))))
    (pcase-let ((`(,faces ,properties) case))
      (should (equal (list faces (imprimeur-palette-test-properties (imprimeur-palette-css faces)))
                     (list faces properties))))))

(defconst imprimeur-palette-test-night
  '(("--emacs-bg" . "#1d1f21") ("--emacs-fg" . "#c5c8c6") ("--emacs-muted" . "#010101")
    ("--emacs-region" . "#373b41") ("--emacs-kw" . "#aabbcc") ("--emacs-kw-weight" . "600")
    ("--emacs-kw-style" . "italic") ("--emacs-str" . "#b5bd68") ("--emacs-str-weight" . "300")
    ("--emacs-str-style" . "oblique") ("--emacs-com" . "#7f7f7f") ("--emacs-fn" . "#81a2be")
    ("--emacs-doc" . "#b5bd68") ("--emacs-doc-weight" . "300") ("--emacs-doc-style" . "oblique")
    ("--emacs-warn" . "#cc6666") ("--emacs-builtin" . "#cc6666"))
  "What the night theme gives, with or without Org.")

(defun imprimeur-palette-test-check (palette)
  "Check that every colour of PALETTE is #rrggbb; return its properties."
  (let ((properties (imprimeur-palette-test-properties (plist-get palette :css))))
    (dolist (property properties)
      (unless (string-match-p "\\`\\(?:.*-weight\\|.*-style\\|--emacs-font-.*\\)\\'"
                              (car property))
        (should (equal (list property (string-match-p "\\`#[0-9a-f]\\{6\\}\\'" (cdr property)))
                       (list property 0)))))
    properties))

(ert-deftest imprimeur-palette-reads-the-theme-with-org ()
  (require 'org)
  (should-not (display-graphic-p))
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (with-temp-buffer
        (let ((properties (imprimeur-palette-test-check (imprimeur-palette (current-buffer)))))
          (dolist (property imprimeur-palette-test-night)
            (should (equal (assoc (car property) properties) property)))
          (should (equal (assoc "--emacs-link" properties) '("--emacs-link" . "#8abeb7")))
          (should (equal (assoc "--emacs-h1" properties) '("--emacs-h1" . "#81a2be")))
          (should-not (assoc "--emacs-font-mono" properties))
          ;; `org-block' inherits `shadow', which gives no background.
          (should-not (assoc "--emacs-code-bg" properties)))
        (should (equal (plist-get (imprimeur-palette (current-buffer)) :appearance) "dark"))
        (let ((imprimeur-appearance 'light))
          (should (equal (plist-get (imprimeur-palette (current-buffer)) :appearance) "light"))))
    (disable-theme 'imprimeur-test-night)))

(defun imprimeur-palette-test-chains (link heading)
  "Return the properties of links and headings that the day theme gives.
LINK is the link colour; HEADING, followed by a level's digit, that
level's colour."
  (cons (cons "--emacs-link" link)
        (mapcar (lambda (level) (cons (format "--emacs-h%d" level) (format "%s%d" heading level)))
                (number-sequence 1 6))))

(ert-deftest imprimeur-palette-tries-the-faces-of-a-chain-in-order ()
  (require 'org)
  (enable-theme 'imprimeur-test-day)
  (unwind-protect
      (with-temp-buffer
        (let ((properties (imprimeur-palette-test-check (imprimeur-palette (current-buffer))))
              (chains (imprimeur-palette-test-chains "#3e999f" "#c8282")))
          (should (equal (mapcar (lambda (property) (assoc (car property) properties)) chains)
                         chains))))
    (disable-theme 'imprimeur-test-day)))

(ert-deftest imprimeur-palette-reads-the-theme-without-org ()
  (let ((child (repo-test-emacs
                (list "-L" (expand-file-name "imprimeur" repo-test-root)
                      "-L" (expand-file-name "tests/helpers" repo-test-root)
                      "-l" "imprimeur-palette" "-l" "imprimeur-test-themes" "-l" "outline" "--eval"
                      (concat "(progn (enable-theme 'imprimeur-test-night)"
                              " (let ((night (imprimeur-palette (current-buffer))))"
                              " (disable-theme 'imprimeur-test-night)"
                              " (enable-theme 'imprimeur-test-day)"
                              " (prin1 (list (featurep 'org) (display-graphic-p)"
                              " night (imprimeur-palette (current-buffer))))))")))))
    (should (equal (car child) 0))
    (pcase-let ((`(,org ,graphic ,night ,day) (car (read-from-string (cdr child)))))
      (should-not org)
      (should-not graphic)
      (let ((properties (imprimeur-palette-test-check night)))
        (dolist (property imprimeur-palette-test-night)
          (should (equal (assoc (car property) properties) property)))
        ;; Without Org nor Markdown, `link' exists but gives nothing.
        (should (equal (assoc "--emacs-link" properties) '("--emacs-link" . "#de935f"))))
      ;; Without Org nor Markdown, the chains fall to `link' and `outline-N'.
      (let ((properties (imprimeur-palette-test-check day))
            (chains (imprimeur-palette-test-chains "#4271ae" "#f5871")))
        (should (equal (mapcar (lambda (property) (assoc (car property) properties)) chains)
                       chains))))))

(ert-deftest imprimeur-palette-reads-code-panes-from-org-then-markdown ()
  ;; markdown-mode is not at hand: a face of its name stands in for it,
  ;; defined, as Org's are, after the day theme is enabled.
  (let ((child (repo-test-emacs
                (list "-L" (expand-file-name "imprimeur" repo-test-root)
                      "-L" (expand-file-name "tests/helpers" repo-test-root)
                      "-l" "imprimeur-palette" "-l" "imprimeur-test-themes" "--eval"
                      (concat "(progn (enable-theme 'imprimeur-test-day)"
                              " (let ((faces (list (facep 'org-block) (facep 'markdown-code-face)))"
                              " (neither (imprimeur-palette (current-buffer))))"
                              " (defface markdown-code-face nil \"A stand-in.\")"
                              " (let ((markdown (imprimeur-palette (current-buffer))))"
                              " (require 'org)"
                              " (prin1 (list faces neither markdown"
                              " (imprimeur-palette (current-buffer)))))))")))))
    (should (equal (car child) 0))
    (pcase-let ((`(,faces . ,palettes) (car (read-from-string (cdr child)))))
      (should (equal faces '(nil nil)))
      (should (equal (mapcar (lambda (palette)
                               (assoc "--emacs-code-bg" (imprimeur-palette-test-check palette)))
                             palettes)
                     '(nil ("--emacs-code-bg" . "#f0f0e2") ("--emacs-code-bg" . "#f0f0e1")))))))

(ert-deftest imprimeur-palette-reads-the-graphic-frame-showing-the-buffer ()
  ;; Batch Emacs has no graphic frame, so one stands in for it, beside a text
  ;; frame that shows the buffer too and the selected frame that does not.
  (let ((asked nil)
        (read (symbol-function 'face-attribute)))
    (with-temp-buffer
      (cl-letf (((symbol-function 'get-buffer-window-list) (lambda (&rest _) '(on-text on-graphic)))
                ((symbol-function 'window-frame)
                 (lambda (window) (if (eq window 'on-text) 'text-frame 'graphic-frame)))
                ((symbol-function 'display-graphic-p) (lambda (frame) (eq frame 'graphic-frame)))
                ((symbol-function 'face-attribute)
                 (lambda (face attribute &optional frame inherit)
                   ;; The inheritance of a face calls this again with no frame.
                   (when frame (push frame asked))
                   (funcall read face attribute nil inherit)))
                ((symbol-function 'color-values)
                 (lambda (_color &optional frame) (push frame asked) nil))
                ((symbol-function 'frame-parameter)
                 (lambda (frame _parameter) (push frame asked) 'dark)))
        (should (equal (plist-get (imprimeur-palette (current-buffer)) :appearance) "dark"))))
    (should (equal (delete-dups asked) '(graphic-frame)))))

(ert-deftest imprimeur-palette-reads-the-selected-frame-for-a-buffer-not-shown ()
  (let ((dead (generate-new-buffer "imprimeur-palette-test")))
    (kill-buffer dead)
    (enable-theme 'imprimeur-test-night)
    (unwind-protect
        (should (equal (imprimeur-palette dead)
                       (with-temp-buffer (imprimeur-palette (current-buffer)))))
      (disable-theme 'imprimeur-test-night))))

;;; imprimeur-palette-test.el ends here

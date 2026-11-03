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
;;
;; The umbrella plan's "headings from the mode's faces": that order is the
;; one of a buffer whose major mode derives from `org-mode'.  In any other
;; buffer, or a dead one, a face named org-* comes last and the others keep
;; their order, so that a Markdown buffer reads `markdown-header-face-N',
;; `outline-N', `org-level-N', whether or not Org is loaded.  An unspecified
;; link therefore takes the org-link colour first in an Org buffer, and in
;; any other once no face before it gives one, as `button' may.  Without
;; Org loaded there is no org-link colour to take.
;;
;; The properties sit on :root, with no colour scheme, which the page
;; takes from the appearance; one whose face gives nothing is left out; a
;; token has a weight and a style; a font family is kept, quoted, only
;; when it holds letters, digits, spaces, dots, hyphens and underscores,
;; and the family "default" of a text terminal is no font.
;; `imprimeur-appearance' overrides the frame's background mode.
;;
;; Plan 008, "A switch can send two palettes", with acceptance 5: a switch made
;; while events spin inside `enable-theme', in a variable's `:set' or in a later
;; function of `enable-theme-functions', gives the watchers one palette, read
;; once the hooks have finished the faces, so holding the comment's weight and
;; slant that one of them sets.
;;
;; Plan 008, "Inverse video": Emacs paints such a face's text in its background on
;; a block of its foreground, where a colour that the face leaves out is that of
;; `default'.  The palette says what it paints, except that a page has no block,
;; so text in the page's own background takes the block's colour: a face with a
;; foreground alone gives that colour and not the next face's, and one inheriting
;; `isearch', whose background is the theme's own, gives a colour that shows.

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
        (org-mode)
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

(ert-deftest imprimeur-palette-takes-a-link-from-org-link-last-outside-org ()
  (require 'org)
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (with-temp-buffer
        (let ((link (lambda ()
                      (assoc "--emacs-link"
                             (imprimeur-palette-test-check (imprimeur-palette (current-buffer)))))))
          ;; `button' comes before `org-link' here, and `link' gives nothing.
          (should (equal (funcall link) '("--emacs-link" . "#de935f")))
          (enable-theme 'imprimeur-test-no-button)
          (should (equal (funcall link) '("--emacs-link" . "#8abeb7")))))
    (mapc #'disable-theme '(imprimeur-test-no-button imprimeur-test-night))))

(defun imprimeur-palette-test-should-read (palette link heading)
  "Check the colours of links and headings in PALETTE.
LINK is the link colour; HEADING, followed by a level's digit, that
level's colour."
  (let ((properties (imprimeur-palette-test-check palette))
        (chains (cons (cons "--emacs-link" link)
                      (mapcar (lambda (level)
                                (cons (format "--emacs-h%d" level) (format "%s%d" heading level)))
                              (number-sequence 1 6)))))
    (should (equal (mapcar (lambda (property) (assoc (car property) properties)) chains)
                   chains))))

(ert-deftest imprimeur-palette-tries-the-faces-of-a-chain-in-order ()
  (require 'org)
  (enable-theme 'imprimeur-test-day)
  (unwind-protect
      (progn
        ;; An Org buffer reads Org's faces first.
        (with-temp-buffer
          (org-mode)
          (imprimeur-palette-test-should-read (imprimeur-palette (current-buffer)) "#3e999f" "#c8282"))
        ;; Any other reads them last: Markdown's being no faces here, `link' and
        ;; `outline-N' come first, and code panes have only `org-block' to read.
        (with-temp-buffer
          (let ((palette (imprimeur-palette (current-buffer))))
            (imprimeur-palette-test-should-read palette "#4271ae" "#f5871")
            (should (equal (assoc "--emacs-code-bg" (imprimeur-palette-test-check palette))
                           '("--emacs-code-bg" . "#f0f0e1"))))))
    (disable-theme 'imprimeur-test-day)))

(ert-deftest imprimeur-palette-reads-the-faces-of-the-buffer-s-mode ()
  ;; markdown-mode is not at hand: a mode derived from text-mode stands for
  ;; it, and faces of its names, defined, as Org's are, after the day theme
  ;; is enabled.  What decides is whether a real mode derives from `org-mode'.
  (let ((child (repo-test-emacs
                (list "-L" (expand-file-name "imprimeur" repo-test-root)
                      "-L" (expand-file-name "tests/helpers" repo-test-root)
                      "-l" "imprimeur-palette" "-l" "imprimeur-test-themes" "--eval"
                      (concat "(progn (enable-theme 'imprimeur-test-day) (require 'org)"
                              " (custom-declare-face 'markdown-link-face nil \"A stand-in.\")"
                              " (dolist (level '(1 2 3 4 5 6))"
                              " (custom-declare-face (intern (format \"markdown-header-face-%d\" level))"
                              " nil \"A stand-in.\"))"
                              " (define-derived-mode stand-in-markdown-mode text-mode \"Markdown\")"
                              " (define-derived-mode stand-in-org-mode org-mode \"Org\")"
                              " (let ((dead (generate-new-buffer \"dead\")))"
                              " (kill-buffer dead)"
                              " (prin1 (append (list (imprimeur-palette dead))"
                              " (mapcar (lambda (mode)"
                              " (with-temp-buffer (funcall mode) (imprimeur-palette (current-buffer))))"
                              " '(stand-in-markdown-mode fundamental-mode org-mode stand-in-org-mode))"
                              ;; The theme's timer runs with any buffer current.
                              " (let ((in-org (generate-new-buffer \"org\"))"
                              " (in-text (generate-new-buffer \"text\")))"
                              " (with-current-buffer in-org (org-mode))"
                              " (with-current-buffer in-text (stand-in-markdown-mode))"
                              " (list (with-current-buffer in-text (imprimeur-palette in-org))"
                              " (with-current-buffer in-org (imprimeur-palette in-text))))))))")))))
    (should (equal (car child) 0))
    (pcase-let ((`(,dead ,markdown ,other ,org ,derived ,org-elsewhere ,text-elsewhere)
                 (car (read-from-string (cdr child)))))
      (imprimeur-palette-test-should-read org-elsewhere "#3e999f" "#c8282")
      (imprimeur-palette-test-should-read text-elsewhere "#7f5f3a" "#2f6b1")
      (imprimeur-palette-test-should-read markdown "#7f5f3a" "#2f6b1")
      (imprimeur-palette-test-should-read other "#7f5f3a" "#2f6b1")
      (imprimeur-palette-test-should-read dead "#7f5f3a" "#2f6b1")
      (imprimeur-palette-test-should-read org "#3e999f" "#c8282")
      (imprimeur-palette-test-should-read derived "#3e999f" "#c8282"))))

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
      (imprimeur-palette-test-should-read day "#4271ae" "#f5871"))))

(ert-deftest imprimeur-palette-reads-code-panes-by-the-buffer-s-mode ()
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
                              " (imprimeur-palette (current-buffer))"
                              " (with-temp-buffer (org-mode) (imprimeur-palette (current-buffer))))))))")))))
    (should (equal (car child) 0))
    (pcase-let ((`(,faces . ,palettes) (car (read-from-string (cdr child)))))
      (should (equal faces '(nil nil)))
      (should (equal (mapcar (lambda (palette)
                               (assoc "--emacs-code-bg" (imprimeur-palette-test-check palette)))
                             palettes)
                     ;; With both faces, `org-block' comes first only in an Org buffer.
                     '(nil ("--emacs-code-bg" . "#f0f0e2") ("--emacs-code-bg" . "#f0f0e2")
                           ("--emacs-code-bg" . "#f0f0e1")))))))

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

(ert-deftest imprimeur-palette-inverse-decides ()
  (pcase-dolist (`(,attribute ,foreground ,background ,page ,shown)
                 '((:foreground "#111111" "#eeeeee" "#1d1f21" "#eeeeee")
                   (:background "#111111" "#eeeeee" "#1d1f21" "#111111")
                   ;; No block on a page for text in its own background.
                   (:foreground "#ff0000" "#1d1f21" "#1d1f21" "#ff0000")
                   (:background "#ff0000" "#1d1f21" "#1d1f21" "#ff0000")
                   ;; A text terminal's `default' names no colour.
                   (:foreground "#ff0000" nil nil "#ff0000")
                   (:foreground nil "#00ff00" nil "#00ff00")
                   (:background nil "#00ff00" nil nil)))
    (should (equal (list attribute foreground background page
                         (imprimeur-palette--inverse attribute foreground background page))
                   (list attribute foreground background page shown)))))

(ert-deftest imprimeur-palette-shows-inverse-video-as-emacs-paints-it ()
  ;; A child Emacs, as these faces would outlive the test: the night theme gives
  ;; `default' #c5c8c6 on #1d1f21, and `button', the next face of the chain, #de935f.
  (let* ((forms '(;; Both colours.
                  (set-face-attribute 'link nil :foreground "#111111" :background "#eeeeee"
                                      :inverse-video t)
                  ;; A background alone: text in it, on a block of `default''s foreground.
                  (set-face-attribute 'link nil :foreground 'unspecified :background "#00ff00")
                  ;; A foreground alone: a block of it, which Emacs paints.
                  (set-face-attribute 'link nil :foreground "#ff0000" :background 'unspecified)
                  ;; Neither: a block of `default''s foreground.
                  (set-face-attribute 'link nil :foreground 'unspecified)
                  ;; `isearch', as a theme writes it: the text is the page's own background.
                  (progn
                    (set-face-attribute 'isearch nil :foreground "#f0c674" :background "#1d1f21"
                                        :inverse-video t)
                    (set-face-attribute 'link nil :inherit 'isearch :inverse-video 'unspecified))))
         (child (repo-test-emacs
                 (list "-L" (expand-file-name "imprimeur" repo-test-root)
                       "-L" (expand-file-name "tests/helpers" repo-test-root)
                       "-l" "imprimeur-palette" "-l" "imprimeur-test-themes" "--eval"
                       (prin1-to-string
                        `(progn
                           (enable-theme 'imprimeur-test-night)
                           (prin1 (mapcar (lambda (form)
                                            (eval form t)
                                            (imprimeur-palette (current-buffer)))
                                          ',forms))))))))
    (should (equal (car child) 0))
    (should (equal (mapcar (lambda (palette)
                             (cdr (assoc "--emacs-link" (imprimeur-palette-test-check palette))))
                           (car (read-from-string (cdr child))))
                   '("#eeeeee" "#00ff00" "#ff0000" "#c5c8c6" "#f0c674")))))

(ert-deftest imprimeur-palette-shows-a-block-from-the-default-face ()
  ;; A region in inverse video with a background alone is a block of `default''s
  ;; foreground, and a `default' in inverse video shows each colour as the other.
  (let ((child (repo-test-emacs
                (list "-L" (expand-file-name "imprimeur" repo-test-root)
                      "-L" (expand-file-name "tests/helpers" repo-test-root)
                      "-l" "imprimeur-palette" "-l" "imprimeur-test-themes" "--eval"
                      (prin1-to-string
                       '(progn
                          (enable-theme 'imprimeur-test-night)
                          (set-face-attribute 'region nil :foreground 'unspecified :background "#123456"
                                              :inverse-video t)
                          (let ((region (imprimeur-palette (current-buffer))))
                            (set-face-attribute 'default nil :inverse-video t)
                            (prin1 (list region (imprimeur-palette (current-buffer))))))))))
        (value (lambda (name palette)
                 (cdr (assoc name (imprimeur-palette-test-check palette))))))
    (should (equal (car child) 0))
    (pcase-let ((`(,region ,reversed) (car (read-from-string (cdr child)))))
      (should (equal (funcall value "--emacs-region" region) "#c5c8c6"))
      (should (equal (mapcar (lambda (name) (funcall value name reversed))
                             '("--emacs-bg" "--emacs-fg"))
                     '("#c5c8c6" "#1d1f21"))))))

(defconst imprimeur-palette-test-spin
  '(dotimes (_ 20) (accept-process-output nil 0.01))
  "A stand-in for a D-Bus call: it spins events for longer than the timer waits.
Each turn runs the timers that are due, whatever the machine's load.")

(defun imprimeur-palette-test-switch (form)
  "Return the palettes that the watchers get from a switch of theme.
A child Emacs goes from the day theme to the night theme, which names the
comment's face.  A function of `enable-theme-functions' then sets that face's
weight and slant, as a reader's configuration may, and comes last, after what
FORM adds to that hook; FORM also runs what the switch needs to spin events."
  (let ((child (repo-test-emacs
                (list "-L" (expand-file-name "imprimeur" repo-test-root)
                      "-L" (expand-file-name "tests/helpers" repo-test-root)
                      "-l" "imprimeur-palette" "-l" "imprimeur-test-themes" "--eval"
                      (prin1-to-string
                       `(let ((palettes nil))
                          (enable-theme 'imprimeur-test-day)
                          (add-hook 'enable-theme-functions
                                    (lambda (_theme)
                                      (set-face-attribute 'font-lock-comment-face nil
                                                          :weight 'light :slant 'italic)))
                          ,form
                          (imprimeur-palette-watch
                           (lambda () (push (imprimeur-palette (current-buffer)) palettes)))
                          (disable-theme 'imprimeur-test-day)
                          (enable-theme 'imprimeur-test-night)
                          ,imprimeur-palette-test-spin
                          (prin1 palettes)))))))
    (should (equal (car child) 0))
    (car (read-from-string (cdr child)))))

(ert-deftest imprimeur-palette-reads-the-faces-after-enable-theme-has-ended ()
  (pcase-dolist (`(,where ,form)
                 `(("a variable's :set, as a theme's user option may"
                    (progn
                      (defcustom imprimeur-palette-test-option nil
                        "A stand-in for an option whose `:set' spins events."
                        :type 'boolean :group 'imprimeur
                        :set (lambda (symbol value)
                               (set-default-toplevel-value symbol value)
                               ,imprimeur-palette-test-spin))
                      (customize-set-variable 'imprimeur-palette-test-option t)))
                   ;; Added here, it runs after the watcher's function, whose timer it then
                   ;; lets run, and before the function that finishes the faces.
                   ("a function of the hook"
                    (add-hook 'enable-theme-functions
                              (lambda (_theme) ,imprimeur-palette-test-spin)))))
    (ert-info (where)
      (let ((palettes (imprimeur-palette-test-switch form)))
        (should (equal (length palettes) 1))
        (let ((properties (imprimeur-palette-test-check (car palettes))))
          (should (equal (assoc "--emacs-bg" properties) '("--emacs-bg" . "#1d1f21")))
          (should (equal (assoc "--emacs-com-weight" properties) '("--emacs-com-weight" . "300")))
          (should (equal (assoc "--emacs-com-style" properties) '("--emacs-com-style" . "italic"))))))))

;;; imprimeur-palette-test.el ends here

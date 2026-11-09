;;; imprimeur-skin-dubai-test.el --- Tests of the skin Dubai  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 051:
;;
;; "An Arabic business memo, Briefing's sibling": the manifest's options, by hand from the
;; plan's table: accent (teal by default, blue, aubergine, graphite), density (compact by
;; default, regular, airy), skim (off), face (kufi by default, plex), hijri (off); the menu
;; key d.  Acceptance 3: the menu shows it under d, with its five options at their defaults.
;;
;; Acceptance 5: on real pandoc, ١٬٢٥٠٫٥, AED 1,250.00, 1,250 د.إ and ١٢٪ are quantities, and
;; dates are not, in either digits; Briefing's English cases still hold.  The filter is
;; Briefing's otherwise, with Arabic words under ar: the bottom line from الخلاصة or الملخص
;; التنفيذي, callouts قرار, طلب, مخاطرة and ملاحظة, chips over action titles whose keywords
;; stay ASCII in the source, a row named الإجمالي a total, a strong phrase with a figure in
;; the bottom line that begins with a quantity a key figure, the masthead's date in CLDR's ar-AE month names and in the
;; digits it was typed in, and never U+FDFC.
;;
;; Acceptance 4: labels and chips have letter-spacing 0 and no capitals under :lang(ar).
;; Acceptance 6: with hijri on, 22 October 2024, the date of Dubai's Law No. 23 of 2024, which
;; the law itself gives as 19 Rabi' al-Akhir 1446, shows day 19, month 4, year 1446 of
;; islamic-umalqura, compared through formatToParts; WebKit's is the smoke test's.
;;
;; Acceptance 2: fonts.nix fetches each Google font whole, by hash at the revision of
;; nixpkgs's google-fonts, with its licence, and cuts it with XIX's make-cut.py into the
;; families that the sheet's local() names; the README credits each face's designers; the
;; sheet serves no font, by url(); no font file is tracked.  The palette passes Briefing's
;; rules, as its sheet states them: each accent at least 4.5:1 on the ground and on its own
;; tint, and at least 25 (CIE76) from each status colour; each status at least 4.5:1 on its
;; chip's tint.  The README says the skin has no relation to the Government of Dubai and
;; does not use Dubai Font.
;;
;; The page, by the plan's verification: in Chromium, at 640 and 420 CSS px, dir=rtl on the
;; root, code and maths left to right, the minitoc's pill at the inline end, no sideways
;; scroll; each option changes what it says, alone.  The samples quote the laws as SOURCES.md
;; says, and the Arabic showcase is the English one's structure.
;;
;; The tests register Dubai in a registry of their own, as the other tests see the plain page
;; alone.  make check's fonts are DejaVu at most, so a page test reads computed values and
;; boxes, never a face drawn.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'color)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-dubai-test-file
  (expand-file-name "imprimeur-skin-dubai/imprimeur-skin-dubai.el" repo-test-root)
  "The skin's main file.")

(defun imprimeur-skin-dubai-test-read (file)
  "Return the text of FILE, under the repository's root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file repo-test-root))
    (buffer-string)))

(defun imprimeur-skin-dubai-test-html (reader text)
  "Return the HTML that Dubai's chain writes from TEXT in READER, on real pandoc."
  (let ((pandoc (imprimeur-test-require "pandoc"))
        (imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-dubai-test-file nil t)
    (with-temp-buffer
      (insert text)
      (should (equal (apply #'call-process-region (point-min) (point-max) pandoc t t nil
                            (imprimeur-render-arguments reader nil nil "python,bash"
                                                        (imprimeur-skin-get "dubai")))
                     0))
      (buffer-string))))

(defun imprimeur-skin-dubai-test-doc (lang body)
  "Return a Markdown document in LANG, whose title is T, holding BODY, as HTML."
  (imprimeur-skin-dubai-test-html "gfm+sourcepos" (format "---\ntitle: T\nlang: %s\n---\n\n%s\n" lang body)))

(defun imprimeur-skin-dubai-test-right-columns (html)
  "Return how many cells of HTML's first table's first row of data stand on the right."
  (string-match "<tbody>\\(\\(?:.\\|\n\\)*?\\)</tr>" html)
  (let ((row (match-string 1 html)) (start 0) (count 0))
    (while (string-match "<td[^>]*text-align: right" row start)
      (setq start (match-end 0) count (1+ count)))
    count))

(defun imprimeur-skin-dubai-test-count (regexp string)
  "Return how many matches of REGEXP STRING holds."
  (let ((start 0) (count 0))
    (while (string-match regexp string start)
      (setq start (match-end 0) count (1+ count)))
    count))

(defmacro imprimeur-skin-dubai-test-with (spec &rest body)
  "Run BODY with Dubai as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in the
selected Emacs window, in `imprimeur-mode'; BROWSER shows its page, at 640 by 900."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'dubai)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (progn
                         ;; The showcase's woodcut, at the path that it names from its own place.
                         (make-directory (expand-file-name "docs/images" root) t)
                         (copy-file (expand-file-name "docs/images/printer-1568.png" repo-test-root)
                                    (expand-file-name "docs/images/" root))
                         (find-file-noselect (expand-file-name ,file root)))))
         (load imprimeur-skin-dubai-test-file nil t)
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-mode 1)
                 (imprimeur-skin-dubai-test-viewport ,browser 640 900)
                 (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
                 (imprimeur-test-wait-for
                  (lambda () (imprimeur-test-cdp-eval ,browser "document.documentElement.dataset.revision")))
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-skin-dubai-test-viewport (browser width height)
  "Give BROWSER's page a viewport of WIDTH by HEIGHT CSS px, and let it lay out."
  (imprimeur-test-cdp-call browser "Emulation.setDeviceMetricsOverride"
                           `(:width ,width :height ,height :deviceScaleFactor 1 :mobile :false))
  (imprimeur-test-cdp-wait browser (format "window.innerWidth === %d && window.innerHeight === %d" width height))
  (accept-process-output nil 0.1))

(defun imprimeur-skin-dubai-test-style (browser selector property)
  "Return the computed PROPERTY of SELECTOR in BROWSER's page."
  (imprimeur-test-cdp-eval
   browser (format "getComputedStyle(document.querySelector(%S))[%S]" selector property)))

(defun imprimeur-skin-dubai-test-attributes (browser)
  "Return the names of the data-dubai attributes on the root of BROWSER's page."
  (append (imprimeur-test-cdp-eval
           browser "[...document.documentElement.attributes].map((a) => a.name).filter((n) => n.startsWith('data-dubai'))")
          nil))

(defun imprimeur-skin-dubai-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-dubai-%s') === %s"
                   id (if (equal value (plist-get (cdr (assq (intern id) (plist-get (imprimeur-skin-get "dubai") :options)))
                                                  :default))
                          "null"
                        (format "%S" value)))))

(defun imprimeur-skin-dubai-test-replace (buffer browser text ready)
  "Replace BUFFER's text by TEXT, and wait until READY, JavaScript, is true in BROWSER."
  (with-current-buffer buffer
    (erase-buffer)
    (insert text))
  (imprimeur-test-cdp-wait browser ready 20))

(defconst imprimeur-skin-dubai-test-memo
  (concat "---\ntitle: قرار\nsubtitle: مذكرة\nauthor: فلان\ndate: 2024-10-22\nstatus: للقرار\nlang: ar\n---\n\n"
          "# الخلاصة\n\nالجواب أولاً، بنفقات **272 مليار درهم**.\n\n> [!IMPORTANT]\n> **قرار:** نعتمد.\n\n"
          "# المتن\n\nفقرة فيها [رابط](https://example.invalid/).\n\nفقرة أخرى.\n\n"
          "## TODO: [#A] إجراء :مالية:\n\nDEADLINE: 2026-11-02, OWNER: فلان\n\nنصه.\n\n"
          "#### أدنى\n\n| البند | المبلغ |\n|---|---|\n| أ | ١٬٢٥٠ |\n| الإجمالي | ٢٬٥٠٠ |\n")
  "An Arabic memo in GitHub Markdown, with all that the skim view keeps and hides.")

(defconst imprimeur-skin-dubai-test-body
  "[...document.querySelectorAll('#imprimeur-main p')].find((p) => p.textContent.includes('فقرة أخرى')).parentElement"
  "A top-level block of the body of the memo above, the wrapper of a paragraph.")

;;;; The package

(ert-deftest imprimeur-skin-dubai-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-dubai-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-dubai-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-dubai)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S\" (and (imprimeur-skin-get \"dubai\") t)))"))))
    (should (equal (car result) 0))
    (should (string-match-p "MARK\\(.\\|\n\\)*before=nil after=t\\'" (cdr result)))))

(ert-deftest imprimeur-skin-dubai-keeps-the-plan-s-defaults-and-choices ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-dubai-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "dubai"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "Dubai"))
      (should (equal (plist-get manifest :menu-key) "d"))
      (should (plist-get manifest :smart))
      (should (equal (plist-get manifest :module) "page.mjs"))
      (should-not (plist-get manifest :notes))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((accent "teal" "teal" "blue" "aubergine" "graphite")
                       (density "compact" "compact" "regular" "airy")
                       (skim "off" "off" "on")
                       (face "kufi" "kufi" "plex")
                       (hijri "off" "off" "on")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(accent density skim face hijri))))))

(ert-deftest imprimeur-skin-dubai-filter-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "imprimeur-skin-dubai/assets/filter.lua" repo-test-root))
                   0))))

(ert-deftest imprimeur-skin-dubai-says-it-has-no-affiliation ()
  (let ((readme (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/README.md")))
    (should (string-search "no relation to the Government of Dubai" readme))
    (should (string-search "does not use Dubai Font" readme))
    (should (string-search "3.1 d, i and j" readme)))
  ;; No part of the skin names Dubai Font, whose family is Dubai, but to say that it is not used.
  (let ((case-fold-search nil))
    (dolist (file '("imprimeur-skin-dubai/assets/skin.css" "imprimeur-skin-dubai/assets/filter.lua"))
      (should-not (string-match-p "\"Dubai\"\\|Dubai Font" (imprimeur-skin-dubai-test-read file))))))

;;;; The fonts

(ert-deftest imprimeur-skin-dubai-cuts-the-families-that-its-sheet-names ()
  (let* ((fonts (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/fonts.nix"))
         ;; Each family that fonts.nix cuts, with its faces' labels.
         (cuts (let ((at 0) found)
                 (while (string-match "(cuts \"\\([^\"]+\\)\"\\(\\(?:.\\|\n\\)*?\\)\\])" fonts at)
                   (let ((family (match-string 1 fonts)) (body (match-string 2 fonts)) (inner 0) labels)
                     (setq at (match-end 0))
                     (while (string-match "(cut \"\\([^\"]+\\)\" [0-9]+)" body inner)
                       (setq inner (match-end 0))
                       (push (match-string 1 body) labels))
                     (push (cons family (nreverse labels)) found)))
                 (nreverse found)))
         (sheet (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/assets/skin.css"))
         (faces (mapcan (lambda (cut) (mapcar (lambda (label) (concat (car cut) " " label)) (cdr cut))) cuts))
         (named nil)
         (start 0))
    ;; By hand from the plan: text 400 and 700, headings 600 and 700, Kufam 500 and 700.
    (should (equal cuts '(("Dubai Kufi" "Regular" "Bold")
                          ("Dubai Alexandria" "SemiBold" "Bold")
                          ("Dubai Kufam" "Medium" "Bold"))))
    (while (string-match "local(\"\\(Dubai [^\"]+\\)\")" sheet start)
      (setq start (match-end 0))
      (push (match-string 1 sheet) named))
    ;; Every face that local() names is cut, and every cut face is named, but Kufam's, which
    ;; the sheet asks for by its family, with the weight.
    (dolist (face named)
      (ert-info (face) (should (member face faces))))
    (dolist (face faces)
      (ert-info (face)
        (should (or (member face named) (string-prefix-p "Dubai Kufam " face)))))
    (should (string-search "--dubai-font-label: \"Dubai Kufam\"" sheet))))

(ert-deftest imprimeur-skin-dubai-installs-each-face-whole-and-credits-it ()
  (let ((fonts (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/fonts.nix"))
        (readme (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/README.md"))
        (sheet (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/assets/skin.css")))
    ;; nixpkgs's google-fonts revision, each file by its hash, with its licence beside it.
    (should (string-search "5174b3333331c966c38f4355d50b03ca1c1df2f9" fonts))
    (dolist (file '("NotoKufiArabic[wght].ttf" "Alexandria[wght].ttf" "Kufam[wght].ttf"))
      (ert-info (file) (should (string-search (format "\"%s\"" file) fonts))))
    (should-not (string-search "Kufam-Italic" fonts))
    (should (equal (imprimeur-skin-dubai-test-count "\"sha256-[A-Za-z0-9+/]\\{43\\}=\"" fonts) 6))
    (should (string-search "share/licenses/${family}/OFL.txt" fonts))
    ;; The cut is XIX's, which keeps every glyph, and nothing subsets a font.
    (should (equal (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/make-cut.py")
                   (imprimeur-skin-dubai-test-read "imprimeur-skin-xix/make-cut.py")))
    (dolist (text (list fonts (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/make-cut.py")))
      (should-not (string-match-p "subset\\|woff2\\|-fonts\\.override *{" text)))
    ;; Each face's designers and licence, in the README.
    (dolist (name '("Monotype Design Team" "David Williams" "Khaled Hosny" "Mohamed Gaber" "Wael Morcos"
                    "Artur Schmal" "Rasmus Andersson" "Mike Abbink" "Nadine Chahine" "Mohamad Dakak"
                    "Xiangdong Zeng"))
      (ert-info (name) (should (string-search name readme))))
    (should (>= (imprimeur-skin-dubai-test-count "OFL-1.1" readme) 8))
    ;; The sheet names installed fonts alone.
    (should-not (string-search "url(" sheet))
    (should (equal (imprimeur-skin-dubai-test-count "@font-face" sheet)
                   (imprimeur-skin-dubai-test-count "src: local(" sheet)))
    ;; No font file enters the repository.
    (should-not (string-match-p
                 "\\.\\(?:ttf\\|otf\\|ttc\\|woff2?\\|eot\\)$"
                 (cdr (repo-test-run "git" (list "ls-files") nil repo-test-root))))))

;;;; The palette

(defun imprimeur-skin-dubai-test-colours (sheet property)
  "Return each pair of colours, light then dark, that SHEET gives PROPERTY, in order.
A colour is a list of three components from 0 to 1."
  (let ((start 0) found)
    (while (string-match (format "--%s: light-dark(#\\([0-9a-f]\\{6\\}\\), #\\([0-9a-f]\\{6\\}\\))" property)
                         sheet start)
      (setq start (match-end 0))
      (push (mapcar (lambda (hex)
                      (mapcar (lambda (at) (/ (string-to-number (substring hex at (+ at 2)) 16) 255.0)) '(0 2 4)))
                    (list (match-string 1 sheet) (match-string 2 sheet)))
            found))
    (nreverse found)))

(defun imprimeur-skin-dubai-test-contrast (one other)
  "Return the contrast ratio of the colours ONE and OTHER, by WCAG 2."
  (let ((lighter (nth 1 (apply #'color-srgb-to-xyz one)))
        (darker (nth 1 (apply #'color-srgb-to-xyz other))))
    (when (< lighter darker) (cl-rotatef lighter darker))
    (/ (+ lighter 0.05) (+ darker 0.05))))

(defun imprimeur-skin-dubai-test-over (colour ground share)
  "Return COLOUR at SHARE, from 0 to 1, over GROUND, as color-mix with transparent paints it."
  (cl-mapcar (lambda (a b) (+ (* a share) (* b (- 1 share)))) colour ground))

(ert-deftest imprimeur-skin-dubai-keeps-its-colours-legible-and-apart ()
  (let* ((sheet (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/assets/skin.css"))
         (ground (car (imprimeur-skin-dubai-test-colours sheet "imp-background")))
         (code (car (imprimeur-skin-dubai-test-colours sheet "imp-code-background")))
         (accents (imprimeur-skin-dubai-test-colours sheet "dubai-accent"))
         (statuses (mapcar (lambda (name) (car (imprimeur-skin-dubai-test-colours sheet name)))
                           '("dubai-amber" "dubai-red" "dubai-green" "dubai-blue"))))
    ;; teal by default, blue, aubergine and graphite.
    (should (equal (length accents) 4))
    (should (seq-every-p #'identity statuses))
    ;; Light, with the tints of the light palette; then dark, with its own.
    (pcase-dolist (`(,side ,tint ,chip) '((0 0.06 0.12) (1 0.09 0.20)))
      (let ((page (nth side ground)))
        (ert-info ((format "side %d" side))
          (dolist (pair (list (car (imprimeur-skin-dubai-test-colours sheet "imp-foreground"))
                              (car (imprimeur-skin-dubai-test-colours sheet "imp-muted"))))
            (should (>= (imprimeur-skin-dubai-test-contrast (nth side pair) page) 4.5))
            (should (>= (imprimeur-skin-dubai-test-contrast (nth side pair) (nth side code)) 4.5)))
          (dolist (pair accents)
            (let ((accent (nth side pair)))
              (should (>= (imprimeur-skin-dubai-test-contrast accent page) 4.5))
              (should (>= (imprimeur-skin-dubai-test-contrast
                           accent (imprimeur-skin-dubai-test-over accent page tint))
                          4.5))
              (dolist (status statuses)
                (should (>= (sqrt (apply #'+ (cl-mapcar (lambda (a b) (expt (- a b) 2))
                                                        (apply #'color-srgb-to-lab accent)
                                                        (apply #'color-srgb-to-lab (nth side status)))))
                            25)))))
          (dolist (status statuses)
            (should (>= (imprimeur-skin-dubai-test-contrast
                         (nth side status) (imprimeur-skin-dubai-test-over (nth side status) page chip))
                        4.5))))))))

;;;; The filter

(ert-deftest imprimeur-skin-dubai-finds-the-quantities-of-a-table ()
  ;; Each row: a column's cells, in a language, and whether it stands on the right.
  (pcase-dolist (`(,lang ,cells ,right)
                 '(("ar" ("١٬٢٥٠٫٥" "١٬٢٥٠٫٥" "١٬٢٥٠٫٥") t)
                   ("ar" ("AED 1,250.00" "AED 1,250.00" "AED 1,250.00") t)
                   ("ar" ("1,250 د.إ" "1,250 د.إ" "1,250 د.إ") t)
                   ("ar" ("١٢٪" "١٢٪" "١٢٪") t)
                   ("ar" ("1,250 درهم" "١٬٢٥٠ درهم" "−١٢") t)
                   ("ar" ("۱۲٫۵" "۱۲" "") t)
                   ("ar" ("٢٠٢٤-١٠-٢٢" "٢٠٢٤-١٠-٢٣" "٢٠٢٤-١٠-٢٤") nil)
                   ("ar" ("2024-10-22" "2024-10-23" "2024-10-24") nil)
                   ("ar" ("٢٢/١٠/٢٠٢٤" "٢٣/١٠/٢٠٢٤" "٢٤/١٠/٢٠٢٤") nil)
                   ("ar" ("22/10/2024" "23/10/2024" "24/10/2024") nil)
                   ("ar" ("١٤٤٦هـ" "١٤٤٧هـ" "١٤٤٨هـ") nil)
                   ("ar" ("كثير" "قليل" "١٢") nil)
                   ;; Briefing's own, in English.
                   ("en" ("412,880" "£84,000" "€1,200") t)
                   ("en" ("$217" "81" "$2,500") t)
                   ("en" ("-16" "−16" "12%") t)
                   ("en" ("3.5k" "0.5" "1e6") t)
                   ("en" ("1.2.3" "4.5.6" "7.8.9") nil)
                   ("en" ("10 20" "30 40" "50 60") nil)
                   ("en" ("1,23" "4,56" "7,89") nil)
                   ("en" ("" "" "") nil)))
    (ert-info ((format "%s %S" lang cells))
      (let* ((rows (mapconcat (lambda (cell) (format "| x | %s |\n" cell)) cells ""))
             (html (imprimeur-skin-dubai-test-html
                    "gfm" (format "---\nlang: %s\n---\n\n| Name | Value |\n|---|---|\n%s" lang rows))))
        (should (equal (imprimeur-skin-dubai-test-right-columns html) (if right 1 0))))))
  ;; A cell over 64 bytes is no quantity, and a minus in a quantity is a true one.
  (should (equal (imprimeur-skin-dubai-test-right-columns
                  (imprimeur-skin-dubai-test-html
                   "gfm" (format "| Name | Value |\n|---|---|\n| x | %s |\n" (make-string 65 ?1))))
                 0))
  (should (string-search "−١٦" (imprimeur-skin-dubai-test-html "gfm" "| A | B |\n|---|---|\n| x | -١٦ |\n")))
  ;; The author's digits stay as typed.
  (let ((html (imprimeur-skin-dubai-test-doc "ar" "| أ | ب |\n|---|---|\n| س | ١٬٢٥٠٫٥ |\n| ص | 1,250.5 |")))
    (should (string-search ">١٬٢٥٠٫٥</td>" html))
    (should (string-search ">1,250.5</td>" html)))
  ;; A row named as a total takes the class, in either language; another does not.
  (pcase-dolist (`(,name ,total) '(("الإجمالي" t) ("المجموع" t) ("إجمالي النفقات" t) ("مجموع" t)
                                   ("Total" t) ("Sum" t) ("الإجماليات" nil) ("النفقات" nil) ("Summer" nil)))
    (ert-info (name)
      (should (eq (and (string-search
                        "class=\"dubai-total\""
                        (imprimeur-skin-dubai-test-html "gfm" (format "| A | B |\n|---|---|\n| %s | 1 |\n" name)))
                       t)
                  total)))))

(ert-deftest imprimeur-skin-dubai-draws-a-heading-s-marks-as-chips-in-arabic ()
  (pcase-dolist (`(,reader ,text ,words)
                 '(("org+smart"
                    "#+TITLE: T\n#+LANGUAGE: ar\n#+OPTIONS: p:t\n* TODO [#A] مراجعة المسودة :مالية:\nDEADLINE: <2026-11-02 Mon>\nنص.\n* آخر\n"
                    ("مفتوح" "P1" "الاستحقاق 2 نوفمبر" "مالية"))
                   ("gfm+sourcepos+smart"
                    "---\ntitle: T\nlang: ar\n---\n\n## DONE: [#B] مراجعة المسودة :مالية:\n\nSCHEDULED: 2026-01-01, OWNER: فلان\n\nنص.\n\n## آخر\n"
                    ("منجز" "P2" "البدء 1 يناير" "فلان" "مالية"))
                   ("gfm+sourcepos+smart"
                    "---\ntitle: T\nlang: en\n---\n\n## TODO: [#A] Review the draft :ops:\n\nDEADLINE: 2026-11-02\n\nWords.\n\n## Bare\n"
                    ("Open" "P1" "Due 2 Nov" "ops"))))
    (ert-info (text)
      (let ((html (imprimeur-skin-dubai-test-html reader text)))
        (dolist (word words)
          (ert-info (word) (should (string-search (format "data-word=\"%s\"" word) html))))
        (should-not (string-match-p "class=\"dubai-chip\"[^>]*>[^<]" html))
        ;; The heading keeps the document's ASCII keyword, and no id holds it.
        (should (string-match-p "<h[12][^>]*>\\(?:.\\|\n\\)*\\(?:TODO\\|DONE\\)" html))
        (should-not (string-match-p "id=\"[^\"]*\\(?:todo\\|done\\)" html))))))

(ert-deftest imprimeur-skin-dubai-finds-the-bottom-line-the-key-figures-and-the-callouts ()
  (pcase-dolist (`(,title ,lang) '(("الخلاصة" "ar") ("الملخص التنفيذي" "ar") ("Summary" "en") ("Bottom line" "en")))
    (ert-info (title)
      (let ((html (imprimeur-skin-dubai-test-doc
                   lang (format "# %s\n\nفي **12 مليار درهم** و**١٥ مليار** و**AED 5 bn** و**كلمة** و**سنة 2025:**.\n\n## تحت\n\nأيضاً.\n\n# بعد\n\nخارج **3 مليارات**.\n" title))))
        (should (string-match-p "dubai-bottom-line\\(?:.\\|\n\\)*أيضاً\\(?:.\\|\n\\)*</section>\\(?:.\\|\n\\)*بعد" html))
        ;; A strong phrase that begins with a quantity, of either digits or after a currency,
        ;; is a key figure in the bottom line alone.
        (should (equal (imprimeur-skin-dubai-test-count "class=\"dubai-kpi\"" html) 3))
        (should (string-search "<span class=\"dubai-kpi\"><strong>12 مليار درهم</strong></span>" html))
        (should (string-search "<span class=\"dubai-kpi\"><strong>١٥ مليار</strong></span>" html)))))
  (let ((html (imprimeur-skin-dubai-test-doc "ar" "# عادي\n\nفي **12 مليار**.\n")))
    (should-not (string-search "dubai-bottom-line" html))
    (should-not (string-search "dubai-kpi" html)))
  ;; A block of class summary takes its label from the skin.
  (should (string-search "class=\"dubai-label\">\nالخلاصة"
                         (imprimeur-skin-dubai-test-html
                          "org" "#+LANGUAGE: ar\n#+begin_summary\nالجواب.\n#+end_summary\n")))
  ;; A callout's kind and label come from the alert, or a leading strong word.
  (pcase-dolist (`(,block ,kind ,label)
                 '(("[!IMPORTANT]" "decision" "مهم") ("[!WARNING]" "ask" "تنبيه") ("[!CAUTION]" "risk" "تحذير")
                   ("[!NOTE]" "note" "ملاحظة") ("[!TIP]" "note" "نصيحة")))
    (ert-info (block)
      (let ((html (imprimeur-skin-dubai-test-doc "ar" (format "> %s\n> نص." block))))
        (should (string-search (format "data-kind=\"%s\"" kind) html))
        (should (string-search (format "class=\"dubai-label\">\n%s" label) html)))))
  (let ((html (imprimeur-skin-dubai-test-doc "ar" "> [!WARNING]\n> **طلب:** نص.")))
    (should (string-search "class=\"dubai-label\">\nطلب" html))
    (should-not (string-search "<strong>" html)))
  (let ((html (imprimeur-skin-dubai-test-html
               "org" (concat "#+LANGUAGE: ar\n#+begin_decision\nنص.\n#+end_decision\n\n#+begin_ask\nنص.\n#+end_ask\n\n"
                             "#+begin_risk\nنص.\n#+end_risk\n\n#+begin_note\nنص.\n#+end_note\n"))))
    (dolist (label '("قرار" "طلب" "مخاطرة" "ملاحظة"))
      (ert-info (label) (should (string-search (format "class=\"dubai-label\">\n%s" label) html))))))

(ert-deftest imprimeur-skin-dubai-writes-a-masthead-with-the-day-to-be-dated ()
  (let ((html (imprimeur-skin-dubai-test-html
               "gfm" "---\ntitle: T\nsubtitle: S\nauthor: فلان\ndate: 2024-10-22\nstatus: للقرار\nlang: ar\n---\n\nنص.\n")))
    (dolist (text '("class=\"dubai-subtitle\"" ">فلان</span>" ">22 أكتوبر 2024</span>"
                    "<time class=\"dubai-hijri\" datetime=\"2024-10-22\"></time>" ">للقرار</span>"
                    ">مدة القراءة 1 د</span>" ">نظرة سريعة</span>" ">المذكرة كاملة</span>"
                    "role=\"button\"" "aria-pressed=\"false\""))
      (ert-info (text) (should (string-search text html)))))
  ;; In the digits it was typed in, and its day in ASCII for the page.
  (let ((html (imprimeur-skin-dubai-test-html "org" "#+TITLE: T\n#+DATE: ٢٠٢٤-١٠-٢٢\n#+LANGUAGE: ar\n\nنص.\n")))
    (should (string-search ">٢٢ أكتوبر ٢٠٢٤</span>" html))
    (should (string-search "datetime=\"2024-10-22\"" html)))
  (let ((html (imprimeur-skin-dubai-test-html "gfm" "---\ntitle: T\ndate: 2024-10-22\nlang: en\n---\n\nWords.\n")))
    (dolist (text '(">22 October 2024</span>" ">1 min read</span>" ">Skim</span>" ">Full brief</span>"))
      (ert-info (text) (should (string-search text html)))))
  ;; Each month, by hand from CLDR's ar-AE.
  (seq-do-indexed
   (lambda (name index)
     (ert-info (name)
       (should (string-search (format ">1 %s 2025</span>" name)
                              (imprimeur-skin-dubai-test-html
                               "gfm" (format "---\ntitle: T\ndate: 2025-%02d-01\nlang: ar\n---\n\nنص.\n" (1+ index)))))))
   '("يناير" "فبراير" "مارس" "أبريل" "مايو" "يونيو" "يوليو" "أغسطس" "سبتمبر" "أكتوبر" "نوفمبر" "ديسمبر"))
  ;; A date that is no day stays as written, with nothing to date.
  (pcase-dolist (`(,date ,shown) '(("2026-13-01" "2026-13-01") ("في الربيع" "في الربيع")))
    (ert-info (date)
      (let ((html (imprimeur-skin-dubai-test-html "gfm" (format "---\ntitle: T\ndate: %s\nlang: ar\n---\n\nنص.\n" date))))
        (should (string-search (format ">%s</span>" shown) html))
        (should-not (string-search "dubai-hijri" html))))))

(ert-deftest imprimeur-skin-dubai-never-writes-the-rial-sign ()
  (should-not (string-search "\ufdfc" (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/assets/filter.lua")))
  (should-not (string-search "u{FDFC}" (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/assets/filter.lua")))
  (let ((html (imprimeur-skin-dubai-test-doc
               "ar" "# الخلاصة\n\nفي **1,250 درهم**.\n\n| أ | ب |\n|---|---|\n| س | 1,250 د.إ |\n| ص | AED 5 |")))
    (should-not (string-search "\ufdfc" html))))

(ert-deftest imprimeur-skin-dubai-keeps-repeated-titles-apart-and-plain-code-whole ()
  (let ((html (imprimeur-skin-dubai-test-html "gfm" "## نفسه\n\n## نفسه\n\n## TODO: [#A] نفسه\n")))
    (should (equal (imprimeur-skin-dubai-test-count "<h1 id=\"doc-نفسه\\(?:-[0-9]\\)?\"" html) 3)))
  (let ((html (imprimeur-skin-dubai-test-html
               "gfm+sourcepos" "نص.\n\n```\nshort <b>\na line of more than forty columns with --a-flag in it\n```\n")))
    (should (string-search "<span>short &lt;b&gt;</span>" html))
    (should (string-search "<span class=\"dubai-word\">--a-flag</span>" html))))

(ert-deftest imprimeur-skin-dubai-writes-the-same-bytes-twice ()
  (let ((text (imprimeur-skin-dubai-test-read "examples/dubai/budget-2026-2028.md")))
    (should (equal (imprimeur-skin-dubai-test-html "gfm+sourcepos+smart" text)
                   (imprimeur-skin-dubai-test-html "gfm+sourcepos+smart" text)))))

;;;; The samples

(ert-deftest imprimeur-skin-dubai-samples-quote-the-laws-and-say-so ()
  (let* ((org (imprimeur-skin-dubai-test-read "examples/dubai/budget-2025-2027.org"))
         (markdown (imprimeur-skin-dubai-test-read "examples/dubai/budget-2026-2028.md"))
         (sources (imprimeur-skin-dubai-test-read "examples/dubai/SOURCES.md"))
         (org-html (imprimeur-skin-dubai-test-html "org+smart" org))
         (markdown-html (imprimeur-skin-dubai-test-html "gfm+sourcepos+smart" markdown)))
    ;; Passages of each law, as the portal gives them, the dash between years as a hyphen.
    (dolist (passage '("(272,060,000,000) مئتان واثنان وسبعون ملياراً وستون مليون درهم."
                       "يُعمل بهذا القانون اعتباراً من الأوّل من يناير 2025، ويُنشر في الجريدة الرسميّة."
                       "الموافــــــــــــق 19 ربيع الآخر 1446هـ"
                       "للسّنوات الماليّة 2025 - 2027 بمبلغ مقداره (302,460,000,000)"))
      (ert-info (passage) (should (string-search passage org))))
    (dolist (passage '("يُعمل بهذا القانون اعتباراً من الأوّل من شهر يناير 2026، ويُنشر في الجريدة الرسميّة."
                       "عدم تجاوز التكلفة الإجماليّة المُعتمدة للمشروع الإنشائي"
                       "| الوفر المالي | 6,400,000,000 | 3,170,000,000 | -3,230,000,000 |"))
      (ert-info (passage) (should (string-search passage markdown))))
    (dolist (text (list "Law No. (23) of 2024" "Law No. (15) of 2025" "No reader of Arabic"
                        "Decree-Law No. 38 of 2021" "article 3(2)" "Read the official text"))
      (ert-info (text) (should (string-search text sources))))
    ;; Each says in Arabic that what is not the law's is the editor's.
    (dolist (text (list org markdown))
      (should (string-search "من وضع المحرر" text))
      (should (string-search "يُرجى الرجوع إلى النص الرسمي" text))
      (should-not (string-search "\ufdfc" text)))
    ;; Both render as briefs: a masthead dated for the option, a bottom line with key figures.
    (should (string-search "datetime=\"2024-10-22\"" org-html))
    (should (string-search "datetime=\"2025-11-17\"" markdown-html))
    (dolist (html (list org-html markdown-html))
      (should (equal (imprimeur-skin-dubai-test-count "class=\"[^\"]*dubai-bottom-line" html) 1))
      (should (>= (imprimeur-skin-dubai-test-count "class=\"dubai-kpi\"" html) 2)))
    (should (equal (imprimeur-skin-dubai-test-count "data-kind=\"priority\"" org-html) 4))
    (should (string-search "−3,230,000,000" markdown-html))))

(ert-deftest imprimeur-skin-dubai-arabic-showcase-follows-the-english-one ()
  (let ((arabic (imprimeur-skin-dubai-test-read "examples/arabic/showcase.org"))
        (english (imprimeur-skin-dubai-test-read "examples/showcase.org")))
    (should (string-search "#+LANGUAGE: ar\n" arabic))
    (should (string-match-p "^# .*No reader of Arabic" arabic))
    (should (string-search "[[file:../../docs/images/printer-1568.png]]" arabic))
    (should (file-exists-p (expand-file-name "docs/images/printer-1568.png" repo-test-root)))
    ;; The same blocks, in the same order: a diagram, a picture, a table, code, a heading,
    ;; maths, a task list and a note; the code itself unchanged.
    (let ((shape (lambda (text)
                   (let ((start 0) found)
                     (while (string-match "^\\(#\\+begin_src [a-z]+\\|\\[\\[file:\\|| =\\|\\* \\|\\\\\\[\\|- \\[[X ]\\]\\|\\[fn:1\\] \\)"
                                          text start)
                       (setq start (match-end 0))
                       (push (match-string 1 text) found))
                     (nreverse found)))))
      (should (equal (funcall shape arabic) (funcall shape english))))
    (string-match "#\\+begin_src elisp\n\\(\\(?:.\\|\n\\)*?\\)#\\+end_src" english)
    (should (string-search (match-string 1 english) arabic))))

;;;; The page

(ert-deftest imprimeur-skin-dubai-sets-both-briefs-right-to-left ()
  (pcase-dolist (`(,file ,callouts ,chips)
                 '(("budget-2025-2027.org" 3 4)
                   ("budget-2026-2028.md" 2 1)))
    (ert-info (file)
      (imprimeur-skin-dubai-test-with
          (_buffer browser file (imprimeur-skin-dubai-test-read (concat "examples/dubai/" file)))
        (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-masthead') !== null")
        (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.skin") "dubai"))
        (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dir") "rtl"))
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.dubai-bottom-line').length") 1))
        (should (>= (imprimeur-test-cdp-eval browser "document.querySelectorAll('.dubai-kpi').length") 2))
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.dubai-callout').length") callouts))
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.dubai-chip[data-kind=\"priority\"]').length")
                       chips))
        ;; A column of figures keeps the physical right, in a page right to left.
        (should (equal (imprimeur-test-cdp-eval
                        browser "getComputedStyle(document.querySelector('.dubai-table tbody td:nth-child(2)')).textAlign")
                       "right"))
        (dolist (width '(640 420))
          (ert-info ((number-to-string width))
            (imprimeur-skin-dubai-test-viewport browser width 900)
            (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.scrollWidth")
                           (imprimeur-test-cdp-eval browser "document.documentElement.clientWidth")))))
        (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))))))

(ert-deftest imprimeur-skin-dubai-sets-the-arabic-showcase-with-code-and-maths-left-to-right ()
  (imprimeur-skin-dubai-test-with
      (_buffer browser "examples/arabic/showcase.org" (imprimeur-skin-dubai-test-read "examples/arabic/showcase.org"))
    (imprimeur-test-cdp-wait browser "document.querySelector('main pre code') !== null")
    (imprimeur-test-cdp-wait
     browser "[...document.querySelectorAll('main img')].every((image) => image.complete && image.naturalWidth > 0)")
    (dolist (width '(640 420))
      (ert-info ((number-to-string width))
        (imprimeur-skin-dubai-test-viewport browser width 900)
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const root = document.documentElement;
  const style = (selector) => getComputedStyle(document.querySelector(selector)).direction;
  const pill = document.querySelector('.imprimeur-minitoc-pill').getBoundingClientRect();
  return [root.dir, style('main p'), style('main pre'), style('main math'),
          pill.width > 0 && pill.right <= innerWidth / 2, root.scrollWidth <= root.clientWidth];
})()")
                       ["rtl" "rtl" "ltr" "ltr" t t]))))
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-banner').textContent") ""))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-dubai-sets-labels-and-chips-without-spacing-or-capitals-in-arabic ()
  ;; Chromium gives a letter-spacing of 0 as normal.
  (let ((labels "[...document.querySelectorAll('.dubai-label, .dubai-chip, .dubai-bottom-line > :first-child')]
  .map((element) => { const style = getComputedStyle(element);
    return [parseFloat(style.letterSpacing) || 0, style.textTransform, style.fontVariantCaps]; })"))
    (imprimeur-skin-dubai-test-with (buffer browser "memo.md" imprimeur-skin-dubai-test-memo)
      (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-masthead') !== null")
      (let ((found (append (imprimeur-test-cdp-eval browser labels) nil)))
        (should (>= (length found) 5))
        (dolist (style found)
          (should (equal style [0 "none" "normal"]))))
      ;; In English, a label takes Kufam's small capitals and a little air.
      (imprimeur-skin-dubai-test-replace
       buffer browser (replace-regexp-in-string "lang: ar" "lang: en" imprimeur-skin-dubai-test-memo)
       "document.documentElement.lang === 'en' && document.querySelector('.dubai-label') !== null")
      (should (equal (imprimeur-skin-dubai-test-style browser ".dubai-callout > .dubai-label" "fontVariantCaps")
                     "all-small-caps"))
      (should (> (imprimeur-test-cdp-eval
                  browser "parseFloat(getComputedStyle(document.querySelector('.dubai-callout > .dubai-label')).letterSpacing) || 0")
                 0)))))

(ert-deftest imprimeur-skin-dubai-dates-the-day-by-umm-al-qura-under-its-option ()
  (imprimeur-skin-dubai-test-with (buffer browser "memo.md" imprimeur-skin-dubai-test-memo)
    (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-date') !== null")
    ;; The calendar itself, in this engine: the law's own pair.
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const parts = new Intl.DateTimeFormat('en-u-ca-islamic-umalqura', { timeZone: 'UTC', day: 'numeric', month: 'numeric', year: 'numeric' })
    .formatToParts(Date.UTC(2024, 9, 22));
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return [value.day, value.month, value.year];
})()")
                   ["19" "4" "1446"]))
    (let ((hijri "(() => { const time = document.querySelector('time.dubai-hijri');
  return [time.textContent, getComputedStyle(time).display]; })()"))
      ;; Hidden by default, written all the same.
      (imprimeur-test-cdp-wait browser "document.querySelector('time.dubai-hijri').textContent !== ''")
      (should (equal (aref (imprimeur-test-cdp-eval browser hijri) 1) "none"))
      (imprimeur-skin-dubai-test-choose buffer browser "hijri" "on")
      ;; Day 19 of month 4, ربيع الآخر, of 1446, as formatToParts names them in the page.
      (let ((shown (imprimeur-test-cdp-eval browser hijri))
            (month (imprimeur-test-cdp-eval browser "new Intl.DateTimeFormat('ar-AE-u-ca-islamic-umalqura', { timeZone: 'UTC', month: 'long' })
  .formatToParts(Date.UTC(2024, 9, 22)).find((part) => part.type === 'month').value")))
        (should (equal month "ربيع الآخر"))
        (should (equal (aref shown 1) "block"))
        (should (string-match-p (format "\\`19 %s 1446" month) (aref shown 0))))
      ;; Typed in Arabic-Indic digits, it is written in them.
      (imprimeur-skin-dubai-test-replace
       buffer browser (replace-regexp-in-string "2024-10-22" "٢٠٢٤-١٠-٢٢" imprimeur-skin-dubai-test-memo)
       "document.querySelector('time.dubai-hijri')?.textContent.startsWith('١٩')")
      (should (string-search "١٤٤٦" (aref (imprimeur-test-cdp-eval browser hijri) 0)))
      ;; In English, in English; and a day that no calendar holds shows nothing.
      (imprimeur-skin-dubai-test-replace
       buffer browser (replace-regexp-in-string "lang: ar" "lang: en" imprimeur-skin-dubai-test-memo)
       "document.querySelector('.dubai-date')?.textContent === '22 October 2024'")
      (imprimeur-test-cdp-wait browser "/^19 \\S.* 1446/.test(document.querySelector('time.dubai-hijri').textContent)")
      (imprimeur-skin-dubai-test-replace
       buffer browser (replace-regexp-in-string "2024-10-22" "2024-02-31" imprimeur-skin-dubai-test-memo)
       "document.querySelector('.dubai-date')?.textContent === '31 فبراير 2024'")
      (should (equal (imprimeur-test-cdp-eval browser hijri) ["" "none"])))
    (should-not (imprimeur-test-cdp-errors browser))))

(defun imprimeur-skin-dubai-test-said (browser)
  "Return what each option decides of BROWSER's page, as an alist from the option.
The accent by a link's colour, the density by a paragraph's line over its size, the skim
view by whether the block of a paragraph takes any room, the face by the text's first
family, and the Umm al-Qura date by whether it shows."
  (list (cons 'accent (imprimeur-skin-dubai-test-style browser "#imprimeur-main a:not(.dubai-skim)" "color"))
        (cons 'density (imprimeur-test-cdp-eval browser (format "(() => {
  const style = getComputedStyle(%s.firstElementChild);
  return Math.round(100 * parseFloat(style.lineHeight) / parseFloat(style.fontSize));
})()" imprimeur-skin-dubai-test-body)))
        (cons 'skim (imprimeur-test-cdp-eval
                     browser (format "%s.getBoundingClientRect().height === 0" imprimeur-skin-dubai-test-body)))
        (cons 'face (imprimeur-test-cdp-eval
                     browser "getComputedStyle(document.querySelector('#imprimeur-main h2')).fontFamily.split(',')[0].replaceAll('\"', '')"))
        (cons 'hijri (imprimeur-skin-dubai-test-style browser "time.dubai-hijri" "display"))))

(ert-deftest imprimeur-skin-dubai-changes-what-each-option-says-alone ()
  (imprimeur-skin-dubai-test-with (buffer browser "memo.md" imprimeur-skin-dubai-test-memo)
    (with-current-buffer buffer
      (setq imprimeur-appearance 'light)
      (imprimeur-refresh-palette))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
    (imprimeur-test-cdp-wait browser "document.querySelector('time.dubai-hijri')?.textContent !== ''")
    (should-not (imprimeur-skin-dubai-test-attributes browser))
    (let ((defaults (imprimeur-skin-dubai-test-said browser)))
      ;; By hand from the plan: teal, 1.6, the whole memo, Alexandria then dubai-text, no date.
      (should (equal defaults '((accent . "rgb(0, 107, 100)") (density . 160) (skim . nil)
                                (face . "dubai-heading") (hijri . "none"))))
      (pcase-dolist (`(,id ,value ,property ,said ,default)
                     '(("accent" "blue" accent "rgb(31, 79, 163)" "teal")
                       ("accent" "aubergine" accent "rgb(91, 58, 140)" "teal")
                       ("accent" "graphite" accent "rgb(27, 29, 33)" "teal")
                       ("density" "regular" density 175 "compact")
                       ("density" "airy" density 190 "compact")
                       ("skim" "on" skim t "off")
                       ("face" "plex" face "dubai-plex" "kufi")
                       ("hijri" "on" hijri "block" "off")))
        (ert-info ((format "%s %s" id value))
          (imprimeur-skin-dubai-test-choose buffer browser id value)
          (let ((now (imprimeur-skin-dubai-test-said browser)))
            (should (equal (alist-get property now) said))
            (should (equal (assq-delete-all property (copy-alist now))
                           (assq-delete-all property (copy-alist defaults)))))
          (should (equal (imprimeur-skin-dubai-test-attributes browser) (list (format "data-dubai-%s" id))))
          (imprimeur-skin-dubai-test-choose buffer browser id default)
          (should (equal (imprimeur-skin-dubai-test-said browser) defaults))))
      (should-not (imprimeur-skin-dubai-test-attributes browser)))))

(ert-deftest imprimeur-skin-dubai-face-plex-enlarges-its-arabic-alone ()
  ;; Chromium reads the descriptor; whether WebKitGTK does is the smoke test's.
  (imprimeur-skin-dubai-test-with (buffer browser "memo.md" imprimeur-skin-dubai-test-memo)
    (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-masthead') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "[...document.styleSheets].flatMap((sheet) => [...sheet.cssRules])
  .filter((rule) => rule instanceof CSSFontFaceRule && rule.style.getPropertyValue('size-adjust') !== '')
  .map((rule) => [rule.style.getPropertyValue('font-family').replaceAll('\"', ''), rule.style.getPropertyValue('size-adjust'),
                  rule.style.getPropertyValue('unicode-range').startsWith('U+600')])")
                   (make-vector 5 ["dubai-plex" "125%" t])))
    (imprimeur-skin-dubai-test-choose buffer browser "face" "plex")
    ;; Kufam keeps the masthead and labels under either face.
    (pcase-dolist (`(,selector . ,family) '(("main p" . "dubai-plex") ("#imprimeur-main > h1" . "dubai-plex")
                                            ("#imprimeur-title" . "Dubai Kufam") (".dubai-label" . "Dubai Kufam")))
      (ert-info (selector)
        (should (equal (imprimeur-test-cdp-eval
                        browser (format "getComputedStyle(document.querySelector(%S)).fontFamily.split(',')[0].replaceAll('\"', '')"
                                        selector))
                       family))))))

(ert-deftest imprimeur-skin-dubai-skims-the-body-and-keeps-the-summaries ()
  (imprimeur-skin-dubai-test-with (buffer browser "memo.md" imprimeur-skin-dubai-test-memo)
    (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-masthead') !== null")
    (let ((height (lambda (selector)
                    (imprimeur-test-cdp-eval
                     browser (format "document.querySelector(%S).getBoundingClientRect().height" selector)))))
      (imprimeur-skin-dubai-test-choose buffer browser "skim" "on")
      (dolist (kept '(".dubai-masthead" ".dubai-bottom-line" ".dubai-callout" "#imprimeur-main > h1"
                      "#imprimeur-main > h2" ".dubai-chips"))
        (ert-info (kept) (should (> (funcall height kept) 0))))
      (dolist (hidden '(".dubai-table" "#imprimeur-main > h4"))
        (ert-info (hidden) (should (equal (funcall height hidden) 0)))))
    ;; The memo's link flips it back at once, and says so.
    (imprimeur-test-cdp-click browser "document.querySelector('.dubai-skim')")
    (imprimeur-test-cdp-wait browser "document.documentElement.getAttribute('data-dubai-skim') === null")
    (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-skim').getAttribute('aria-pressed') === 'false'")
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.dubai-skim').innerText") "نظرة سريعة"))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-dubai-shows-under-d-in-the-menu-with-its-five-options ()
  (imprimeur-skin-dubai-test-with (_buffer browser "memo.md" imprimeur-skin-dubai-test-memo)
    (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-masthead') !== null")
    (execute-kbd-macro (kbd "M-g s"))
    (unwind-protect
        (let ((text (with-current-buffer " *transient*" (buffer-substring-no-properties (point-min) (point-max)))))
          (dolist (line '(" d * Dubai" "Options of Dubai" " A Accent: Teal" " D Density: Compact"
                          " S Skim view: the bottom line, the titles to level three and the callouts: Off"
                          " F Face of the text and headings: Noto Kufi Arabic, Alexandria and Inter"
                          " H Umm al-Qura date beside the masthead's date: Off"))
            (ert-info (line) (should (string-search line text)))))
      (execute-kbd-macro (kbd "C-g")))))

(ert-deftest imprimeur-skin-dubai-leaves-nothing-after-a-swap ()
  (imprimeur-skin-dubai-test-with (buffer browser "memo.md" imprimeur-skin-dubai-test-memo)
    (imprimeur-test-cdp-wait browser "document.querySelector('time.dubai-hijri')?.textContent !== ''")
    (imprimeur-test-cdp-click browser "document.querySelector('.dubai-skim')")
    (imprimeur-test-cdp-wait browser "document.documentElement.hasAttribute('data-dubai-skim')")
    (with-current-buffer buffer (imprimeur-choose-skin "base"))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.skin === 'base'")
    (should-not (imprimeur-skin-dubai-test-attributes browser))
    (should-not (imprimeur-test-cdp-eval browser "document.documentElement.classList.contains('dubai-plain-figures')"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('[class*=\"dubai-\"], [style*=\"dubai-\"]').length") 0))
    (should (equal (imprimeur-test-cdp-eval
                    browser "[...document.styleSheets].flatMap((sheet) => [...sheet.cssRules]).filter((rule) => rule instanceof CSSFontFaceRule).length")
                   0))
    ;; A click on a link that a filter no more writes flips nothing.
    (imprimeur-test-cdp-eval
     browser "document.getElementById('imprimeur-main').insertAdjacentHTML('beforeend', '<a class=\"dubai-skim\" href=\"#x\">x</a>'); document.querySelector('.dubai-skim').click()")
    (should-not (imprimeur-skin-dubai-test-attributes browser))))

(ert-deftest imprimeur-skin-dubai-takes-no-option-from-a-document ()
  (imprimeur-skin-dubai-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: T\nauthor: A\nlang: ar\nskim: on\nhijri: on\nface: plex\ndata-dubai-skim: on\n---\n\n"
                       "نص.\n\n<div data-dubai-skim=\"on\">لا شيء.</div>\n"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.dubai-masthead') !== null")
    (should-not (imprimeur-skin-dubai-test-attributes browser))))

(ert-deftest imprimeur-skin-dubai-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/README.md"))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'dubai\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-dubai-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-dubai)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"dubai\" (imprimeur-skin-get \"dubai\") (imprimeur-skin-configured \"dubai\" (imprimeur-skin-get \"dubai\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "dubai[]" (cdr result)))))

(ert-deftest imprimeur-skin-dubai-sheet-keeps-to-its-names ()
  (let ((sheet (replace-regexp-in-string
                "/\\*\\(?:.\\|\n\\)*?\\*/" ""
                (imprimeur-skin-dubai-test-read "imprimeur-skin-dubai/assets/skin.css")))
        (start 0))
    (while (string-match "\\.\\([a-z][a-z-]*\\)[ ,:{)>]" sheet start)
      (setq start (match-end 0))
      (let ((class (match-string 1 sheet)))
        (ert-info (class)
          ;; What belongs to the shell, the core or pandoc keeps its name, and the skin's its own.
          (should (or (string-prefix-p "dubai-" class)
                      (member class '("task" "caption" "captioned-content" "sourceCode" "mermaid" "imprimeur-code"
                                      "footnotes" "footnote-ref" "footnote-back" "flowchart-link" "messageLine0"
                                      "messageLine1" "actor-line" "loopLine" "actor" "node" "cluster" "note"
                                      "kw" "cf" "im" "pp" "at" "st" "ss" "vs" "ch" "sc" "bn" "fu" "bu" "ex"
                                      "dt" "dv" "fl" "cn" "va" "op" "ot" "co" "do" "an" "cv" "in" "er" "wa" "al")))))))
    (should-not (string-search "briefing" sheet))))

;;; imprimeur-skin-dubai-test.el ends here

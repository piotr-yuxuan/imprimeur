;;; imprimeur-skin-yaqut-test.el --- Tests of the skin Yaqut  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 052, "Design (approved)" and "Verification":
;;
;; The manifest: menu key y; preset (mamluk, ottoman, persian), title (auto, thuluth, kufi,
;; raqq), notes (auto, margin, oblique, foot) and calendar (umalqura, civil), the first of each
;; the default.
;;
;; The page, in Chromium at 640 and 420 CSS px, by computed values, since make check has DejaVu
;; alone: dir=rtl on the root for ar and fa; pre and math left to right; the pill at the inline
;; end; no sideways scroll.  em and strong in Arabic keep the paragraph's weight, size and style,
;; and change its colour.  The colophon's year follows U+0601, and 22 October 2024 is 19 Rabi'
;; al-Thani 1446 by Umm al-Qura, in the parts of formatToParts; the seal has role=img and its
;; label.  Glosses stand in the margin, outside the jadwal, and go back to the foot below about
;; 600 px or under notes=foot; persian, and notes=oblique, slant them.  The colophon is a triangle
;; with the apex down.  Nothing is left after a swap.
;;
;; The filter, on real pandoc: #+COLOPHON, #+HIJRI and #+SEAL, as Markdown's metadata; U+0601
;; before the last run of digits of the Hijri date, or else a date for the page from #+DATE
;; written YYYY-MM-DD; what is enclosed in ﴿ ﴾ set apart, whole words alone.
;;
;; The fonts: whole and credited, no url( but to the skin's own files, no tracked font file, Raqq
;; installed as released with its licence beside it.  Aref Ruqaa is left out, as the WebKit of an
;; Emacs window draws it without its letters' dots: see the skin's README.
;;
;; The samples: real texts from the sources that SOURCES.md names, which no reader of Arabic or
;; Persian has checked, and neither U+06DD nor U+06DE anywhere in the skin or its samples.
;;
;; The tests register Yaqut in a registry of their own, as the other tests see the plain page alone.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-yaqut-test-file
  (expand-file-name "imprimeur-skin-yaqut/imprimeur-skin-yaqut.el" repo-test-root)
  "The skin's main file.")

(defun imprimeur-skin-yaqut-test-read (file)
  "Return the text of FILE, under the repository's root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file repo-test-root))
    (buffer-string)))

(defun imprimeur-skin-yaqut-test-html (reader text)
  "Return the HTML that Yaqut's chain writes from TEXT in READER, on real pandoc."
  (let ((pandoc (imprimeur-test-require "pandoc"))
        (imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-yaqut-test-file nil t)
    (with-temp-buffer
      (insert text)
      (should (equal (apply #'call-process-region (point-min) (point-max) pandoc t t nil
                            (imprimeur-render-arguments reader nil nil "python,bash"
                                                        (imprimeur-skin-get "yaqut")))
                     0))
      (buffer-string))))

(defun imprimeur-skin-yaqut-test-doc (front body)
  "Return the HTML of a Markdown document in Arabic, titled T, with FRONT matter and BODY."
  (imprimeur-skin-yaqut-test-html
   "gfm+sourcepos" (format "---\ntitle: T\nlang: ar\n%s---\n\n%s\n" front body)))

(defmacro imprimeur-skin-yaqut-test-with (spec &rest body)
  "Run BODY with Yaqut as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in the
selected Emacs window, in `imprimeur-mode'; BROWSER shows its page, at 640 by 900."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'yaqut)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (load imprimeur-skin-yaqut-test-file nil t)
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-mode 1)
                 (imprimeur-skin-yaqut-test-viewport ,browser 640 900)
                 (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
                 (imprimeur-test-wait-for
                  (lambda () (imprimeur-test-cdp-eval ,browser "document.documentElement.dataset.revision")))
                 (imprimeur-test-cdp-wait ,browser "document.documentElement.dataset.skin === 'yaqut'")
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-skin-yaqut-test-viewport (browser width height)
  "Give BROWSER's page a viewport of WIDTH by HEIGHT CSS px, and let it lay out."
  (imprimeur-test-cdp-call browser "Emulation.setDeviceMetricsOverride"
                           `(:width ,width :height ,height :deviceScaleFactor 1 :mobile :false))
  (imprimeur-test-cdp-wait browser (format "window.innerWidth === %d && window.innerHeight === %d" width height))
  (accept-process-output nil 0.1))

(defun imprimeur-skin-yaqut-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-yaqut-%s') === %s"
                   id (if (member value '("mamluk" "auto" "umalqura")) "null" (format "%S" value)))))

(defun imprimeur-skin-yaqut-test-style (browser selector property)
  "Return the computed PROPERTY of what SELECTOR finds first in BROWSER's page."
  (imprimeur-test-cdp-eval
   browser (format "getComputedStyle(document.querySelector(%S))[%S]" selector property)))

(defun imprimeur-skin-yaqut-test-family (browser selector)
  "Return the first family of what SELECTOR finds first in BROWSER's page, without its quotes."
  (string-trim (car (split-string (imprimeur-skin-yaqut-test-style browser selector "fontFamily") ","))
               "\"" "\""))

(defconst imprimeur-skin-yaqut-test-sideways
  "document.documentElement.scrollWidth - document.documentElement.clientWidth"
  "How far a page scrolls sideways, in CSS px.")

(defconst imprimeur-skin-yaqut-test-notes
  (concat "---\ntitle: T\nlang: ar\n---\n\n"
          "# أول\n\n"
          "نص فيه حاشية[^1] وأخرى[^2]، ونص يطول بعدها ليملأ السطر ويزيد عليه. "
          "ونص يطول بعدها ليملأ السطر ويزيد عليه.\n\n"
          "## ثان\n\nنص ثالث[^3].\n\n## ثالث\n\nنص.\n\n"
          "[^1]: الحاشية الأولى.\n[^2]: الحاشية الثانية.\n[^3]: الحاشية الثالثة.\n")
  "An Arabic document in Markdown, with three headings and three notes in two paragraphs.")

;;;; The package

(ert-deftest imprimeur-skin-yaqut-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-yaqut-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-yaqut-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-yaqut)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S\" (and (imprimeur-skin-get \"yaqut\") t)))"))))
    (should (equal (car result) 0))
    (should (string-match-p "MARK\\(.\\|\n\\)*before=nil after=t\\'" (cdr result)))))

(ert-deftest imprimeur-skin-yaqut-keeps-every-choice ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-yaqut-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "yaqut"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "Yaqut"))
      (should (equal (plist-get manifest :menu-key) "y"))
      (should (equal (plist-get manifest :module) "page.mjs"))
      (should (equal (plist-get manifest :files) '("unwan.svg" "rosette.svg")))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((preset "mamluk" "mamluk" "ottoman" "persian")
                       (title "auto" "auto" "thuluth" "kufi" "raqq")
                       (notes "auto" "auto" "margin" "oblique" "foot")
                       (calendar "umalqura" "umalqura" "civil")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(preset title notes calendar))))))

(ert-deftest imprimeur-skin-yaqut-filter-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "imprimeur-skin-yaqut/assets/filter.lua" repo-test-root))
                   0))))

(ert-deftest imprimeur-skin-yaqut-installs-its-fonts-whole-and-credits-them ()
  (let ((fonts (imprimeur-skin-yaqut-test-read "imprimeur-skin-yaqut/fonts.nix"))
        (readme (imprimeur-skin-yaqut-test-read "imprimeur-skin-yaqut/README.md"))
        (sheet (imprimeur-skin-yaqut-test-read "imprimeur-skin-yaqut/assets/skin.css")))
    ;; Raqq as released, under the AGPL, its licence beside it, and the README's warning.
    (should (string-search "agpl3Plus" fonts))
    (should (string-match-p "install -Dm444 -t \"\\$out/share/fonts/truetype/raqq\" Raqq\\.ttf LICENSE" fonts))
    (should (string-search "AGPL" readme))
    (should (string-search "embeds" readme))
    ;; Each family fetched alone comes with its licence, and nothing cuts a face.
    (should (equal (length (split-string fonts (regexp-quote "(fetched \"") t)) 3))
    (should (string-search "share/licenses/${family}/OFL.txt" fonts))
    (should-not (string-match-p "instancer\\|pyftsubset\\|subset\\|fontforge\\|fonttools\\|make-cut\\|woff2\\|ttx" fonts))
    (should-not (string-search "pkgs.google-fonts" fonts))
    ;; The sheet loads no font, and fetches nothing but the skin's own files.
    (should-not (string-search "@font-face" sheet))
    (let ((start 0) (urls nil))
      (while (string-match "url(\"\\([^\"]*\\)\")" sheet start)
        (push (match-string 1 sheet) urls)
        (setq start (match-end 0)))
      (should (equal (sort (delete-dups urls) #'string<) '("rosette.svg" "unwan.svg"))))
    ;; Every family that a stack names stands in the README's table of fonts.
    (let ((start 0) (case-fold-search nil))
      (while (string-match "\"\\([A-Z][A-Za-z ]+\\)\"" sheet start)
        (setq start (match-end 0))
        (ert-info ((match-string 1 sheet))
          (should (string-search (concat "| " (match-string 1 sheet) " |") readme)))))
    ;; No font file enters the repository.
    (should-not (string-match-p
                 "\\.\\(?:ttf\\|otf\\|ttc\\|woff2?\\|eot\\)$"
                 (cdr (repo-test-run "git" (list "ls-files") nil repo-test-root))))))

(ert-deftest imprimeur-skin-yaqut-uses-no-qur-anic-sign ()
  (dolist (file (append (directory-files-recursively (expand-file-name "imprimeur-skin-yaqut" repo-test-root) "")
                        (directory-files-recursively (expand-file-name "examples/yaqut" repo-test-root) "")))
    (ert-info (file)
      (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
        (should-not (string-search "\u06dd" text))
        (should-not (string-search "\u06de" text))))))

;;;; The filter

(ert-deftest imprimeur-skin-yaqut-takes-its-keys-from-org-and-markdown-alike ()
  (let ((org (imprimeur-skin-yaqut-test-html
              "org" "#+TITLE: T\n#+COLOPHON: تمت\n#+HIJRI: ١٤٤٦\n#+SEAL: ختم\n#+NOPE: لا يؤخذ\n\nنص.\n"))
        (gfm (imprimeur-skin-yaqut-test-doc "colophon: تمت\nhijri: ١٤٤٦\nseal: ختم\n" "نص.")))
    (dolist (html (list org gfm))
      (should (string-search "<p class=\"yaqut-colophon-text\">" html))
      (should (string-search "تمت</p>" html))
      (should (string-search "<span class=\"yaqut-year\">\u0601١٤٤٦</span>" html))
      (should (string-search "<span class=\"yaqut-seal\" role=\"img\" aria-label=\"ختم\">ختم</span>" html)))
    (should-not (string-search "لا يؤخذ" org)))
  ;; A seal alone still closes the page, with no words and no date.
  (let ((html (imprimeur-skin-yaqut-test-doc "seal: ختم\ndate: 2024-10-22\n" "نص.")))
    (should (string-search "aria-label=\"ختم\"" html))
    (should-not (string-search "yaqut-colophon-text" html))
    (should-not (string-search "yaqut-hijri" html)))
  ;; No colophon and no seal: nothing.
  (should-not (string-search "yaqut-colophon" (imprimeur-skin-yaqut-test-doc "date: 2024-10-22\n" "نص.")))
  ;; A document's words reach attributes and markup as text.
  (let ((html (imprimeur-skin-yaqut-test-doc "colophon: \"<img src=x>\"\nseal: \"a\\\" onclick=\\\"x\"\n" "نص.")))
    (should-not (string-search "<img src=x>" html))
    (should-not (string-search "\" onclick=" html))))

(ert-deftest imprimeur-skin-yaqut-sets-the-year-sign-before-the-year ()
  (pcase-dolist (`(,hijri ,want)
                 `(("١٩ ربيع الآخر ١٤٤٦" "١٩ ربيع الآخر <span class=\"yaqut-year\">\u0601١٤٤٦</span>")
                   ;; The year is the last run of digits, whatever digits they are.
                   ("19 ربيع الآخر 1446" "19 ربيع الآخر <span class=\"yaqut-year\">\u06011446</span>")
                   ("۱۹ ربیع‌الثانی ۱۴۴۶" "۱۹ ربیع‌الثانی <span class=\"yaqut-year\">\u0601۱۴۴۶</span>")
                   ;; What follows the year stays after it.
                   ("غرة رجب ١٤٤٦ هـ" "غرة رجب <span class=\"yaqut-year\">\u0601١٤٤٦</span> هـ")
                   ;; A sign that the author wrote is the page's, never twice.
                   ("رجب \u0601١٤٤٦" "رجب <span class=\"yaqut-year\">\u0601١٤٤٦</span>")
                   ;; No digit, no year: no date.
                   ("في رجب" nil)))
    (ert-info (hijri)
      (let ((html (imprimeur-skin-yaqut-test-doc (format "colophon: تمت\nhijri: \"%s\"\n" hijri) "نص.")))
        (if want
            (progn
              (should (string-search (concat "<p class=\"yaqut-colophon-date\">" want "</p>") html))
              (should (equal (length (split-string html "\u0601")) 2)))
          (should-not (string-search "yaqut-colophon-date" html)))))))

(ert-deftest imprimeur-skin-yaqut-dates-a-colophon-by-the-document-s-date ()
  (pcase-dolist (`(,reader ,text ,want)
                 '(("org" "#+TITLE: T\n#+DATE: 2024-10-22\n#+COLOPHON: تمت\n\nنص.\n" "2024-10-22")
                   ("org" "#+TITLE: T\n#+DATE: <2024-10-22 Tue>\n#+COLOPHON: تمت\n\nنص.\n" "2024-10-22")
                   ("gfm" "---\ntitle: T\ndate: 2024-10-22\ncolophon: تمت\n---\n\nنص.\n" "2024-10-22")
                   ;; Whether the date exists is the page's to judge.
                   ("gfm" "---\ntitle: T\ndate: 2024-13-45\ncolophon: تمت\n---\n\nنص.\n" "2024-13-45")
                   ("gfm" "---\ntitle: T\ndate: 22 October 2024\ncolophon: تمت\n---\n\nنص.\n" nil)
                   ("gfm" "---\ntitle: T\ndate: 2024-10\ncolophon: تمت\n---\n\nنص.\n" nil)
                   ;; The author's Hijri date comes first.
                   ("gfm" "---\ntitle: T\ndate: 2024-10-22\nhijri: ١٤٤٦\ncolophon: تمت\n---\n\nنص.\n" nil)))
    (ert-info (text)
      (let ((html (imprimeur-skin-yaqut-test-html reader text)))
        (if want
            (should (string-search (format "<time class=\"yaqut-hijri\" datetime=\"%s\">%s</time>" want want) html))
          (should-not (string-search "<time" html)))))))

(ert-deftest imprimeur-skin-yaqut-opens-each-block-with-the-glosses-of-its-notes ()
  (let ((html (imprimeur-skin-yaqut-test-html "gfm+sourcepos" imprimeur-skin-yaqut-test-notes)))
    ;; Each paragraph opens with its own, in their order, and pandoc keeps the notes for the foot.
    (should (string-match-p
             (concat "<p><span class=\"yaqut-hashiya\"><span class=\"yaqut-gloss\">الحاشية الأولى\\.</span>"
                     "<span class=\"yaqut-gloss\">الحاشية الثانية\\.</span></span>نص فيه حاشية<a")
             html))
    (should (string-match-p "<p><span class=\"yaqut-hashiya\"><span class=\"yaqut-gloss\">الحاشية الثالثة\\.</span></span>نص ثالث<a" html))
    (should (string-search "class=\"footnotes" html))
    (should (equal (length (split-string html "class=\"yaqut-hashiya\"")) 3)))
  ;; A note of several blocks keeps their words; a note in a verse of Org glosses it too.
  (let ((html (imprimeur-skin-yaqut-test-doc "" "نص[^1].\n\n[^1]: أول.\n\n    ```\n    رمز\n    ```\n")))
    (should (string-search "<span class=\"yaqut-gloss\">أول. رمز</span>" html)))
  (let ((html (imprimeur-skin-yaqut-test-html "org" "#+begin_verse\nشطر[fn::حاشية.]\nشطر\n#+end_verse\n")))
    (should (string-search "<span class=\"yaqut-hashiya\"><span class=\"yaqut-gloss\">حاشية.</span></span>شطر" html)))
  ;; A heading's stand in a block just before it, and leave its text its own.
  (let ((html (imprimeur-skin-yaqut-test-doc "" "## عنوان[^1]\n\nنص.\n\n[^1]: حاشية.\n")))
    (should (string-match-p (concat "<div class=\"yaqut-hashiya\">\\s-*<span class=\"yaqut-gloss\">حاشية\\.</span>\\s-*</div>"
                                    "\\s-*<h2[^>]*>عنوان<a")
                            html))
    (should (equal (length (split-string html "class=\"yaqut-hashiya\"")) 2)))
  ;; One gloss for each note that pandoc writes, wherever it stands, so that the margin's count
  ;; follows pandoc's numbers: in a heading, a caption, a table cell and a term.
  (dolist (case (list (list (imprimeur-skin-yaqut-test-doc
                             "" (concat "## عنوان[^1]\n\n![صورة[^2]](a.png)\n\n| أ |\n|---|\n| خلية[^3] |\n\n"
                                        "[^1]: ١.\n[^2]: ٢.\n[^3]: ٣.\n"))
                            3)
                      (list (imprimeur-skin-yaqut-test-html "org" "- مصطلح[fn::٢] :: تعريف[fn::٣]\n") 2)))
    (pcase-let ((`(,html ,notes) case))
      (should (equal (length (split-string html "class=\"footnote-ref\"")) (1+ notes)))
      (should (equal (length (split-string html "class=\"yaqut-gloss\"")) (1+ notes)))))
  (should (string-search "<dt><span class=\"yaqut-hashiya\"><span class=\"yaqut-gloss\">٢</span>"
                         (imprimeur-skin-yaqut-test-html "org" "- مصطلح[fn::٢] :: تعريف[fn::٣]\n"))))

(ert-deftest imprimeur-skin-yaqut-sets-apart-what-is-enclosed-in-ornate-parentheses ()
  (pcase-dolist (`(,text ,want)
                 '(("قال ﴿كتب﴾ ثم" "قال <span class=\"yaqut-quran\">﴿كتب﴾</span> ثم")
                   ("قال ﴿كتب الكاتب﴾. ثم" "قال <span class=\"yaqut-quran\">﴿كتب الكاتب﴾.</span> ثم")
                   ;; A conjunction before the mark goes with it, and a run ends at the first close.
                   ("قال و﴿كتب﴾ ثم" "قال <span class=\"yaqut-quran\">و﴿كتب﴾</span> ثم")
                   ("﴿أ﴾ و﴿ب ﴿ج﴾ د" "<span class=\"yaqut-quran\">﴿أ﴾</span> <span class=\"yaqut-quran\">و﴿ب ﴿ج﴾</span> د")
                   ;; One that never closes stays as it was.
                   ("قال ﴿كتب ثم" "قال ﴿كتب ثم")))
    (ert-info (text)
      (should (string-search (concat "<p>" want "</p>") (imprimeur-skin-yaqut-test-doc "" text))))))

(ert-deftest imprimeur-skin-yaqut-writes-the-title-into-the-headpiece ()
  (let ((html (imprimeur-skin-yaqut-test-html
               "org" "#+TITLE: المقامة <b>\n#+AUTHOR: الحريري\n\nنص.\n")))
    (should (string-match-p (concat "<div class=\"yaqut-unwan\">\n<p class=\"yaqut-unwan-title\">المقامة &lt;b&gt;</p>\n"
                                    "<p class=\"yaqut-author\">الحريري</p>")
                            html)))
  (should-not (string-search "yaqut-unwan" (imprimeur-skin-yaqut-test-html "gfm" "نص.\n"))))

(ert-deftest imprimeur-skin-yaqut-writes-the-same-bytes-each-time ()
  (let ((text (imprimeur-skin-yaqut-test-read "examples/yaqut/golestan.md")))
    (should (equal (imprimeur-skin-yaqut-test-html "gfm+sourcepos" text)
                   (imprimeur-skin-yaqut-test-html "gfm+sourcepos" text)))))

;;;; The samples

(ert-deftest imprimeur-skin-yaqut-samples-hold-what-their-sources-say ()
  (let ((maqama (imprimeur-skin-yaqut-test-read "examples/yaqut/sanaaniyya.org"))
        (golestan (imprimeur-skin-yaqut-test-read "examples/yaqut/golestan.md"))
        (sources (imprimeur-skin-yaqut-test-read "examples/yaqut/SOURCES.md")))
    ;; Passages of Arabic Wikisource's maqama, copied by hand from its page.
    (dolist (passage '("لما اقتعدت غارب"
                       "إلى صنْعاء اليَمَنِ. فدَخَلْتُها خاويَ الوِفاضِ. باديَ الإنْفاضِ. لا أملكُ بُلْغَةً"
                       "وتخْشَى الناسَ واللهُ أحقُّ أنْ تخْشاهُ!"
                       "تباً لطالِـبِ دُنْـيا\nثَنى إلَيها انصِبابَهْ"
                       "فاتّبعْتُهُ مُوارِياً عنْهُ عِياني."
                       "سِراجُ الغُرَباء. وتاجُ الأدَباء. فانصرَفْتُ من حيثُ أتيتُ. وقضَيْتُ العجَبَ ممّا رأيْتُ."))
      (ert-info (passage)
        (should (string-search passage maqama))))
    ;; The notes, each a sentence of an entry of Mukhtar al-Sihah, copied by hand from Wikisource.
    (dolist (gloss '("«(الْغَارِبُ) مَا بَيْنَ السَّنَامِ إِلَى الْعُنُقِ» مختار الصحاح، غرب."
                     "«(الْمَتْرَبَةُ) الْمَسْكَنَةُ وَالْفَاقَةُ» مختار الصحاح، ترب."
                     "«الْجِرَابُ وِعَاءُ الزَّادِ وَالْعَامَّةُ تَفْتَحُهُ» مختار الصحاح، جرب."))
      (ert-info (gloss)
        (should (string-search gloss maqama))))
    ;; Foroughi's text of the Golestan, and a note of his.
    (dolist (passage '("پادشاهی را شنیدم بکشتن اسیری اشارت کرد بیچاره در آن حالت[^1]"
                       "دروغی مصلحت آمیز به که راستی[^7] فتنه‌انگیز"
                       "جهان ای برادر نماند بکس\\\nدل اندر جهان آفرین بند و بس"
                       "[^7]: پا: دروغ مصلحت‌آمیز به از راست."))
      (ert-info (passage)
        (should (string-search passage golestan))))
    (dolist (source '("ar.wikisource.org" "fa.wikisource.org" "مختار الصحاح" "Foroughi" "CC BY-SA 4.0"))
      (should (string-search source sources)))
    (should (string-search "No\nreader of Arabic or Persian has checked them" sources))
    ;; Each names that licence in its first lines, so that a copy of it alone keeps it.
    (dolist (sample (list maqama golestan))
      (should (string-match-p "\\`\\(?:.*\n\\)\\{0,9\\}# SPDX-License-Identifier: CC-BY-SA-4\\.0$" sample)))
    (should (string-match-p "^#\\+LANGUAGE: ar$" maqama))
    (should (string-match-p "^lang: fa$" golestan))))

;;;; The page

(ert-deftest imprimeur-skin-yaqut-keeps-the-core-s-right-to-left-page ()
  (let ((text (concat "---\ntitle: T\nlang: %s\n---\n\n# أول\n\nنص فيه `code` و $x^2$.\n\n"
                      "```\nblock = 1;\n```\n\n## ثان\n\nنص.\n\n## ثالث\n\nنص.\n")))
    (dolist (language '("ar" "fa"))
      (ert-info (language)
        (imprimeur-skin-yaqut-test-with (_buffer browser "doc.md" (format text language))
          (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dir") "rtl"))
          (should (equal (imprimeur-skin-yaqut-test-style browser "main pre" "direction") "ltr"))
          (should (equal (imprimeur-skin-yaqut-test-style browser "main math" "direction") "ltr"))
          (dolist (width '(640 420))
            (ert-info ((number-to-string width))
              (imprimeur-skin-yaqut-test-viewport browser width 900)
              ;; The pill stands at the inline end, which is the left.
              (should (imprimeur-test-cdp-wait browser "(() => {
  const pill = document.querySelector('#imprimeur-minitoc:not([hidden]) > .imprimeur-minitoc-pill');
  if (!pill) return false;
  const box = pill.getBoundingClientRect();
  return Math.round(box.left) === 8 && box.right < innerWidth - 8;
})()"))
              (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-yaqut-test-sideways) 0))))
          (should-not (imprimeur-test-cdp-errors browser)))))))

(ert-deftest imprimeur-skin-yaqut-changes-only-the-colour-of-emphasis-in-arabic ()
  (imprimeur-skin-yaqut-test-with
      (_buffer browser "doc.md" "---\ntitle: T\nlang: ar\n---\n\nنص *مائل* و **غامق** و<em>كلم</em>ة.\n")
    (let ((paragraph (imprimeur-test-cdp-eval browser "(() => {
  const style = getComputedStyle(document.querySelector('main p:has(em)'));
  return [style.fontWeight, style.fontSize, style.fontStyle, style.color];
})()")))
      (dolist (selector '("main p em" "main p strong"))
        (ert-info (selector)
          (should (equal (imprimeur-skin-yaqut-test-style browser selector "fontWeight") (aref paragraph 0)))
          (should (equal (imprimeur-skin-yaqut-test-style browser selector "fontSize") (aref paragraph 1)))
          (should (equal (imprimeur-skin-yaqut-test-style browser selector "fontStyle") (aref paragraph 2)))
          (should-not (equal (imprimeur-skin-yaqut-test-style browser selector "color") (aref paragraph 3)))))
      (should-not (equal (imprimeur-skin-yaqut-test-style browser "main p em" "color")
                         (imprimeur-skin-yaqut-test-style browser "main p strong" "color"))))))

(ert-deftest imprimeur-skin-yaqut-dates-the-colophon-in-the-hijri-calendar ()
  (imprimeur-skin-yaqut-test-with
      (buffer browser "doc.md"
              "---\ntitle: T\nlang: ar\ndate: 2024-10-22\ncolophon: تمت\nseal: ختم\n---\n\nنص.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('time.yaqut-hijri .yaqut-year') !== null")
    ;; 19 Rabi' al-Thani 1446: the day and the year in the page, the month by its number.
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const time = document.querySelector('time.yaqut-hijri');
  const month = new Intl.DateTimeFormat('ar-u-ca-islamic-umalqura-nu-arab', { timeZone: 'UTC', month: 'numeric' })
    .formatToParts(new Date(Date.UTC(2024, 9, 22))).find((part) => part.type === 'month').value;
  const name = new Intl.DateTimeFormat('ar-u-ca-islamic-umalqura-nu-arab', { timeZone: 'UTC', month: 'long' })
    .formatToParts(new Date(Date.UTC(2024, 9, 22))).find((part) => part.type === 'month').value;
  return [month, time.textContent === '١٩ ' + name + ' \\u0601١٤٤٦',
          time.querySelector('.yaqut-year').textContent, time.getAttribute('datetime')];
})()")
                   ["٤" t "\u0601١٤٤٦" "2024-10-22"]))
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const seal = document.querySelector('.yaqut-seal');
  return [seal.getAttribute('role'), seal.getAttribute('aria-label')];
})()")
                   ["img" "ختم"]))
    ;; The tabular civil calendar: the 18th, a day before Umm al-Qura's, by its arithmetic.
    (imprimeur-skin-yaqut-test-choose buffer browser 'calendar "civil")
    (imprimeur-test-cdp-wait browser "document.querySelector('time.yaqut-hijri').dataset.yaqutCalendar === 'civil'")
    (should (string-prefix-p "١٨ " (imprimeur-test-cdp-eval browser "document.querySelector('time.yaqut-hijri').textContent")))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('time.yaqut-hijri .yaqut-year').textContent")
                   "\u0601١٤٤٦"))
    (should-not (imprimeur-test-cdp-errors browser))))

(defconst imprimeur-skin-yaqut-test-glosses
  "(() => {
  const main = document.getElementById('imprimeur-main').getBoundingClientRect();
  const hashiya = document.querySelector('.yaqut-hashiya');
  const box = hashiya.getBoundingClientRect();
  const gloss = getComputedStyle(document.querySelector('.yaqut-gloss'));
  const shown = getComputedStyle(hashiya).display;
  return [shown, shown !== 'none' && box.right <= main.left && box.left >= 0,
          getComputedStyle(document.querySelector('main .footnotes')).display, gloss.transform !== 'none',
          document.documentElement.scrollWidth - document.documentElement.clientWidth];
})()"
  "Where a page shows its glosses: their display, whether they stand in the margin outside the
jadwal, the display of the notes at the foot, whether the glosses slant, and the sideways scroll.")

(ert-deftest imprimeur-skin-yaqut-sets-glosses-in-the-margin-or-at-the-foot ()
  (imprimeur-skin-yaqut-test-with (buffer browser "doc.md" imprimeur-skin-yaqut-test-notes)
    (imprimeur-test-cdp-wait browser "document.querySelector('.yaqut-hashiya') !== null")
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-yaqut-test-glosses) ["block" t "none" nil 0]))
    (imprimeur-skin-yaqut-test-viewport browser 420 900)
    (should (equal (aref (imprimeur-test-cdp-eval browser imprimeur-skin-yaqut-test-glosses) 0) "none"))
    (should (equal (aref (imprimeur-test-cdp-eval browser imprimeur-skin-yaqut-test-glosses) 2) "block"))
    (imprimeur-skin-yaqut-test-viewport browser 640 900)
    (pcase-dolist (`(,id ,value ,want)
                   '((notes "foot" ["none" nil "block" nil 0])
                     (notes "oblique" ["block" t "none" t 0])
                     (notes "margin" ["block" t "none" nil 0])
                     ;; Persian margins slant their glosses, unless chosen otherwise.
                     (preset "persian" ["block" t "none" nil 0])
                     (notes "auto" ["block" t "none" t 0])))
      (ert-info ((format "%s %s" id value))
        (imprimeur-skin-yaqut-test-choose buffer browser id value)
        (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-yaqut-test-glosses) want))))))

(ert-deftest imprimeur-skin-yaqut-leaves-a-heading-its-own-title ()
  ;; A note in a heading has its glosses in the margin, in the space between the block before the
  ;; heading and the heading, and a minitoc's entry reads what pandoc rendered of the heading
  ;; alone: its words and the note's number, by the rules' Titles.
  (pcase-dolist (`(,file ,text)
                 '(("doc.md" "---\ntitle: T\nlang: ar\n---\n\n## عنوان[^1]\n\nنص.\n\n## ثان\n\nنص.\n\n[^1]: حاشية.\n")
                   ("doc.org" "#+TITLE: T\n#+LANGUAGE: ar\n\n* عنوان[fn::حاشية.]\n\nنص.\n\n* ثان\n\nنص.\n")))
    (ert-info (file)
      (imprimeur-skin-yaqut-test-with (_buffer browser file text)
        (imprimeur-test-cdp-wait browser "document.querySelector('.yaqut-hashiya') !== null")
        (imprimeur-test-cdp-eval browser "document.querySelector('.imprimeur-minitoc-popover').hidden = false")
        (should (equal (imprimeur-test-cdp-eval
                        browser "[...document.querySelectorAll('.imprimeur-minitoc-popover li button')].map((row) => row.textContent)")
                       ["عنوان1" "ثان"]))
        ;; A rosette opens each heading but the first, which its glosses leave the first.
        (should (equal (imprimeur-test-cdp-eval
                        browser "[...document.querySelectorAll('main h1, main h2')].map((heading) => getComputedStyle(heading, '::before').content === '\"\"')")
                       [nil t]))
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const main = document.getElementById('imprimeur-main').getBoundingClientRect();
  const hashiya = document.querySelector('.yaqut-hashiya');
  const box = hashiya.getBoundingClientRect();
  return [box.right <= main.left, box.top >= hashiya.previousElementSibling.getBoundingClientRect().bottom,
          box.top <= hashiya.nextElementSibling.getBoundingClientRect().top,
          hashiya.nextElementSibling.matches('h1, h2')];
})()")
                       [t t t t]))
        (should-not (imprimeur-test-cdp-errors browser))))))

(ert-deftest imprimeur-skin-yaqut-gives-each-preset-its-faces ()
  (imprimeur-skin-yaqut-test-with (buffer browser "doc.md" imprimeur-skin-yaqut-test-notes)
    (imprimeur-test-cdp-wait browser "document.querySelector('.yaqut-unwan-title') !== null")
    (should (equal (imprimeur-skin-yaqut-test-family browser "main p:not([class])") "Amiri"))
    (should (equal (imprimeur-skin-yaqut-test-family browser ".yaqut-unwan-title") "Katibeh"))
    (should (equal (imprimeur-skin-yaqut-test-family browser "main h1") "Katibeh"))
    ;; Mamluk headings are rubrics, in the vermilion of emphasis, on the ground.
    (should (equal (imprimeur-skin-yaqut-test-style browser "main h1" "backgroundColor") "rgba(0, 0, 0, 0)"))
    (pcase-dolist (`(,value ,family)
                   '(("kufi" "Qahiri") ("raqq" "Raqq") ("thuluth" "Katibeh")))
      (ert-info (value)
        (imprimeur-skin-yaqut-test-choose buffer browser 'title value)
        (should (equal (imprimeur-skin-yaqut-test-family browser ".yaqut-unwan-title") family))))
    (imprimeur-skin-yaqut-test-choose buffer browser 'title "auto")
    ;; Persian: Naskh for an Arabic document, white Nastaliq on lapis above.
    (imprimeur-skin-yaqut-test-choose buffer browser 'preset "persian")
    (should (equal (imprimeur-skin-yaqut-test-family browser "main p:not([class])") "Amiri"))
    (should (equal (imprimeur-skin-yaqut-test-family browser ".yaqut-unwan-title") "Noto Nastaliq Urdu"))
    (should (equal (imprimeur-skin-yaqut-test-style browser "main h1" "color") "rgb(255, 255, 255)"))
    (should (equal (imprimeur-skin-yaqut-test-style browser "main h1" "backgroundColor") "rgb(35, 64, 142)")))
  (imprimeur-skin-yaqut-test-with
      (buffer browser "doc.md" "---\ntitle: T\nlang: fa\n---\n\nمتن[^1] و <span lang=\"ar\">نص</span>.\n\n[^1]: یادداشت.\n")
    (should (equal (imprimeur-skin-yaqut-test-family browser "main p:not([class])") "Amiri"))
    (imprimeur-skin-yaqut-test-choose buffer browser 'preset "persian")
    ;; Persian in Nastaliq, its glosses too, and Arabic within it in Naskh.
    (should (equal (imprimeur-skin-yaqut-test-family browser "main p:not([class])") "Noto Nastaliq Urdu"))
    (should (equal (imprimeur-skin-yaqut-test-family browser ".yaqut-hashiya") "Noto Nastaliq Urdu"))
    (should (equal (imprimeur-skin-yaqut-test-family browser "main span[lang=ar]") "Amiri"))))

(ert-deftest imprimeur-skin-yaqut-sets-the-colophon-as-a-triangle ()
  (imprimeur-skin-yaqut-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: T\nlang: ar\ncolophon: "
                       (mapconcat #'identity (make-list 14 "تمت المقامة بحمد الله") " ")
                       "\n---\n\nنص.\n"))
    (dolist (width '(640 420))
      (ert-info ((number-to-string width))
        (imprimeur-skin-yaqut-test-viewport browser width 900)
        (let ((lines (imprimeur-test-cdp-wait browser "(() => {
  const text = document.querySelector('.yaqut-colophon-text');
  if (!text.style.getPropertyValue('--yaqut-colophon-lines')) return false;
  const range = document.createRange();
  range.selectNodeContents(text.lastChild);
  const lines = new Map();
  for (const rect of range.getClientRects()) {
    if (rect.width < 1) continue;
    const top = Math.round(rect.top);
    const [left, right] = lines.get(top) ?? [Infinity, -Infinity];
    lines.set(top, [Math.min(left, rect.left), Math.max(right, rect.right)]);
  }
  const box = text.getBoundingClientRect();
  return [[...lines.entries()].sort((a, b) => a[0] - b[0]).map(([, [left, right]]) => Math.round(right - left)),
          Math.round(box.bottom - range.getBoundingClientRect().bottom)];
})()")))
          ;; Lines that narrow to the apex, and a block that ends with the last.
          (let ((widths (append (aref lines 0) nil)))
            (should (>= (length widths) 3))
            (should (equal widths (sort (copy-sequence widths) #'>=)))
            (should (< (car (last widths)) (* 0.6 (car widths)))))
          (should (<= (abs (aref lines 1)) 1)))))))

(ert-deftest imprimeur-skin-yaqut-sets-both-samples-without-sideways-scroll ()
  (pcase-dolist (`(,file ,preset)
                 '(("sanaaniyya.org" "mamluk") ("golestan.md" "persian")))
    (ert-info (file)
      (imprimeur-skin-yaqut-test-with
          (buffer browser file (imprimeur-skin-yaqut-test-read (concat "examples/yaqut/" file)))
        (imprimeur-skin-yaqut-test-choose buffer browser 'preset preset)
        (imprimeur-test-cdp-wait browser "document.querySelector('time.yaqut-hijri .yaqut-year') !== null")
        (should (string-prefix-p "\u0601" (imprimeur-test-cdp-eval browser "document.querySelector('.yaqut-year').textContent")))
        (dolist (width '(640 420))
          (ert-info ((number-to-string width))
            (imprimeur-skin-yaqut-test-viewport browser width 900)
            (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-yaqut-test-sideways) 0))))
        (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-banner').textContent") ""))
        (should-not (imprimeur-test-cdp-errors browser))))))

(ert-deftest imprimeur-skin-yaqut-leaves-nothing-after-a-swap ()
  (imprimeur-skin-yaqut-test-with
      (buffer browser "doc.md"
              "---\ntitle: T\nlang: ar\ndate: 2024-10-22\ncolophon: تمت المقامة\n---\n\nنص[^1].\n\n[^1]: حاشية.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('time.yaqut-hijri .yaqut-year') !== null")
    (imprimeur-skin-yaqut-test-choose buffer browser 'calendar "civil")
    (with-current-buffer buffer (imprimeur-choose-skin "base"))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.skin === 'base'")
    (imprimeur-test-cdp-wait
     browser "document.querySelectorAll('[class*=\"yaqut\"], [style*=\"yaqut\"], [data-yaqut-calendar]').length === 0")
    (should-not (imprimeur-test-cdp-eval
                 browser "[...document.documentElement.attributes].some((attribute) => attribute.name.startsWith('data-yaqut'))"))
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-banner').textContent") ""))))

(ert-deftest imprimeur-skin-yaqut-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (imprimeur-skin-yaqut-test-read "imprimeur-skin-yaqut/README.md"))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'yaqut\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-yaqut-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-yaqut)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"yaqut\" (imprimeur-skin-get \"yaqut\") (imprimeur-skin-configured \"yaqut\" (imprimeur-skin-get \"yaqut\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "yaqut[]" (cdr result)))))

(ert-deftest imprimeur-skin-yaqut-sheet-keeps-to-its-names ()
  (let ((sheet (replace-regexp-in-string
                "/\\*\\(?:.\\|\n\\)*?\\*/\\|url(\"[^\"]*\")" ""
                (imprimeur-skin-yaqut-test-read "imprimeur-skin-yaqut/assets/skin.css")))
        (start 0))
    (while (string-match "\\.\\([a-z][a-z-]*\\)[ ,:{)>+]" sheet start)
      (setq start (match-end 0))
      (let ((class (match-string 1 sheet)))
        (ert-info (class)
          ;; What belongs to pandoc keeps its name, and the skin's its own.
          (should (or (string-prefix-p "yaqut-" class)
                      (member class '("footnotes" "footnote-ref")))))))))

;;; imprimeur-skin-yaqut-test.el ends here

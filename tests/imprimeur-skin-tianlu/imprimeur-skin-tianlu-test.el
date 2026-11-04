;;; imprimeur-skin-tianlu-test.el --- Tests of the skin Tianlu  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 025:
;;
;; "A Song block-print page in vertical text, in multicolumn bands that still scroll down":
;; the manifest's choices and defaults, by hand from docs/work/planned/skin-defaults.md and
;; the workbench's params.json: preset (song, juzhen, siku), face (auto, moe, kai, ming, fang).
;;
;; Acceptance 2: on real pandoc, a traditional and a simplified document in vertical-rl bands,
;; no line off the grid, no sideways scroll at 640 and 420 CSS px; code, Mermaid, pictures and
;; tables as horizontal plates.  Here in Chromium; WebKit is run apart, as no test opens a
;; desktop window.  Acceptance 3: each option changes what it says, alone; scroll sync and a
;; double-click still find the source's line.  Acceptance 5: the filter is within 10.
;;
;; What the skin decides, by the reports of its trial and plan 017, which reads them: the
;; Ministry's Song is the traditional default, down to a grid of 19 px; a simplified document
;; keeps a mainland face; zh-CN, zh-Hans and zh-SG are simplified, and any other zh traditional;
;; a filter's Chinese passes run under zh alone, and walk no metadata.  The licence: fonts.nix
;; holds the Ministry's fonts whole, marks them cc-by-nd-30 and credits 中華民國教育部, and no font
;; file is tracked.  The samples hold neither the word for the island, nor a flag, nor an era's
;; date, by docs/work/planned/chinese-readme-and-gallery.md.
;;
;; The tests register Tianlu in a registry of their own, as the other tests see the plain page alone.
;; make check's fonts are DejaVu at most, so a page test reads computed values and boxes, never a
;; face drawn.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-tianlu-test-file
  (expand-file-name "imprimeur-skin-tianlu/imprimeur-skin-tianlu.el" repo-test-root)
  "The skin's main file.")

(defconst imprimeur-skin-tianlu-test-sheet
  (expand-file-name "imprimeur-skin-tianlu/assets/skin.css" repo-test-root)
  "The skin's sheet.")

(defconst imprimeur-skin-tianlu-test-examples
  (expand-file-name "examples/tianlu" repo-test-root)
  "The directory of the two samples.")

(defun imprimeur-skin-tianlu-test-read (file)
  "Return the text of FILE, under the repository's root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file repo-test-root))
    (buffer-string)))

(defun imprimeur-skin-tianlu-test-html (reader text)
  "Return the HTML that Tianlu's chain writes from TEXT in READER, on real pandoc."
  (let ((pandoc (imprimeur-test-require "pandoc"))
        (imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-tianlu-test-file nil t)
    (with-temp-buffer
      (insert text)
      (should (equal (apply #'call-process-region (point-min) (point-max) pandoc t t nil
                            (imprimeur-render-arguments reader nil nil "python,bash"
                                                        (imprimeur-skin-get "tianlu")))
                     0))
      (buffer-string))))

(defun imprimeur-skin-tianlu-test-doc (lang body)
  "Return a Markdown document in LANG, whose title is T, holding BODY, as HTML."
  (imprimeur-skin-tianlu-test-html
   "gfm+sourcepos" (format "---\ntitle: T\nlang: %s\n---\n\n%s\n" lang body)))

(defun imprimeur-skin-tianlu-test-count (regexp string)
  "Return how many matches of REGEXP STRING holds."
  (let ((start 0) (count 0))
    (while (string-match regexp string start)
      (setq start (match-end 0) count (1+ count)))
    count))

(defmacro imprimeur-skin-tianlu-test-with (spec &rest body)
  "Run BODY with Tianlu as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in the
selected Emacs window, in `imprimeur-mode'; BROWSER shows its page, at 640 by 900."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'tianlu)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (progn
                         ;; What the samples show, beside whichever document this is.
                         (dolist (media '("plate-shuixian.svg" "plate-zipan.svg" "yuhou.webm" "zhuanlun.webm"))
                           (copy-file (expand-file-name media imprimeur-skin-tianlu-test-examples) root))
                         ;; The showcase's woodcut, at the path that the document names from its own place.
                         (make-directory (expand-file-name "docs/images" root) t)
                         (copy-file (expand-file-name "../../docs/images/printer-1568.png"
                                                      imprimeur-skin-tianlu-test-examples)
                                    (expand-file-name "docs/images/" root))
                         (find-file-noselect (expand-file-name ,file root)))))
         (load imprimeur-skin-tianlu-test-file nil t)
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-mode 1)
                 (imprimeur-skin-tianlu-test-viewport ,browser 640 900)
                 (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
                 (imprimeur-test-wait-for
                  (lambda () (imprimeur-test-cdp-eval ,browser "document.documentElement.dataset.revision")))
                 (imprimeur-test-cdp-wait ,browser "document.querySelector('.tianlu-folds') !== null")
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defconst imprimeur-skin-tianlu-test-paragraph "main p:not(.tianlu-title, .tianlu-author)"
  "A paragraph of the text, and not of the title block.")

(defun imprimeur-skin-tianlu-test-viewport (browser width height)
  "Give BROWSER's page a viewport of WIDTH by HEIGHT CSS px, and let it lay out."
  (imprimeur-test-cdp-call browser "Emulation.setDeviceMetricsOverride"
                           `(:width ,width :height ,height :deviceScaleFactor 1 :mobile :false))
  (imprimeur-test-cdp-wait browser (format "window.innerWidth === %d && window.innerHeight === %d" width height))
  (accept-process-output nil 0.1))

(defun imprimeur-skin-tianlu-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-tianlu-%s') === %s"
                   id (if (member value '("song" "auto")) "null" (format "%S" value)))))

(defun imprimeur-skin-tianlu-test-face (browser)
  "Return the first family of the text in BROWSER's page, without its quotes."
  (string-trim
   (imprimeur-test-cdp-eval browser (format "getComputedStyle(document.querySelector(%S)).fontFamily.split(',')[0]"
                                            imprimeur-skin-tianlu-test-paragraph))
   "\"" "\""))

(defun imprimeur-skin-tianlu-test-size (browser)
  "Return the size of the text in BROWSER's page, in px."
  (imprimeur-test-cdp-eval browser (format "parseFloat(getComputedStyle(document.querySelector(%S)).fontSize)"
                                           imprimeur-skin-tianlu-test-paragraph)))

(defconst imprimeur-skin-tianlu-test-grid
  "(() => {
  const main = document.getElementById('imprimeur-main');
  const pitch = parseFloat(getComputedStyle(main).lineHeight);
  const right = main.getBoundingClientRect().right;
  const walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  let lines = 0;
  const off = [];
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const skipped = '.tianlu-slot, pre, math, .tianlu-headnote, .tianlu-note, .tianlu-seal, rt, .tianlu-imath, .tianlu-title, .tianlu-colophon';
    if (!node.textContent.trim() || node.parentElement.closest(skipped)) continue;
    range.selectNodeContents(node);
    for (const rect of range.getClientRects()) {
      if (rect.width < 2) continue;
      lines += 1;
      const phase = (((right - (rect.left + rect.right) / 2) / pitch) % 1 + 1) % 1;
      if (Math.abs(phase - 0.5) * pitch > 1.01) off.push(node.textContent.slice(0, 8));
    }
  }
  const root = document.documentElement;
  return { lines, off: off.join(' '), sideways: root.scrollWidth - root.clientWidth, mode: getComputedStyle(main).writingMode };
})()"
  "What BROWSER's page shows of its grid: how many lines of text it holds, those further than a
pixel from a column's centre, how far it scrolls sideways, and its writing mode.")

(defun imprimeur-skin-tianlu-test-on-the-grid (browser &optional lines)
  "Check that BROWSER's page runs in vertical bands, on its grid, with no sideways scroll.
It must hold more than LINES lines, by default 20, so that the grid is put to the test."
  (let ((grid (imprimeur-test-cdp-eval browser imprimeur-skin-tianlu-test-grid)))
    (should (equal (plist-get grid :mode) "vertical-rl"))
    (should (> (plist-get grid :lines) (or lines 20)))
    (should (equal (plist-get grid :off) ""))
    (should (equal (plist-get grid :sideways) 0))))

(defconst imprimeur-skin-tianlu-test-plates
  "[...document.querySelectorAll('main .tianlu-slot > *')].map((plate) => [
  plate.matches('figure') ? 'figure' : plate.matches('table') ? 'table' : plate.querySelector('pre.mermaid') || plate.matches('pre.mermaid') ? 'diagram' : plate.matches('.tianlu-math') ? 'math' : plate.matches('.tianlu-code') ? 'code' : plate.tagName,
  getComputedStyle(plate).writingMode])"
  "Each plate of a page: what it holds, and its writing mode.")

(defconst imprimeur-skin-tianlu-test-mixed
  (concat "---\ntitle: 試排\nauthor: 某甲\nlang: zh-TW\n---\n\n"
          "# 第一\n\n"
          (mapconcat (lambda (n) (format "第%d段，%s。\n\n" n (apply #'concat (make-list 12 "舊宅在巷底，門內一方小庭")))) (number-sequence 1 6) "")
          "| 甲 | 乙 |\n|---|---|\n| 一 | 二 |\n\n"
          "```python\nprint(1)\n```\n\n"
          "```\nplain\n  lines\n```\n\n"
          "| 碑帖 | 書者 | 年代 | 西元 | 現存 |\n|---|---|---|---|---|\n| 九成宮醴泉銘 | 歐陽詢 | 唐貞觀六年 | 632 | 陝西麟遊 |\n\n"
          "末段文字，並引 Latin words 與 12 字，及 [連結](https://example.invalid/) 一處。\n")
  "A traditional document in Markdown, with prose, a tall and a wide table, and code.")

;;;; The package

(ert-deftest imprimeur-skin-tianlu-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-tianlu-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-tianlu-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-tianlu)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S\" (and (imprimeur-skin-get \"tianlu\") t)))"))))
    (should (equal (car result) 0))
    (should (string-match-p "MARK\\(.\\|\n\\)*before=nil after=t\\'" (cdr result)))))

(ert-deftest imprimeur-skin-tianlu-keeps-every-choice ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-tianlu-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "tianlu"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "Tianlu"))
      (should (plist-get manifest :smart))
      (should (equal (plist-get manifest :module) "page.mjs"))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((preset "song" "song" "juzhen" "siku")
                       (face "auto" "auto" "moe" "kai" "ming" "fang")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(preset face))))))

(ert-deftest imprimeur-skin-tianlu-filter-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "imprimeur-skin-tianlu/assets/filter.lua" repo-test-root))
                   0))))

(ert-deftest imprimeur-skin-tianlu-installs-the-ministry-s-fonts-whole-and-credits-them ()
  (let ((fonts (imprimeur-skin-tianlu-test-read "imprimeur-skin-tianlu/fonts.nix"))
        (readme (imprimeur-skin-tianlu-test-read "imprimeur-skin-tianlu/README.md")))
    (should (string-search "cc-by-nd-30" fonts))
    (dolist (text (list fonts readme))
      (should (string-search "中華民國教育部" text))
      (should (string-search "creativecommons.org/licenses/by-nd/3.0/tw/" text)))
    ;; Nothing that would derive a font from another, and no other way to a font.
    (should-not (string-match-p "instancer\\|pyftsubset\\|subset\\|fontforge\\|fonttools\\|woff2\\|ttx" fonts))
    (should-not (string-search "google-fonts" fonts))
    ;; The sheet names installed fonts alone.
    (let ((sheet (imprimeur-skin-tianlu-test-read "imprimeur-skin-tianlu/assets/skin.css")))
      (should (equal (imprimeur-skin-tianlu-test-count "@font-face" sheet) 2))
      (should (equal (imprimeur-skin-tianlu-test-count "src: local(" sheet) 2))
      (should-not (string-search "url(" (replace-regexp-in-string "url(\"data:image[^\"]*\")" "" sheet))))
    ;; No font file enters the repository.
    (should-not (string-match-p
                 "\\.\\(?:ttf\\|otf\\|ttc\\|woff2?\\|eot\\)$"
                 (cdr (repo-test-run "git" (list "ls-files") nil repo-test-root))))))

(ert-deftest imprimeur-skin-tianlu-leaves-out-of-the-kai-what-is-not-one-em ()
  ;; The 161 code points whose advance in the Ministry's Kai 5.1 is not 1 em, by hand from its
  ;; vmtx table as plan 017 read it: the sheet's range covers none of them and all the others.
  (let* ((sheet (imprimeur-skin-tianlu-test-read "imprimeur-skin-tianlu/assets/skin.css"))
         (range (progn (string-match "tianlu-moe-kai\"[^}]*unicode-range: \\([^;]*\\);" sheet)
                       (match-string 1 sheet)))
         (kept (mapcar (lambda (item)
                         (let ((ends (split-string (string-remove-prefix "U+" (string-trim item)) "-")))
                           (cons (string-to-number (car ends) 16)
                                 (string-to-number (car (last ends)) 16))))
                       (split-string range ",")))
         (han (string-to-list "榐欗湊湋湍湎湑湒湓湔湕湖湘湚湛湜湝湞湟湠湡湢湣湤湥湦湧湨湩湫湮湯湱澥猁硤笞蛃蟦諏辯蘠"))
         (signs (append (number-sequence #x2522 #x254B) (number-sequence #x2550 #x2574)
                        (number-sequence #x2581 #x258F) (number-sequence #x2593 #x2595)
                        '(#x25A0 #x25A1 #x25B2 #x25B3 #x25BC #x25BD #x25C6 #x25C7 #x25CB #x25CE #x25CF
                                 #x25E2 #x25E3 #x25E4 #x25E5 #x2605 #x2606 #x2609 #x2640 #x2641 #x2642 #xFF22)))
         (out (sort (append han signs) #'<)))
    (should (equal (length out) 161))
    ;; The ranges in order, with the gaps between them exactly those.
    (let ((next 0) (gaps nil))
      (pcase-dolist (`(,from . ,to) kept)
        (when (> from next) (setq gaps (append gaps (number-sequence next (1- from)))))
        (setq next (1+ to)))
      (should (equal next #x110000))
      (should (equal gaps out)))))

;;;; The filter

(ert-deftest imprimeur-skin-tianlu-turns-quotation-marks-by-the-script ()
  (pcase-dolist (`(,lang ,text ,want)
                 '(("zh-CN" "前“后”中" "前『后』中")
                   ("zh-Hans" "前“后”中" "前『后』中")
                   ("zh-SG" "前“后”中" "前『后』中")
                   ;; A language's case means nothing.
                   ("zh-cn" "前“后”中" "前『后』中")
                   ("zh-hans" "前“后”中" "前『后』中")
                   ("ZH-TW" "前“后”中" "前「后」中")
                   ("zh-TW" "前“后”中" "前「后」中")
                   ("zh" "前“后”中" "前「后」中")
                   ("zh-Hant" "前“后”中" "前「后」中")
                   ("zh-CN" "甲‘乙’丙" "甲「乙」丙")
                   ("zh-TW" "甲‘乙’丙" "甲『乙』丙")
                   ;; +smart gives the same mark twice beside Han, so they alternate.
                   ("zh-TW" "甲“丁“乙" "甲「丁」乙")
                   ("zh-TW" "甲\"丁\"乙" "甲「丁」乙")
                   ("zh-TW" "Don’t" "Don’t")))
    (ert-info ((format "%s %s" lang text))
      (should (string-search want (imprimeur-skin-tianlu-test-doc lang text)))))
  ;; Zhuang is no Chinese.
  (should (string-search "前“后”中" (imprimeur-skin-tianlu-test-doc "zha" "前“后”中")))
  ;; A title's marks stay as written, for no pass walks the metadata.
  (let ((html (imprimeur-skin-tianlu-test-html "gfm" "---\ntitle: 甲“乙”丙\nlang: zh-TW\n---\n\n文\n")))
    (should (string-search "\"title\":\"甲“乙”丙\"" html))))

(ert-deftest imprimeur-skin-tianlu-sets-latin-digits-and-spaces-in-chinese-alone ()
  (let ((html (imprimeur-skin-tianlu-test-doc "zh-TW" "在 Emacs 中，第 12 頁，Latin words 同。……")))
    (should (string-search "在<span class=\"tianlu-lat\">Emacs</span>中" html))
    (should (string-search "第<span class=\"tianlu-tcy\">12</span>頁" html))
    (should (string-search "<span class=\"tianlu-lat\">Latin words</span>同" html))
    (should (equal (imprimeur-skin-tianlu-test-count "class=\"tianlu-ell\"" html) 2)))
  ;; A link of Latin alone takes the class itself, a bare address too, and a Chinese one neither.
  (let ((html (imprimeur-skin-tianlu-test-doc "zh-TW" "甲[Emacs](https://example.invalid/)乙[連結](https://example.invalid/)丙 https://example.invalid/a-b 丁")))
    (should (string-match-p "<a href=\"https://example.invalid/\" class=\"tianlu-lat\"[^>]*>Emacs</a>" html))
    (should (string-match-p "<a href=\"https://example.invalid/\" data-pos=\"[^\"]*\">連結</a>" html))
    (should (string-match-p "<a href=\"https://example.invalid/a-b\"[^>]*class=\"[^\"]*tianlu-lat\"[^>]*>https:" html))
    (should-not (string-search "<span class=\"tianlu-lat\">https" html)))
  ;; A document in another language takes the page and none of the Chinese passes.
  (let ((html (imprimeur-skin-tianlu-test-doc "en" "In Emacs, page 12[^1] and “quotes”…\n\n[^1]: A note.")))
    (should-not (string-match-p "tianlu-\\(?:lat\\|tcy\\|ell\\|note\\)" html))
    (should (string-search "“quotes”" html))))

(ert-deftest imprimeur-skin-tianlu-sets-notes-in-place-in-boxes ()
  ;; A note in place, in boxes of at most 40 cells and a little over, keeping every character,
  ;; its link and its code.
  (let* ((note (apply #'concat (make-list 11 "一二三四五六七八九十")))
         (html (imprimeur-skin-tianlu-test-doc
                "zh-TW" (format "文[^1]字\n\n[^1]: %s[鏈](https://example.invalid/)`c`。" note)))
         (cells (let ((start 0) found)
                  (while (string-match "tianlu-note-cells:\\([0-9]+\\)" html start)
                    (setq start (match-end 0))
                    (push (string-to-number (match-string 1 html)) found))
                  found)))
    (should (>= (length cells) 3))
    (should (seq-every-p (lambda (n) (<= n 44)) cells))
    (should (equal (replace-regexp-in-string "<[^>]+>" "" (progn (string-match "文\\(.*\\)字" html) (match-string 1 html)))
                   (concat note "鏈c。")))
    (should (string-search "<a href=\"https://example.invalid/\"" html))
    (should (string-match-p "<code[^>]*>c</code>" html))
    (should-not (string-search "footnote" html))))

(ert-deftest imprimeur-skin-tianlu-keeps-the-words-of-any-block-in-a-note ()
  ;; A document may hold any block in a note, and a render must not fail for it.
  (pcase-dolist (`(,block ,words)
                 '(("> 引文一句" "引文一句")
                   ("```\n    code plain\n    ```" "code plain")
                   ("- 一項\n    - 二項" "一項")
                   ("$$x$$" "x")
                   ("![圖注](a.png)" "圖注")))
    (ert-info (block)
      (let ((html (imprimeur-skin-tianlu-test-doc
                   "zh-TW" (format "文[^1]字\n\n[^1]: 前句。\n\n    %s" block))))
        (should (string-search "tianlu-note" html))
        (should (string-search words html)))))
  (let ((html (imprimeur-skin-tianlu-test-html
               "org" "#+LANGUAGE: zh-TW\n\n文[fn:1]字\n\n[fn:1] 前句。\n#+begin_src python\nprint(1)\n#+end_src\n")))
    (should (string-search "tianlu-note" html))
    (should (string-search "print" html)))
  ;; A headnote of Markdown that is no paragraph stays what it was, a block of its own.
  (should (imprimeur-skin-tianlu-test-doc "zh-TW" "<div class=\"headnote\">- 一項</div>\n\n正文。")))

(ert-deftest imprimeur-skin-tianlu-names-an-alert-in-the-document-s-script ()
  (pcase-dolist (`(,lang ,kind ,word)
                 '(("zh-TW" "NOTE" "按") ("zh-TW" "CAUTION" "慎之") ("zh-TW" "IMPORTANT" "要旨")
                   ("zh-CN" "NOTE" "注") ("zh-CN" "CAUTION" "警告") ("zh-CN" "IMPORTANT" "重要")))
    (ert-info ((format "%s %s" lang kind))
      (should (string-search (format "<p>%s</p>" word)
                             (imprimeur-skin-tianlu-test-doc lang (format "> [!%s]\n> 文。" kind))))))
  ;; Another language keeps pandoc's own word.
  (should (string-search "Note" (imprimeur-skin-tianlu-test-doc "en" "> [!NOTE]\n> Words."))))

(ert-deftest imprimeur-skin-tianlu-gives-a-zhuyin-gloss-what-the-sheet-draws ()
  (pcase-dolist (`(,reader ,text)
                 '(("org" "#+LANGUAGE: zh-TW\n\n文@@html:<ruby>帖<rt>ㄊㄧㄝˋ</rt></ruby>@@字\n")
                   ("gfm" "---\nlang: zh-TW\n---\n\n文<ruby>帖<rt>ㄊㄧㄝˋ</rt></ruby>字\n")))
    (ert-info (reader)
      (let ((html (imprimeur-skin-tianlu-test-html reader text)))
        (should (string-search "data-tianlu-zhuyin=\"ㄊㄧㄝ\"" html))
        (should (string-search "data-tianlu-tone=\"ˋ\"" html))
        (should (string-search "--tianlu-zhuyin-count:3" html))
        (should-not (string-search "tianlu-lat" html)))))
  ;; A neutral tone's dot stays in the stack, and another annotation is left alone.
  (let ((html (imprimeur-skin-tianlu-test-doc "zh-TW" "文<ruby>的<rt>˙ㄉㄜ</rt></ruby>字")))
    (should (string-search "data-tianlu-zhuyin=\"˙ㄉㄜ\" data-tianlu-tone=\"\"" html)))
  (let ((html (imprimeur-skin-tianlu-test-doc "zh-CN" "文<ruby>帖<rt>tiè</rt></ruby>字")))
    (should-not (string-search "data-tianlu-zhuyin" html))))

(ert-deftest imprimeur-skin-tianlu-closes-each-juan-with-its-number ()
  (should (string-search "T卷第一終" (imprimeur-skin-tianlu-test-doc "zh-TW" "# 甲\n\n文\n\n# 乙\n\n文")))
  (should (string-search "T卷第一终" (imprimeur-skin-tianlu-test-doc "zh-CN" "# 甲\n\n文\n\n# 乙\n\n文")))
  ;; Each numeral through an end title, by hand: a document of that many first-level headings.
  (let ((html (imprimeur-skin-tianlu-test-doc
               "zh-TW" (mapconcat (lambda (n) (format "# 卷%d\n\n文" n)) (number-sequence 1 112) "\n\n"))))
    (dolist (numeral '("九" "十" "十一" "二十" "九十九" "一百" "一百零一" "一百一十" "一百一十二"))
      (ert-info (numeral)
        (should (string-search (concat "T卷第" numeral "終") html))))))

(ert-deftest imprimeur-skin-tianlu-dates-a-colophon-only-by-a-year-of-the-cycle ()
  (pcase-dolist (`(,lunar ,want)
                 '(("丙午九月二十三日" "歲次丙午九月二十三日")
                   ("乙巳十二月十四日" "歲次乙巳十二月十四日")
                   ("十二月十四日" nil)
                   ;; 甲 and 丑 are of different parity, so no year of the sixty.
                   ("甲丑十二月十四日" nil)
                   ;; A year needs a date after it.
                   ("丙午" nil)))
    (ert-info (lunar)
      (let ((html (imprimeur-skin-tianlu-test-html
                   "gfm" (format "---\ntitle: T\nlang: zh-TW\ncolophon: 某本\nlunar: %s\n---\n\n文\n" lunar))))
        (should (string-search "某本" html))
        (if want
            (should (string-search want html))
          (should-not (string-search "歲次" html))))))
  (should (string-search "岁次丙午" (imprimeur-skin-tianlu-test-html
                                  "gfm" "---\ntitle: T\nlang: zh-CN\ncolophon: 某本\nlunar: 丙午九月\n---\n\n文\n"))))

(ert-deftest imprimeur-skin-tianlu-takes-its-keys-from-org-and-markdown-alike ()
  (let ((org (imprimeur-skin-tianlu-test-html
              "org" "#+TITLE: T\n#+SEAL: 青田\n#+ENDSEAL: 庭\n#+COLOPHON: 某本\n#+NOPE: 不取\n\n文\n"))
        (gfm (imprimeur-skin-tianlu-test-html
              "gfm" "---\ntitle: T\nseal: 青田\nendseal: 庭\ncolophon: 某本\n---\n\n文\n")))
    (dolist (html (list org gfm))
      (should (string-search "aria-label=\"青田\"" html))
      (should (string-search "aria-label=\"庭\"" html))
      (should (string-search "某本" html)))
    (should-not (string-search "不取" org)))
  ;; A document's words reach attributes and markup as text.
  (let ((html (imprimeur-skin-tianlu-test-html
               "gfm" "---\ntitle: T\nseal: \"<img src=x>\"\n---\n\n文\n")))
    (should-not (string-search "<img src=x>" html))))

(ert-deftest imprimeur-skin-tianlu-moves-a-headnote-into-its-paragraph ()
  (pcase-dolist (`(,reader ,text)
                 '(("org" "#+begin_headnote\n沈括，字存中。\n#+end_headnote\n\n正文。\n")
                   ("gfm+sourcepos" "<div class=\"headnote\">沈括，字存中。</div>\n\n正文。\n")))
    (ert-info (reader)
      (let ((html (imprimeur-skin-tianlu-test-html reader text)))
        (should (string-match-p "<p><span class=\"tianlu-headnote\">沈括，字存中。</span>正文" html))))))

(ert-deftest imprimeur-skin-tianlu-makes-plates-of-what-cannot-stand-in-a-column ()
  ;; Code, cut every 18 lines, keeping its line and language on the first piece alone.
  (let* ((lines (mapconcat (lambda (n) (format "line %d" n)) (number-sequence 1 40) "\n"))
         (html (imprimeur-skin-tianlu-test-html
                "gfm+sourcepos" (format "---\nlang: zh-TW\n---\n\n```klingon\n%s\n```\n" lines))))
    (should (equal (imprimeur-skin-tianlu-test-count "tianlu-plate tianlu-code" html) 3))
    (should (equal (imprimeur-skin-tianlu-test-count "tianlu-code-columns:7" html) 3))
    (should (equal (imprimeur-skin-tianlu-test-count "data-pos=" html) 1))
    (should (equal (imprimeur-skin-tianlu-test-count "data-language=\"klingon\"" html) 3)))
  ;; One with no language too, in the place of common's div.imprimeur-code.
  (let ((html (imprimeur-skin-tianlu-test-doc "zh-TW" "```\nplain\n```")))
    (should (string-search "<div class=\"tianlu-slot\"" html))
    (should-not (string-search "imprimeur-code" html)))
  ;; A table by its width in cells.
  (let ((wide (imprimeur-skin-tianlu-test-doc "zh-TW" "| 一二三四五六七八九 | 一二三四五六七八 |\n|---|---|\n| 甲 | 乙 |"))
        (tall (imprimeur-skin-tianlu-test-doc "zh-TW" "| 甲甲 | 乙 |\n|---|---|\n| 丙 | 丁丁丁 |")))
    (should (string-search "tianlu-wide" wide))
    (should (string-search "tianlu-slot" wide))
    (should (string-search "tianlu-tall" tall))
    (should-not (string-search "tianlu-slot" tall))
    (should (string-search "--tianlu-cells:2" tall))
    (should (string-search "--tianlu-cells:3" tall)))
  ;; Each caption in its script, in the shape the sheet reads.
  (should (string-search "captioned-content"
                         (imprimeur-skin-tianlu-test-doc "zh-CN" "```mermaid\npie\n  \"甲\" : 1\n```\n\n图：一幅图。")))
  (should (string-search "captioned-content"
                         (imprimeur-skin-tianlu-test-doc "zh-TW" "```mermaid\npie\n  \"甲\" : 1\n```\n\n圖：一幅圖。")))
  (should (string-search "<caption>"
                         (imprimeur-skin-tianlu-test-doc "zh-TW" "表：一表。\n\n| 甲 |\n|---|\n| 乙 |")))
  ;; A picture alone, with a description or none, and a film, each in a slot.
  (dolist (text '("![](a.png)" "![某圖](a.png)" "[某片](a.webm)"))
    (ert-info (text)
      (should (string-match-p "tianlu-slot[^>]*>\n<figure"
                              (imprimeur-skin-tianlu-test-doc "zh-TW" text)))))
  ;; A formula alone is a plate, and one in a line is turned.
  (let ((html (imprimeur-skin-tianlu-test-doc "zh-TW" "$$x + y$$\n\n設 $x$ 為。")))
    (should (string-search "tianlu-plate tianlu-math" html))
    (should (string-search "tianlu-imath" html))))

(ert-deftest imprimeur-skin-tianlu-writes-the-same-bytes-each-time ()
  (let ((text (imprimeur-skin-tianlu-test-read "examples/tianlu/bisheng-jiaoni-huozi.md")))
    (should (equal (imprimeur-skin-tianlu-test-html "gfm+sourcepos" text)
                   (imprimeur-skin-tianlu-test-html "gfm+sourcepos" text)))))

;;;; The samples

(ert-deftest imprimeur-skin-tianlu-samples-hold-what-they-should-and-nothing-else ()
  (let* ((traditional (imprimeur-skin-tianlu-test-read "examples/tianlu/tinggui-xiaoji.org"))
         (simplified (imprimeur-skin-tianlu-test-read "examples/tianlu/bisheng-jiaoni-huozi.md"))
         (showcase (imprimeur-skin-tianlu-test-read "examples/tianlu/showcase.org"))
         (sources (imprimeur-skin-tianlu-test-read "examples/tianlu/SOURCES.md"))
         (traditional-html (imprimeur-skin-tianlu-test-html "org" traditional))
         (simplified-html (imprimeur-skin-tianlu-test-html "gfm+sourcepos" simplified)))
    ;; A sample names no island, no flag and no era's date.
    (dolist (text (list traditional simplified showcase sources))
      (dolist (word '("臺灣" "台灣" "民國" "🇹🇼" "青天白日"))
        (should-not (string-search word text))))
    (should-not (string-search "begin_tianlu" traditional))
    (should-not (string-search "明人筆記多載之" traditional))
    (should (string-search "雨過青天雲破處，這般顏色做將來" traditional))
    ;; What each quotes, with its source in SOURCES.md.
    (dolist (passage '("人閒桂花落，夜靜春山空。月出驚山鳥，時鳴春澗中。"))
      (should (string-search passage traditional)))
    (dolist (passage '("庆历中，有布衣毕昇，又为活版。其法用胶泥刻字，薄如钱唇，每字为一印，火烧令坚。"
                       "木理有疏密，沾水则高下不平。"
                       "每一字皆有数印，如‘之’‘也’等字，每字有二十余印，以备一板内有重复者。"
                       "若止印三二本，未为简易；若印数十百千本，则极为神速。"
                       "每韵为一贴，木格贮之"
                       "奇字素无备者，旋刻之，以草火烧，瞬息可成"
                       "昇死，其印为余群从所得，至今保藏"))
      (ert-info (passage)
        (should (string-search passage simplified))))
    (dolist (source '("《夢溪筆談》卷十八" "〈鳥鳴澗〉" "《五雜俎》卷十二"))
      (should (string-search source sources)))
    (should (string-search "No reader of Chinese" sources))
    ;; Both render whole: quotes turned, a seal, a colophon, and each file they name is there.
    (should (string-search "「讀去聲。」" traditional-html))
    (should (string-search "歲次丙午九月二十三日" traditional-html))
    (should (string-search "岁次丙午九月二十三日" simplified-html))
    (dolist (file '("plate-shuixian.svg" "plate-zipan.svg" "yuhou.webm" "zhuanlun.webm"))
      (should (file-exists-p (expand-file-name file imprimeur-skin-tianlu-test-examples))))
    ;; The drawings hold no text, and so nothing of any font.
    (dolist (file '("plate-shuixian.svg" "plate-zipan.svg"))
      (let ((svg (imprimeur-skin-tianlu-test-read (concat "examples/tianlu/" file))))
        (should-not (string-search "<text" svg))
        (should-not (string-search "font-family" svg))))))

;;;; The page

(ert-deftest imprimeur-skin-tianlu-sets-both-samples-on-the-grid-with-horizontal-plates ()
  (pcase-dolist (`(,file ,kinds ,lines ,where)
                 '(("tinggui-xiaoji.org" ("table" "figure" "diagram" "math" "code") 20)
                   ("bisheng-jiaoni-huozi.md" ("diagram" "code" "math" "figure" "table") 20)
                   ;; A short document: its text is a line or two around its plates.
                   ("showcase.org" ("table" "figure" "diagram" "math" "code") 5 "examples/tianlu/")))
    (ert-info (file)
      (imprimeur-skin-tianlu-test-with
          (_buffer browser (concat where file) (imprimeur-skin-tianlu-test-read (concat "examples/tianlu/" file)))
        (imprimeur-test-cdp-wait
         browser "[...document.querySelectorAll('main pre.mermaid')].every((pre) => pre.querySelector('svg, code'))")
        (dolist (width '(640 420))
          (ert-info ((number-to-string width))
            (imprimeur-skin-tianlu-test-viewport browser width 900)
            (imprimeur-skin-tianlu-test-on-the-grid browser lines)))
        ;; A table is horizontal, so a formula in it is not turned.
        (imprimeur-test-cdp-wait
         browser "[...document.querySelectorAll('main table math')].every((math) => getComputedStyle(math).transform === 'none')")
        (let ((plates (append (imprimeur-test-cdp-eval browser imprimeur-skin-tianlu-test-plates) nil)))
          (dolist (kind kinds)
            (ert-info (kind)
              (should (seq-find (lambda (plate) (equal (aref plate 0) kind)) plates))))
          (dolist (plate plates)
            (should (equal (aref plate 1) "horizontal-tb"))))
        ;; Every slot at the top level: WebKit runs later text under a float in a wrapper's box,
        ;; which no test here can see drawn.  In Markdown each one knows its line.
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('main .tianlu-slot').length")
                       (imprimeur-test-cdp-eval
                        browser (format "document.querySelectorAll('#imprimeur-main > .tianlu-slot%s').length"
                                        (if (string-suffix-p ".md" file) "[data-line]" "")))))
        (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-banner').textContent") ""))
        (should-not (imprimeur-test-cdp-errors browser))))))

(ert-deftest imprimeur-skin-tianlu-gives-each-preset-its-grid-and-each-face-its-family ()
  (imprimeur-skin-tianlu-test-with (buffer browser "doc.md" imprimeur-skin-tianlu-test-mixed)
    (let ((band "(() => { const style = getComputedStyle(document.getElementById('imprimeur-main'));
return [parseFloat(style.width) / parseFloat(style.lineHeight), parseFloat(style.height) / parseFloat(getComputedStyle(document.documentElement).fontSize)]; })()")
          (ear "getComputedStyle(document.querySelector('.tianlu-folds u')).display"))
      ;; With nothing set, the root is bare and the look is the default's.
      (should (equal (imprimeur-test-cdp-eval
                      browser "[...document.documentElement.attributes].filter((a) => a.name.startsWith('data-tianlu')).length")
                     0))
      (should (equal (imprimeur-test-cdp-eval browser band) [10 20]))
      (should-not (equal (imprimeur-test-cdp-eval browser ear) "none"))
      (should (equal (imprimeur-skin-tianlu-test-face browser) "MOESongUN"))
      (imprimeur-skin-tianlu-test-on-the-grid browser)
      ;; Each preset alone: its grid, its ear, the face it brings; and it leaves the other
      ;; option's attribute alone.
      (pcase-dolist (`(,preset ,grid ,has-ear ,face)
                     '(("juzhen" [9 21] nil "I.MingCP")
                       ("siku" [8 21] nil "tianlu-moe-kai")
                       ("song" [10 20] t "MOESongUN")))
        (ert-info (preset)
          (imprimeur-skin-tianlu-test-choose buffer browser "preset" preset)
          (should (equal (imprimeur-test-cdp-eval browser band) grid))
          (should (equal (not (equal (imprimeur-test-cdp-eval browser ear) "none")) has-ear))
          (should (equal (imprimeur-skin-tianlu-test-face browser) face))
          (should-not (imprimeur-test-cdp-eval browser "document.documentElement.hasAttribute('data-tianlu-face')"))
          (imprimeur-skin-tianlu-test-on-the-grid browser)))
      ;; Each face alone: its family, and the preset's grid stays.
      (pcase-dolist (`(,face ,family)
                     '(("kai" "tianlu-moe-kai")
                       ("ming" "I.MingCP")
                       ("fang" "tianlu-punct-tw")
                       ("moe" "MOESongUN")
                       ("auto" "MOESongUN")))
        (ert-info (face)
          (imprimeur-skin-tianlu-test-choose buffer browser "face" face)
          (should (equal (imprimeur-skin-tianlu-test-face browser) family))
          (should (equal (imprimeur-test-cdp-eval browser band) [10 20]))
          (should-not (imprimeur-test-cdp-eval browser "document.documentElement.hasAttribute('data-tianlu-preset')"))))
      ;; A face wins over a preset, whichever is chosen first.
      (imprimeur-skin-tianlu-test-choose buffer browser "preset" "siku")
      (imprimeur-skin-tianlu-test-choose buffer browser "face" "ming")
      (should (equal (imprimeur-skin-tianlu-test-face browser) "I.MingCP"))
      (should (equal (imprimeur-test-cdp-eval browser band) [8 21])))))

(ert-deftest imprimeur-skin-tianlu-keeps-a-mainland-face-under-a-simplified-document ()
  (let ((text (replace-regexp-in-string "lang: zh-TW" "lang: %s" imprimeur-skin-tianlu-test-mixed)))
    (pcase-dolist (`(,lang ,family)
                   '(("zh-CN" "Zhuque Fangsong (technical preview)")
                     ("zh-Hans" "Zhuque Fangsong (technical preview)")
                     ("zh-SG" "Zhuque Fangsong (technical preview)")
                     ("zh" "MOESongUN")
                     ("zh-Hant" "MOESongUN")
                     ("zh-TW" "MOESongUN")))
      (ert-info (lang)
        (imprimeur-skin-tianlu-test-with (buffer browser "doc.md" (format text lang))
          (should (equal (imprimeur-skin-tianlu-test-face browser) family))
          (when (equal lang "zh-CN")
            (pcase-dolist (`(,id ,value ,face)
                           '(("preset" "juzhen" "Noto Serif CJK SC")
                             ("preset" "siku" "LXGW WenKai")
                             ("preset" "song" "Zhuque Fangsong (technical preview)")
                             ;; The Ministry's Song holds no simplified forms.
                             ("face" "moe" "Noto Serif CJK SC")
                             ("face" "kai" "LXGW WenKai")))
              (ert-info (value)
                (imprimeur-skin-tianlu-test-choose buffer browser id value)
                (should (equal (imprimeur-skin-tianlu-test-face browser) face))))))))))

(ert-deftest imprimeur-skin-tianlu-holds-the-song-to-its-floor ()
  ;; From the formula of the size and the Ministry's Song's measure of 19 px: each row is the
  ;; last and first viewport on either side of a grid of 19 px.  "TW-Kai" stands for the small
  ;; Kai, which takes the text under the floor.
  (imprimeur-skin-tianlu-test-with (buffer browser "doc.md" imprimeur-skin-tianlu-test-mixed)
    (pcase-dolist (`(,preset ,face ,rows)
                   '(("song" "auto" ((640 487 18 "TW-Kai") (640 488 19 "MOESongUN")
                                     (407 1000 18 "TW-Kai") (408 1000 19 "MOESongUN")
                                     (640 900 26 "MOESongUN") (420 900 19 "MOESongUN")
                                     (640 600 23 "MOESongUN")))
                     ("song" "moe" ((640 487 18 "TW-Kai") (640 488 19 "MOESongUN")))
                     ("juzhen" "moe" ((640 506 18 "TW-Kai") (640 507 19 "MOESongUN")
                                      (374 1000 18 "TW-Kai") (375 1000 19 "MOESongUN")))
                     ("siku" "moe" ((640 506 18 "TW-Kai") (640 507 19 "MOESongUN")
                                    (374 1000 21 "TW-Kai") (375 1000 21 "MOESongUN")))))
      (imprimeur-skin-tianlu-test-choose buffer browser "preset" preset)
      (imprimeur-skin-tianlu-test-choose buffer browser "face" face)
      (pcase-dolist (`(,width ,height ,size ,family) rows)
        (ert-info ((format "%s %s %d x %d" preset face width height))
          (imprimeur-skin-tianlu-test-viewport browser width height)
          (should (equal (imprimeur-skin-tianlu-test-size browser) size))
          (should (equal (imprimeur-skin-tianlu-test-face browser) family))))))
  ;; A simplified document's own Song moves for no floor.
  (imprimeur-skin-tianlu-test-with
      (buffer browser "doc.md" (replace-regexp-in-string "lang: zh-TW" "lang: zh-CN" imprimeur-skin-tianlu-test-mixed))
    (imprimeur-skin-tianlu-test-viewport browser 640 487)
    (should (equal (imprimeur-skin-tianlu-test-face browser) "Zhuque Fangsong (technical preview)"))
    (imprimeur-skin-tianlu-test-choose buffer browser "face" "moe")
    (should (equal (imprimeur-skin-tianlu-test-face browser) "Noto Serif CJK SC"))))

(ert-deftest imprimeur-skin-tianlu-sets-small-text-in-kai-under-the-song-alone ()
  (let ((text (concat "---\ntitle: T\nlang: zh-TW\n---\n\n<div class=\"headnote\">眉批。</div>\n\n正文[^1]。\n\n"
                      "![圖](a.png)\n\n[^1]: 小注。\n"))
        (small '(".tianlu-note" ".tianlu-headnote" "figcaption")))
    (imprimeur-skin-tianlu-test-with (buffer browser "doc.md" text)
      (dolist (selector small)
        (ert-info (selector)
          (should (string-prefix-p "\"TW-Kai\"" (imprimeur-test-cdp-eval
                                                 browser (format "getComputedStyle(document.querySelector(%S)).fontFamily.replace(/^(TW-Kai)/, '\"$1\"')" selector))))))
      (imprimeur-skin-tianlu-test-choose buffer browser "face" "ming")
      (dolist (selector small)
        (ert-info (selector)
          (should (string-prefix-p "\"I.MingCP\"" (imprimeur-test-cdp-eval
                                                   browser (format "getComputedStyle(document.querySelector(%S)).fontFamily" selector)))))))))

(ert-deftest imprimeur-skin-tianlu-keeps-its-bands-in-whole-pixels ()
  ;; WebKit snaps a background's tile to whole pixels, so that a band in fractions takes the
  ;; frame away from its columns along the page.
  (imprimeur-skin-tianlu-test-with (_buffer browser "doc.md" imprimeur-skin-tianlu-test-mixed)
    (pcase-dolist (`(,width ,height) '((640 900) (420 900) (640 600) (500 900) (450 700)))
      (ert-info ((format "%d x %d" width height))
        (imprimeur-skin-tianlu-test-viewport browser width height)
        (should (imprimeur-test-cdp-eval browser "(() => {
  const style = getComputedStyle(document.getElementById('imprimeur-main'));
  const pitch = parseFloat(style.height) + parseFloat(style.columnGap);
  return Number.isInteger(pitch);
})()"))))))

(ert-deftest imprimeur-skin-tianlu-draws-one-fold-for-each-band-outside-main ()
  (let* ((many (mapconcat (lambda (n) (format "第%d段，%s。" n (apply #'concat (make-list 40 "舊宅在巷底"))))
                          (number-sequence 1 12) "\n\n"))
         (text (format "---\ntitle: '\\<img src=x onerror=1\\>長題'\nlang: zh-TW\n---\n\n%s\n" many))
         (folds "document.querySelectorAll('body > .tianlu-folds > i').length"))
    (imprimeur-skin-tianlu-test-with (buffer browser "doc.md" text)
      (let ((count (imprimeur-test-cdp-eval browser folds)))
        (should (> count 2))
        ;; Its children are the page's bands, by the page's height with the layer gone.
        (should (equal (imprimeur-test-cdp-eval browser
                                                "document.querySelector('.tianlu-folds').getBoundingClientRect().height <= document.documentElement.scrollHeight")
                       t))
        (let ((with (imprimeur-test-cdp-eval browser "document.documentElement.scrollHeight"))
              (pitch (imprimeur-test-cdp-eval browser "parseFloat(getComputedStyle(document.getElementById('imprimeur-main')).height) + parseFloat(getComputedStyle(document.getElementById('imprimeur-main')).columnGap)")))
          (should (equal count (round (/ (float with) pitch))))
          (should (equal (imprimeur-test-cdp-eval
                          browser "(() => { const layer = document.querySelector('.tianlu-folds'); layer.style.display = 'none'; const height = document.documentElement.scrollHeight; layer.style.display = ''; return height; })()")
                         with)))
        ;; None of it in main, whose blocks the page diffs.
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('main .tianlu-folds').length") 0))
        ;; The title reaches it as text alone.
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.tianlu-folds i').getAttribute('data-tianlu-title')")
                       "<img src=x onerror=1>長題"))
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.tianlu-folds img').length") 0))
        ;; An option, a viewport and an edit each count the bands again.
        (imprimeur-skin-tianlu-test-choose buffer browser "preset" "siku")
        (imprimeur-test-cdp-wait browser (format "%s > %d" folds count))
        (imprimeur-skin-tianlu-test-choose buffer browser "preset" "song")
        (imprimeur-test-cdp-wait browser (format "%s === %d" folds count))
        ;; A narrower page draws the same bands smaller, and the layer ends with the page.
        (imprimeur-skin-tianlu-test-viewport browser 420 900)
        (should (equal (imprimeur-test-cdp-eval browser
                                                "Math.round(document.querySelector('.tianlu-folds').getBoundingClientRect().height) === document.documentElement.scrollHeight")
                       t))
        (imprimeur-skin-tianlu-test-viewport browser 640 900)
        (with-current-buffer buffer
          (goto-char (point-max))
          (insert (format "\n%s\n" many)))
        (imprimeur-test-cdp-wait browser (format "%s > %d" folds count) 20)
        ;; Each band's number comes from the sheet, by leaves of two half-leaves.
        (should (equal (imprimeur-test-cdp-eval
                        browser "getComputedStyle(document.querySelector('.tianlu-folds i:nth-child(3)')).counterIncrement")
                       "tianlu-leaf 1"))
        (should (equal (imprimeur-test-cdp-eval
                        browser "getComputedStyle(document.querySelector('.tianlu-folds i:nth-child(2)')).counterIncrement")
                       "none"))))))

(ert-deftest imprimeur-skin-tianlu-opens-a-document-with-no-title-on-the-first-band ()
  (pcase-dolist (`(,file ,text)
                 '(("doc.md" "---\nlang: zh-TW\n---\n\n# 甲\n\n文。\n\n# 乙\n\n文。\n")
                   ("doc.org" "#+LANGUAGE: zh-TW\n\n* 甲\n\n文。\n\n* 乙\n\n文。\n")))
    (ert-info (file)
      (imprimeur-skin-tianlu-test-with (_buffer browser file text)
        (should (< (imprimeur-test-cdp-eval
                    browser "document.querySelector('#imprimeur-main > :first-child').getBoundingClientRect().top + scrollY")
                   (imprimeur-test-cdp-eval
                    browser "parseFloat(getComputedStyle(document.getElementById('imprimeur-main')).marginTop) + 2")))))))

(ert-deftest imprimeur-skin-tianlu-gives-each-diagram-its-width ()
  (let ((text (concat imprimeur-skin-tianlu-test-mixed "\n```mermaid\nflowchart TD\n  甲 --> 乙\n```\n\n末段。\n")))
    (imprimeur-skin-tianlu-test-with (_buffer browser "doc.md" text)
      (when (imprimeur-test-cdp-eval browser "document.documentElement.hasAttribute('data-mermaid')")
        (imprimeur-test-cdp-wait browser "document.querySelector('pre.mermaid > svg') !== null" 30)
        (imprimeur-test-cdp-wait
         browser "document.querySelector('.tianlu-slot:has(pre.mermaid)').style.getPropertyValue('--tianlu-draw-w') !== ''")
        (should (equal (imprimeur-test-cdp-eval
                        browser "parseFloat(document.querySelector('.tianlu-slot:has(pre.mermaid)').style.getPropertyValue('--tianlu-draw-w'))")
                       (imprimeur-test-cdp-eval
                        browser "document.querySelector('pre.mermaid > svg').viewBox.baseVal.width")))
        (imprimeur-skin-tianlu-test-on-the-grid browser)))))

;; A band holds several of these paragraphs, side by side at one offset along the page.
(defconst imprimeur-skin-tianlu-test-short-paragraphs
  (mapconcat (lambda (n) (format "第%d段，舊宅在巷底，門內一方小庭，四季桂兩株，老梅一株，石徑不過十數步。\n\n" n))
             (number-sequence 1 30) "")
  "Thirty paragraphs of three columns or so.")

(defun imprimeur-skin-tianlu-test-block (paragraph)
  "Return JavaScript giving the block of the page that starts with PARAGRAPH."
  (format "[...document.querySelectorAll('#imprimeur-main > *')].find((block) => block.textContent.trim().startsWith('%s'))"
          paragraph))

(ert-deftest imprimeur-skin-tianlu-finds-the-source-s-line-by-a-double-click-and-a-scroll ()
  (pcase-dolist (`(,file ,head)
                 '(("doc.md" "---\ntitle: 試排\nlang: zh-TW\n---\n\n# 第一\n\n")
                   ("doc.org" "#+TITLE: 試排\n#+LANGUAGE: zh-TW\n\n* 第一\n\n")))
    (ert-info (file)
      (imprimeur-skin-tianlu-test-with
          (buffer browser file (concat head imprimeur-skin-tianlu-test-short-paragraphs))
        ;; Paragraphs that share a band, and so an offset along the page.
        (should (equal (imprimeur-test-cdp-eval
                        browser (format "%s.getBoundingClientRect().top === %s.getBoundingClientRect().top"
                                        (imprimeur-skin-tianlu-test-block "第2段") (imprimeur-skin-tianlu-test-block "第1段")))
                       t))
        ;; A double-click names each one's own line.
        (dolist (paragraph '("第1段" "第2段" "第3段" "第20段"))
          (ert-info (paragraph)
            (let ((block (imprimeur-skin-tianlu-test-block paragraph)))
              (imprimeur-test-cdp-eval browser (concat block ".scrollIntoView({ block: 'center' })"))
              (imprimeur-test-cdp-click browser block nil 2)
              (imprimeur-test-wait-for
               (lambda () (with-current-buffer buffer (looking-at-p paragraph)))))))
        ;; A scroll of the source's Emacs window brings the page to that line's band.
        (let ((overriding-local-map
               (define-keymap "<f12>" (lambda ()
                                        (interactive)
                                        (goto-char (point-min))
                                        (search-forward "第25段")
                                        (set-window-start nil (pos-bol))))))
          (execute-kbd-macro [f12]))
        (imprimeur-test-cdp-wait
         browser (format "Math.abs(%s.getBoundingClientRect().top) <= 2 && window.scrollY > 0"
                         (imprimeur-skin-tianlu-test-block "第25段")))
        ;; And a wheel on the page brings the Emacs window to a block of the band it reaches.
        (imprimeur-test-cdp-wheel browser -1000)
        (imprimeur-test-wait-for
         (lambda ()
           (equal (line-number-at-pos (window-start) t)
                  (imprimeur-test-cdp-eval browser "(() => {
  const blocks = [...document.querySelectorAll('#imprimeur-main > [data-line]')]
    .filter((block) => block.getBoundingClientRect().top <= 0);
  return Number(blocks.at(-1).getAttribute('data-line'));
})()"))))
        (should-not (imprimeur-test-cdp-errors browser))))))

(ert-deftest imprimeur-skin-tianlu-leaves-nothing-after-a-swap ()
  (imprimeur-skin-tianlu-test-with (buffer browser "doc.md" imprimeur-skin-tianlu-test-mixed)
    (with-current-buffer buffer (imprimeur-choose-skin "base"))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.skin === 'base'")
    (imprimeur-test-cdp-wait browser "document.querySelector('.tianlu-folds') === null")
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('[style*=\"tianlu-draw-w\"]').length") 0))
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-banner').textContent") ""))))

(ert-deftest imprimeur-skin-tianlu-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (imprimeur-skin-tianlu-test-read "imprimeur-skin-tianlu/README.md"))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'tianlu\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-tianlu-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-tianlu)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"tianlu\" (imprimeur-skin-get \"tianlu\") (imprimeur-skin-configured \"tianlu\" (imprimeur-skin-get \"tianlu\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "tianlu[]" (cdr result)))))

(ert-deftest imprimeur-skin-tianlu-sheet-keeps-to-its-names ()
  (let ((sheet (replace-regexp-in-string
                "/\\*\\(?:.\\|\n\\)*?\\*/\\|url(\"[^\"]*\")" ""
                (imprimeur-skin-tianlu-test-read "imprimeur-skin-tianlu/assets/skin.css")))
        (start 0))
    (while (string-match "\\.\\([a-z][a-z-]*\\)[ ,:{)>]" sheet start)
      (setq start (match-end 0))
      (let ((class (match-string 1 sheet)))
        (ert-info (class)
          ;; What belongs to the shell, the core or pandoc keeps its name, and the skin's its own.
          (should (or (string-prefix-p "tianlu-" class)
                      (member class '("title" "unnumbered" "task" "note" "tip" "important" "warning" "caution"
                                      "caption" "captioned-content" "sourceCode" "mermaid"
                                      ;; pandoc's tokens, and what a number's decimals read as.
                                      "kw" "cf" "im" "pp" "at" "st" "ss" "vs" "ch" "sc" "bn" "fu" "bu" "ex"
                                      "dt" "dv" "fl" "cn" "va" "op" "ot" "sp" "co" "do" "an" "cv" "in" "er" "wa" "al")))))))
    (should-not (string-search "--tl-" sheet))))

;;; imprimeur-skin-tianlu-test.el ends here

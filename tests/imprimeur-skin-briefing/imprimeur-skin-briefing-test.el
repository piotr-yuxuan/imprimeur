;;; imprimeur-skin-briefing-test.el --- Tests of the skin Briefing  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 023:
;;
;; "A modern business memo in Inter, compact by default, with the owner's sample briefs":
;; the manifest's defaults and choices, by hand from docs/work/planned/skin-defaults.md and
;; the workbench's params.json: accent (blue, teal, aubergine, graphite), density (compact by
;; default, regular, airy), skim (off).
;;
;; Acceptance 3: with Briefing chosen, on real pandoc, the Org and Markdown briefs show the
;; bottom line, callouts, chips with no [#A] in an id, numeric tables right-aligned; French
;; labels under a French document.  Acceptance 4: each option changes what it says, alone;
;; skim hides the body and shows the summaries.  Acceptance 6: the filter is within 10, by
;; luacheck.
;;
;; What the filter does, by the trial's reports and plan 014: a column of quantities takes
;; the right by Org's threshold of a half, thousands, currencies, 3.5k and the true minus
;; counting, a version or a date not; a heading keeps every word, and a chip draws its own;
;; a Markdown keyword needs its colon; repeated titles keep ids of their own; a section
;; named as a summary is the bottom line, up to the next heading of its level or callout;
;; a leading strong word names a callout; a plain block keeps its line.
;;
;; The tests register Briefing in a registry of their own, as the other tests see Minitel
;; alone.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-briefing-test-file
  (expand-file-name "imprimeur-skin-briefing/imprimeur-skin-briefing.el" repo-test-root)
  "The skin's main file.")

(defconst imprimeur-skin-briefing-test-examples
  (expand-file-name "examples/briefing" repo-test-root)
  "The directory of the two briefs.")

(defun imprimeur-skin-briefing-test-read (file)
  "Return the text of FILE, one of the two briefs."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file imprimeur-skin-briefing-test-examples))
    (buffer-string)))

(defun imprimeur-skin-briefing-test-html (reader text)
  "Return the HTML that Briefing's chain writes from TEXT in READER, on real pandoc.
The arguments are those of a page's render."
  (let ((pandoc (imprimeur-test-require "pandoc"))
        (imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-briefing-test-file nil t)
    (with-temp-buffer
      (insert text)
      (should (equal (apply #'call-process-region (point-min) (point-max) pandoc t t nil
                            (imprimeur-render-arguments reader nil nil "python,bash"
                                                        (imprimeur-skin-get "briefing")))
                     0))
      (buffer-string))))

(defun imprimeur-skin-briefing-test-headings (html)
  "Return the text of each heading of HTML, its markup out, its spaces folded."
  (let ((start 0) found)
    (while (string-match "<h[1-6][^>]*>\\(\\(?:.\\|\n\\)*?\\)</h[1-6]>" html start)
      (setq start (match-end 0))
      (push (string-trim (replace-regexp-in-string
                          "[ \n]+" " "
                          (replace-regexp-in-string "<[^>]+>" "" (match-string 1 html))))
            found))
    (nreverse found)))

(defun imprimeur-skin-briefing-test-right-columns (html)
  "Return how many cells of HTML's first table's first row of data stand on the right."
  (string-match "<tbody>\\(\\(?:.\\|\n\\)*?\\)</tr>" html)
  (let ((row (match-string 1 html)) (start 0) (count 0))
    (while (string-match "<td[^>]*text-align: right" row start)
      (setq start (match-end 0) count (1+ count)))
    count))

(defmacro imprimeur-skin-briefing-test-with (spec &rest body)
  "Run BODY with Briefing as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in
the selected Emacs window, in `imprimeur-mode'; BROWSER shows its page."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'briefing)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (load imprimeur-skin-briefing-test-file nil t)
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-mode 1)
                 (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
                 (imprimeur-test-wait-for
                  (lambda () (imprimeur-test-cdp-eval ,browser "document.documentElement.dataset.revision")))
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-skin-briefing-test-style (browser selector property)
  "Return the computed PROPERTY of SELECTOR in BROWSER's page."
  (imprimeur-test-cdp-eval
   browser (format "getComputedStyle(document.querySelector(%S))[%S]" selector property)))

(defun imprimeur-skin-briefing-test-count (browser selector)
  "Return how many elements SELECTOR finds in BROWSER's page."
  (imprimeur-test-cdp-eval browser (format "document.querySelectorAll(%S).length" selector)))

(defun imprimeur-skin-briefing-test-attributes (browser)
  "Return the names of the data-briefing attributes on the root of BROWSER's page."
  (append (imprimeur-test-cdp-eval
           browser "[...document.documentElement.attributes].map((a) => a.name).filter((n) => n.startsWith('data-briefing'))")
          nil))

(defun imprimeur-skin-briefing-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-briefing-%s') === %s"
                   id (if (equal value (plist-get (cdr (assq (intern id) (plist-get (imprimeur-skin-get "briefing") :options)))
                                                  :default))
                          "null"
                        (format "%S" value)))))

(defconst imprimeur-skin-briefing-test-body
  "[...document.querySelectorAll('#imprimeur-main p')].find((p) => p.textContent.includes('Un autre')).parentElement"
  "A top-level block of the body of the memo below, the wrapper of a paragraph.")

(defun imprimeur-skin-briefing-test-said (browser)
  "Return what each option decides of BROWSER's page, as an alist from the option.
The accent by a link's colour, the density by a paragraph's line over its size, and the
skim view by whether the block of a paragraph takes any room."
  (list (cons 'accent (imprimeur-skin-briefing-test-style browser "#imprimeur-main a:not(.briefing-skim)" "color"))
        (cons 'density (imprimeur-test-cdp-eval browser (format "(() => {
  const style = getComputedStyle(%s.firstElementChild);
  return Math.round(100 * parseFloat(style.lineHeight) / parseFloat(style.fontSize));
})()" imprimeur-skin-briefing-test-body)))
        (cons 'skim (imprimeur-test-cdp-eval
                     browser (format "%s.getBoundingClientRect().height === 0" imprimeur-skin-briefing-test-body)))))

(defconst imprimeur-skin-briefing-test-memo
  (concat "---\ntitle: Une décision\nsubtitle: Une note\nauthor: Quelqu'un\ndate: 2026-11-01\nstatus: Pour décision\nlang: fr\n---\n\n"
          "# L'essentiel\n\nDire la réponse d'abord.\n\n> [!IMPORTANT]\n> Trancher.\n\n"
          "# Le corps\n\nUn [lien](https://example.invalid/) dans un alinéa.\n\nUn autre alinéa.\n\n"
          "## TODO: [#A] Une action peut-être :cour:\n\nDEADLINE: 2026-11-02, OWNER: Le roi\n\nSon texte.\n\n"
          "#### Trop bas\n\n| Article | Livres |\n|---|---|\n| Un | 1 000 |\n| Total | 2 000 |\n")
  "A French memo in GitHub Markdown, with all that the skim view keeps and hides.")

(ert-deftest imprimeur-skin-briefing-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-briefing-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-briefing-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-briefing)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S\" (and (imprimeur-skin-get \"briefing\") t)))"))))
    (should (equal (car result) 0))
    (should (string-match-p "MARK\\(.\\|\n\\)*before=nil after=t\\'" (cdr result)))))

(ert-deftest imprimeur-skin-briefing-keeps-the-owner-s-defaults-and-choices ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-briefing-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "briefing"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "Briefing"))
      (should (plist-get manifest :smart))
      (should (equal (plist-get manifest :module) "page.mjs"))
      (should-not (plist-get manifest :notes))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((accent "blue" "blue" "teal" "aubergine" "graphite")
                       (density "compact" "compact" "regular" "airy")
                       (skim "off" "off" "on")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(accent density skim))))))

(ert-deftest imprimeur-skin-briefing-finds-the-quantities-of-a-table ()
  ;; Each row: a column's cells, in a language, and whether it stands on the right.
  (pcase-dolist (`(,lang ,cells ,right)
                 '(("en" ("412,880" "£84,000" "€1,200") t)
                   ("en" ("$217" "81" "$2,500") t)
                   ("en" ("-16" "−16" "12%") t)
                   ("en" ("3.5k" "0.5" "1e6") t)
                   ("en" ("12" "many" "") t)
                   ("en" ("12" "many" "words") nil)
                   ("en" ("1.2.3" "4.5.6" "7.8.9") nil)
                   ("en" ("2026-11-02" "2026-11-03" "2026-11-04") nil)
                   ("en" ("10 20" "30 40" "50 60") nil)
                   ("en" ("1,23" "4,56" "7,89") nil)
                   ("en" ("" "" "") nil)
                   ("fr" ("234 962 756" "1,5" "12 %") t)
                   ("fr" ("234 962 756" "1 000" "2 000") t)))
    (ert-info ((format "%s %S" lang cells))
      (let* ((rows (mapconcat (lambda (cell) (format "| x | %s |\n" cell)) cells ""))
             (html (imprimeur-skin-briefing-test-html
                    "gfm" (format "---\nlang: %s\n---\n\n| Name | Value |\n|---|---|\n%s" lang rows))))
        (should (equal (imprimeur-skin-briefing-test-right-columns html) (if right 1 0))))))
  ;; A cell over 64 bytes is no quantity, and a minus in a quantity is a true one.
  (should (equal (imprimeur-skin-briefing-test-right-columns
                  (imprimeur-skin-briefing-test-html
                   "gfm" (format "| Name | Value |\n|---|---|\n| x | %s |\n" (make-string 65 ?1))))
                 0))
  (should (string-search "−16" (imprimeur-skin-briefing-test-html "gfm" "| A | B |\n|---|---|\n| x | -16 |\n")))
  (should (string-search "One-off" (imprimeur-skin-briefing-test-html "gfm" "| A |\n|---|\n| One-off |\n")))
  ;; A row named Total, Sum or a total of something takes the class; a Summer does not.
  (pcase-dolist (`(,name ,total) '(("Total" t) ("Total of these rows" t) ("Sum" t) ("Déficit total" t)
                                   ("Summer" nil) ("Totally" nil) ("Net" nil)))
    (ert-info (name)
      (should (eq (and (string-search
                        "class=\"briefing-total\""
                        (imprimeur-skin-briefing-test-html "gfm" (format "| A | B |\n|---|---|\n| %s | 1 |\n" name)))
                       t)
                  total)))))

(ert-deftest imprimeur-skin-briefing-draws-a-heading-s-marks-as-chips ()
  (pcase-dolist (`(,reader ,text ,words)
                 '(("gfm+sourcepos+smart"
                    "---\ntitle: T\n---\n\n## TODO: [#A] Review the draft :ops:cost:\n\nDEADLINE: 2026-11-02, OWNER: Pat\n\nWords.\n\n## Bare\n"
                    ("Open" "P1" "Due 2 Nov" "Pat" "ops" "cost"))
                   ("org+smart"
                    "#+TITLE: T\n#+OPTIONS: p:t\n* TODO [#A] Review the draft :ops:cost:\nDEADLINE: <2026-11-02 Mon>\nWords.\n* Bare\n"
                    ("Open" "P1" "Due 2 Nov" "ops" "cost"))
                   ("gfm+sourcepos+smart"
                    "---\ntitle: T\nlang: fr\n---\n\n## TODO: [#A] Review the draft :ops:cost:\n\nDEADLINE: 2026-11-01\n\nMots.\n\n## Bare\n"
                    ("À faire" "P1" "Échéance 1er nov." "ops" "cost"))
                   ("org+smart"
                    "#+TITLE: T\n#+LANGUAGE: fr\n#+OPTIONS: p:t\n* DONE [#A] Review the draft :ops:\nDEADLINE: <2026-11-02 lun.>\nMots.\n* Bare\n"
                    ("Fait" "P1" "Échéance 2 nov." "ops"))))
    (ert-info (text)
      (let ((html (imprimeur-skin-briefing-test-html reader text)))
        (dolist (word words)
          (should (string-search (format "data-word=\"%s\"" word) html)))
        ;; The cookie, the keyword and the tags in no id, and no text in a chip.
        (should (string-search "id=\"doc-review-the-draft\"" html))
        (should-not (string-match-p "id=\"[^\"]*\\(?:todo\\|done\\|\\ba-review\\|ops\\)" html))
        (should-not (string-match-p "class=\"briefing-chip\"[^>]*>[^<]" html))
        ;; The heading keeps every word it has under no skin.
        (should (string-search "[#A]" (car (imprimeur-skin-briefing-test-headings html))))
        (should (string-search "Review the draft" (car (imprimeur-skin-briefing-test-headings html))))
        (should (equal (cadr (imprimeur-skin-briefing-test-headings html)) "Bare")))))
  ;; A Markdown keyword needs its colon, and a keyword outside the six keeps its word.
  (let ((html (imprimeur-skin-briefing-test-html "gfm" "## NEXT STEPS\n\n## TODO list\n\n## DONE WHEN\n")))
    (should-not (string-search "briefing-chip" html)))
  (let ((html (imprimeur-skin-briefing-test-html "org" "#+TODO: REVIEW | CLOSED\n* REVIEW One\n* Two\n")))
    (should (string-search "data-word=\"Review\" data-status=\"other\"" html)))
  ;; An Org owner stays a plain chip, as nothing else on the page writes it.
  (let ((html (imprimeur-skin-briefing-test-html "org" "* DONE One\n:PROPERTIES:\n:OWNER: Turgot\n:END:\n* Two\n")))
    (should (string-search ">Turgot</span>" html)))
  ;; An identifier that the document chose stays, as a link may lead to it.
  (let ((html (imprimeur-skin-briefing-test-html
               "org" "* TODO Task :x:\n:PROPERTIES:\n:CUSTOM_ID: mine\n:END:\n* TODO [#A] L'État\n")))
    (should (string-search "id=\"doc-mine\"" html))
    (should (string-search "id=\"doc-l" html))
    (should-not (string-match-p "id=\"doc-a-" html)))
  ;; A date that is none draws no chip, and leaves the document whole.
  (let ((html (imprimeur-skin-briefing-test-html
               "gfm" "## TODO: One\n\nDEADLINE: 2026-13-01, OWNER: Pat\n\nWords.\n\n## Two\n")))
    (should (string-search "data-word=\"Pat\"" html))
    (should-not (string-search "data-kind=\"due\"" html))))

(ert-deftest imprimeur-skin-briefing-keeps-repeated-titles-apart ()
  (let ((html (imprimeur-skin-briefing-test-html
               "gfm" "## Same\n\n## Same\n\n## TODO: [#A] Same\n\n## DONE: Same\n")))
    (should (string-search "id=\"doc-same\"" html))
    (should (string-search "id=\"doc-same-1\"" html))
    (should (string-search "id=\"doc-same-2\"" html))
    (should (string-search "id=\"doc-same-3\"" html))))

(ert-deftest imprimeur-skin-briefing-makes-the-shallowest-heading-the-first-level ()
  (let ((html (imprimeur-skin-briefing-test-html "gfm" "---\ntitle: T\n---\n\n## Two\n\n### Three\n")))
    (should (string-match-p "<h1[^>]*>Two</h1>" html))
    (should (string-match-p "<h2[^>]*>Three</h2>" html))))

(ert-deftest imprimeur-skin-briefing-finds-the-bottom-line-and-the-callouts ()
  (pcase-dolist (`(,title ,lang) '(("Summary" "en") ("Executive summary" "en") ("TL;DR" "en") ("Bottom line" "en")
                                   ("Résumé" "fr") ("Synthèse" "fr") ("L'essentiel" "fr")))
    (ert-info (title)
      (let ((html (imprimeur-skin-briefing-test-html
                   "gfm+smart" (format "---\nlang: %s\n---\n\n# %s\n\nInside.\n\n## Under\n\nStill.\n\n# After\n\nOutside.\n"
                                       lang title))))
        (should (string-match-p "briefing-bottom-line\\(?:.\\|\n\\)*Inside\\(?:.\\|\n\\)*Still\\(?:.\\|\n\\)*</section>\\(?:.\\|\n\\)*After" html)))))
  (let ((html (imprimeur-skin-briefing-test-html "gfm" "# Plain\n\nInside.\n")))
    (should-not (string-search "briefing-bottom-line" html)))
  ;; A callout ends it, and its label and kind come from the alert, or a leading strong word.
  (pcase-dolist (`(,block ,lang ,kind ,label)
                 '(("[!IMPORTANT]" "en" "decision" "Important")
                   ("[!WARNING]" "en" "ask" "Warning")
                   ("[!CAUTION]" "en" "risk" "Caution")
                   ("[!NOTE]" "en" "note" "Note")
                   ("[!TIP]" "en" "note" "Tip")
                   ("[!CAUTION]" "fr" "risk" "Prudence")))
    (ert-info (block)
      (let ((html (imprimeur-skin-briefing-test-html
                   "gfm+sourcepos" (format "---\nlang: %s\n---\n\n# Summary\n\nInside.\n\n> %s\n> Words.\n\nOutside.\n\n# After\n" lang block))))
        (should (string-search (format "data-kind=\"%s\"" kind) html))
        (should (string-search (format "class=\"briefing-label\">\n%s" label) html))
        (should (string-match-p "</section>\\(?:.\\|\n\\)*briefing-callout" html)))))
  (let ((html (imprimeur-skin-briefing-test-html "gfm+sourcepos" "> [!WARNING]\n> **Ask:** Words.\n")))
    (should (string-search "class=\"briefing-label\">\nAsk" html))
    (should-not (string-search "<strong>" html)))
  (let ((html (imprimeur-skin-briefing-test-html "org" "#+begin_decision\nWords.\n#+end_decision\n\n#+begin_risk\nWords.\n#+end_risk\n")))
    (should (string-search "data-kind=\"decision\"" html))
    (should (string-search "data-kind=\"risk\"" html))))

(ert-deftest imprimeur-skin-briefing-writes-a-masthead ()
  (let ((html (imprimeur-skin-briefing-test-html
               "gfm" "---\ntitle: T\nsubtitle: S\nauthor: A\ndate: 2026-11-01\nstatus: For decision\n---\n\nWords.\n")))
    (dolist (text '("class=\"briefing-subtitle\"" ">A</span>" ">1 November 2026</span>" ">For decision</span>"
                    ">1 min read</span>" ">Skim</span>" ">Full brief</span>" "role=\"button\"" "aria-pressed=\"false\""))
      (should (string-search text html))))
  (let ((html (imprimeur-skin-briefing-test-html
               "org" "#+TITLE: T\n#+AUTHOR: A\n#+DATE: 2026-11-01\n#+STATUS: Pour décision\n#+LANGUAGE: fr\n\nMots.\n")))
    (dolist (text '(">1er novembre 2026</span>" ">Pour décision</span>" ">1 min de lecture</span>" ">Survol</span>" ">Texte entier</span>"))
      (should (string-search text html))))
  (should-not (string-search "briefing-masthead" (imprimeur-skin-briefing-test-html "gfm" "---\ntitle: T\n---\n\nWords.\n")))
  ;; A date that is no date stays as the document wrote it.
  (pcase-dolist (`(,date ,shown) '(("2026-13-01" "2026-13-01") ("2026-00-10" "2026-00-10") ("In the spring" "In the spring")))
    (ert-info (date)
      (should (string-search
               (format ">%s</span>" shown)
               (imprimeur-skin-briefing-test-html "gfm" (format "---\ntitle: T\ndate: %s\n---\n\nWords.\n" date)))))))

(ert-deftest imprimeur-skin-briefing-sets-figures-and-signs-in-french ()
  (let ((html (imprimeur-skin-briefing-test-html
               "org" (concat "#+LANGUAGE: fr\nSomme de 234 962 756 livres, et de 234 962 757, à 12 %.\n\n"
                             "Une formule $x$ : près, et $y$ ; puis.\n\n* Peut-être vingt-et-une fois\n"))))
    (should (string-search "234 962 756 livres" html))
    (should (string-search "234 962 757" html))
    (should (string-search "12 %" html))
    (should (string-match-p "briefing-nobreak\"><math.*</math> :</span> près" html))
    (should (string-match-p "briefing-nobreak\"><math.*</math> ;</span> puis" html))
    (should (string-search "<span class=\"briefing-compound\">Peut-être</span>" html))
    (should (string-search "<span class=\"briefing-compound\">vingt-et-une</span>" html))
    (should-not (string-search "⁠" html)))
  (let ((html (imprimeur-skin-briefing-test-html "org" "Some 234 962 756 and x-y.\n\n* Well-known\n")))
    (should (string-search "234 962 756" html))
    (should-not (string-search "briefing-compound" html))))

(ert-deftest imprimeur-skin-briefing-sets-plain-code-and-keeps-its-line ()
  (let ((html (imprimeur-skin-briefing-test-html
               "gfm+sourcepos" "Words.\n\n```\nshort <b>\na line of more than forty columns with --a-flag in it\n```\n")))
    (should (string-search "<span>short &lt;b&gt;</span>" html))
    (should (string-search "<span class=\"briefing-word\">--a-flag</span>" html))
    (should (string-match-p "<div[^>]*imprimeur-code[^>]*data-pos=\"3:" html))))

(ert-deftest imprimeur-skin-briefing-writes-the-same-bytes-twice ()
  ;; The page's block diff keeps a block whose markup is the same.
  (let ((text (imprimeur-skin-briefing-test-read "jefferson.md")))
    (should (equal (imprimeur-skin-briefing-test-html "gfm+sourcepos+smart" text)
                   (imprimeur-skin-briefing-test-html "gfm+sourcepos+smart" text)))))

(defun imprimeur-skin-briefing-test-brief (file labels chips)
  "Check the page of the brief FILE: its LABELS, in its language, and its CHIPS of priority."
  (imprimeur-skin-briefing-test-with (_buffer browser file (imprimeur-skin-briefing-test-read file))
    (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.skin") "briefing"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.briefing-masthead') !== null")
    (should (equal (imprimeur-skin-briefing-test-count browser ".briefing-bottom-line") 1))
    (should (>= (imprimeur-skin-briefing-test-count browser ".briefing-callout") 3))
    (should (equal (imprimeur-skin-briefing-test-count browser ".briefing-chip[data-kind='priority']") chips))
    (should (equal (imprimeur-test-cdp-eval
                    browser "[...document.querySelectorAll('[id]')].filter((e) => /#|\\[|%5B/.test(e.id)).length")
                   0))
    ;; A chip draws its word, and the heading keeps the document's letters at no size.
    (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('.briefing-chip[data-word]'), '::before').content.length > 2") t))
    (should (equal (imprimeur-skin-briefing-test-style browser ".briefing-letters" "fontSize") "0px"))
    ;; The quantities of the first table, on the right.
    (should (equal (imprimeur-test-cdp-eval
                    browser "getComputedStyle(document.querySelector('.briefing-table tbody td:last-child')).textAlign")
                   "right"))
    ;; A diagram's caption stands under it, numbered with the figures, at full width.
    (imprimeur-test-cdp-wait browser "document.querySelector('.captioned-content > pre.mermaid svg') !== null")
    (should (eq (imprimeur-test-cdp-eval browser "(() => {
  const box = document.querySelector('.captioned-content:has(> pre.mermaid)');
  const caption = box.querySelector(':scope > .caption');
  return caption.getBoundingClientRect().top >= box.querySelector(':scope > pre.mermaid').getBoundingClientRect().bottom
    && getComputedStyle(caption, '::before').content.startsWith('\"Figure');
})()")
                t))
    (dolist (label labels)
      (should (imprimeur-test-cdp-eval
               browser (format "document.getElementById('imprimeur-main').innerText.includes(%S)" label))))
    (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.scrollWidth")
                   (imprimeur-test-cdp-eval browser "document.documentElement.clientWidth")))
    (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))))

(ert-deftest imprimeur-skin-briefing-sets-the-french-brief-in-org ()
  (imprimeur-skin-briefing-test-brief "turgot.org" '("Survol" "24 août 1774" "min de lecture") 6))

(ert-deftest imprimeur-skin-briefing-sets-the-english-brief-in-markdown ()
  (imprimeur-skin-briefing-test-brief "jefferson.md" '("Skim" "20 June 1803" "min read") 7))

(ert-deftest imprimeur-skin-briefing-changes-what-each-option-says-alone ()
  (imprimeur-skin-briefing-test-with (buffer browser "memo.md" imprimeur-skin-briefing-test-memo)
    (with-current-buffer buffer
      (setq imprimeur-appearance 'light)
      (imprimeur-refresh-palette))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
    (imprimeur-test-cdp-wait browser "document.querySelector('.briefing-masthead') !== null")
    (should-not (imprimeur-skin-briefing-test-attributes browser))
    (let ((defaults (imprimeur-skin-briefing-test-said browser)))
      (should (equal defaults '((accent . "rgb(31, 79, 163)") (density . 142) (skim . nil))))
      (pcase-dolist (`(,id ,value ,property ,said ,default)
                     '(("accent" "teal" accent "rgb(0, 107, 100)" "blue")
                       ("accent" "aubergine" accent "rgb(91, 58, 140)" "blue")
                       ("accent" "graphite" accent "rgb(26, 28, 30)" "blue")
                       ("density" "regular" density 155 "compact")
                       ("density" "airy" density 172 "compact")
                       ("skim" "on" skim t "off")))
        (ert-info ((format "%s %s" id value))
          (imprimeur-skin-briefing-test-choose buffer browser id value)
          (let ((now (imprimeur-skin-briefing-test-said browser)))
            (should (equal (alist-get property now) said))
            (should (equal (assq-delete-all property (copy-alist now))
                           (assq-delete-all property (copy-alist defaults)))))
          (should (equal (imprimeur-skin-briefing-test-attributes browser) (list (format "data-briefing-%s" id))))
          (imprimeur-skin-briefing-test-choose buffer browser id default)
          (should (equal (imprimeur-skin-briefing-test-said browser) defaults))))
      (should-not (imprimeur-skin-briefing-test-attributes browser)))))

(ert-deftest imprimeur-skin-briefing-skims-the-body-and-keeps-the-summaries ()
  (imprimeur-skin-briefing-test-with (buffer browser "memo.md" imprimeur-skin-briefing-test-memo)
    (imprimeur-test-cdp-wait browser "document.querySelector('.briefing-masthead') !== null")
    (let ((height (lambda (selector)
                    (imprimeur-test-cdp-eval
                     browser (format "document.querySelector(%S).getBoundingClientRect().height" selector))))
          (length-before (imprimeur-test-cdp-eval browser "document.documentElement.scrollHeight")))
      (imprimeur-skin-briefing-test-choose buffer browser "skim" "on")
      (dolist (kept '(".briefing-masthead" ".briefing-bottom-line" ".briefing-callout" "#imprimeur-main > h1"
                      "#imprimeur-main > h2" ".briefing-chips"))
        (ert-info (kept) (should (> (funcall height kept) 0))))
      (dolist (hidden '(".briefing-table" "#imprimeur-main > h4"))
        (ert-info (hidden) (should (equal (funcall height hidden) 0))))
      (should (eq (alist-get 'skim (imprimeur-skin-briefing-test-said browser)) t))
      (should (< (imprimeur-test-cdp-eval browser "document.documentElement.scrollHeight") length-before))
      ;; What it hides still has a box inside it and keeps its place: the map of lines rises.
      (should (> (imprimeur-test-cdp-eval browser "document.querySelector('.briefing-table td').getBoundingClientRect().height") 0))
      (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 200, behavior: 'instant' })")
      (should (eq (imprimeur-test-cdp-eval browser "(() => {
  const tops = [...document.querySelectorAll('#imprimeur-main > [data-line]')].map((b) => b.getBoundingClientRect().top);
  return tops.length > 3 && tops.every((top, index) => index === 0 || top >= tops[index - 1]);
})()")
                  t)))))

(ert-deftest imprimeur-skin-briefing-flips-skim-by-the-memo-s-link ()
  (imprimeur-skin-briefing-test-with (buffer browser "memo.md" imprimeur-skin-briefing-test-memo)
    (imprimeur-test-cdp-wait browser "document.querySelector('.briefing-skim') !== null")
    (let ((word "document.querySelector('.briefing-skim').innerText")
          (pressed "document.querySelector('.briefing-skim').getAttribute('aria-pressed')")
          (skim "document.documentElement.getAttribute('data-briefing-skim')"))
      (should (equal (imprimeur-test-cdp-eval browser word) "Survol"))
      (imprimeur-test-cdp-click browser "document.querySelector('.briefing-skim')")
      (imprimeur-test-cdp-wait browser (concat skim " === 'on'"))
      (imprimeur-test-cdp-wait browser (concat pressed " === 'true'"))
      (should (equal (imprimeur-test-cdp-eval browser word) "Texte entier"))
      (should (equal (imprimeur-test-cdp-eval browser "location.hash") ""))
      ;; A new render keeps the view and the link's state, though the masthead is new.
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert "\n" (mapconcat #'identity (make-list 300 "mot") " ") "\n"))
      (imprimeur-test-cdp-wait browser "document.querySelector('.briefing-reading').innerText.startsWith('2')")
      (imprimeur-test-cdp-wait browser (concat pressed " === 'true'"))
      (imprimeur-test-cdp-click browser "document.querySelector('.briefing-skim')")
      (imprimeur-test-cdp-wait browser (concat skim " === null"))
      (imprimeur-test-cdp-wait browser (concat pressed " === 'false'"))
      ;; M-g o says the same to the link.
      (imprimeur-skin-briefing-test-choose buffer browser "skim" "on")
      (imprimeur-test-cdp-wait browser (concat pressed " === 'true'"))
      (should (equal (imprimeur-test-cdp-eval browser word) "Texte entier"))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-skin-briefing-opens-details-on-paper-and-closes-them-after ()
  (imprimeur-skin-briefing-test-with
      (_buffer browser "doc.md" "Words.\n\n<details id=\"a\"><summary>A</summary>Folded.</details>\n\n<details id=\"b\" open><summary>B</summary>Open.</details>\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('details') !== null")
    (let ((open "[...document.querySelectorAll('details')].map((d) => d.open)"))
      (imprimeur-test-cdp-wait browser "(window.dispatchEvent(new Event('beforeprint')), document.querySelector('#a').open)")
      (should (equal (imprimeur-test-cdp-eval browser open) [t t]))
      (imprimeur-test-cdp-eval browser "window.dispatchEvent(new Event('afterprint'))")
      (should (equal (imprimeur-test-cdp-eval browser open) [nil t])))))

(defun imprimeur-skin-briefing-test-figures (buffer browser ratio)
  "Load BUFFER's page in BROWSER under a font whose designed figures are RATIO of the plain.
The font is whatever the machine has, so the module's measure is stubbed."
  (imprimeur-test-cdp-call
   browser "Page.addScriptToEvaluateOnNewDocument"
   `(:source ,(format "const measured = Element.prototype.getBoundingClientRect;
Element.prototype.getBoundingClientRect = function () {
  if (!this.style?.cssText.includes('visibility: hidden')) return measured.call(this);
  return { width: this.style.fontVariantPosition === 'super' ? %s : 10 };
};" (* 10 ratio))))
  (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
  (imprimeur-test-cdp-wait browser "document.querySelector('.briefing-skim') !== null")
  (imprimeur-test-cdp-wait browser "document.fonts.ready.then(() => true)"))

(ert-deftest imprimeur-skin-briefing-sets-figures-by-what-the-font-holds ()
  (pcase-dolist (`(,ratio ,plain) '((0.75 nil) (1 t)))
    (ert-info ((format "%s" ratio))
      (imprimeur-skin-briefing-test-with (buffer browser "doc.md" "---\ntitle: T\nauthor: A\n---\n\n10<sup>3</sup>\n")
        (imprimeur-skin-briefing-test-figures buffer browser ratio)
        (should (eq (imprimeur-test-cdp-eval browser "document.documentElement.classList.contains('briefing-plain-figures')")
                    plain))
        (should (equal (imprimeur-skin-briefing-test-style browser "sup" "fontVariantPosition") (if plain "normal" "super")))
        (should (equal (imprimeur-skin-briefing-test-style browser "sup" "verticalAlign") (if plain "super" "baseline")))))))

(ert-deftest imprimeur-skin-briefing-leaves-nothing-after-a-swap ()
  (imprimeur-skin-briefing-test-with (buffer browser "memo.md" imprimeur-skin-briefing-test-memo)
    (imprimeur-skin-briefing-test-figures buffer browser 1)
    (imprimeur-test-cdp-wait browser "document.documentElement.classList.contains('briefing-plain-figures')")
    (imprimeur-test-cdp-click browser "document.querySelector('.briefing-skim')")
    (imprimeur-test-cdp-wait browser "document.documentElement.hasAttribute('data-briefing-skim')")
    (with-current-buffer buffer (imprimeur-choose-skin "minitel"))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.skin === 'minitel'")
    (should-not (imprimeur-skin-briefing-test-attributes browser))
    (should-not (imprimeur-test-cdp-eval browser "document.documentElement.classList.contains('briefing-plain-figures')"))
    ;; A click on a link that a filter no more writes flips nothing.
    (imprimeur-test-cdp-eval
     browser "document.getElementById('imprimeur-main').insertAdjacentHTML('beforeend', '<a class=\"briefing-skim\" href=\"#x\">x</a>'); document.querySelector('.briefing-skim').click()")
    (should-not (imprimeur-skin-briefing-test-attributes browser))))

(ert-deftest imprimeur-skin-briefing-takes-no-option-from-a-document ()
  (imprimeur-skin-briefing-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: T\nauthor: A\nskim: on\ndensity: airy\ndata-briefing-skim: on\n---\n\n"
                       "Words.\n\n<div data-briefing-skim=\"on\">Rien.</div>\n"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.briefing-masthead') !== null")
    (should-not (imprimeur-skin-briefing-test-attributes browser))))

(ert-deftest imprimeur-skin-briefing-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (with-temp-buffer
                   (insert-file-contents (expand-file-name "imprimeur-skin-briefing/README.md" repo-test-root))
                   (buffer-string)))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'briefing\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-briefing-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-briefing)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"briefing\" (imprimeur-skin-get \"briefing\") (imprimeur-skin-configured \"briefing\" (imprimeur-skin-get \"briefing\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "briefing[]" (cdr result)))))

(ert-deftest imprimeur-skin-briefing-filter-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "imprimeur-skin-briefing/assets/filter.lua" repo-test-root))
                   0))))

;;; imprimeur-skin-briefing-test.el ends here
